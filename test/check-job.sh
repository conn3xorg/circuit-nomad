#!/usr/bin/env sh
# Run on a server, with the job file on stdin: bootstraps ACLs if nobody has,
# checks anonymous requests are refused, runs the job, and checks a client
# finished it and printed its line. Takes the expected number of servers and
# clients. The bootstrap token only ever lives in this script's memory.
set -eu
servers=$1
clients=$2
job=$(mktemp)
cat > "$job"

for _ in $(seq 60); do
  [ "$(curl -sS http://127.0.0.1:4646/v1/status/peers | tr ',' '\n' | grep -c :)" = "$servers" ] \
    && curl -sS http://127.0.0.1:4646/v1/status/leader | grep -q : && break
  sleep 2
done
curl -sS http://127.0.0.1:4646/v1/status/leader | grep -q : || { echo "No leader." >&2; exit 1; }

[ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:4646/v1/jobs)" = 403 ] || { echo "An anonymous request wasn't refused." >&2; exit 1; }

# A new leader can take a moment to be ready for this.
NOMAD_TOKEN=
for _ in $(seq 30); do
  NOMAD_TOKEN=$(nomad acl bootstrap -json | sed -n 's/.*"SecretID": *"\([^"]*\)".*/\1/p')
  [ -n "$NOMAD_TOKEN" ] && break
  sleep 2
done
[ -n "$NOMAD_TOKEN" ] || { echo "Couldn't bootstrap ACLs." >&2; exit 1; }
export NOMAD_TOKEN

# On a follower, the new token takes a moment to arrive.
for _ in $(seq 30); do
  [ "$(nomad server members 2>/dev/null | grep -c alive)" = "$servers" ] && break
  sleep 2
done
[ "$(nomad server members | grep -c alive)" = "$servers" ] || { nomad server members; exit 1; }
nomad operator gossip keyring list | grep -q .

for _ in $(seq 60); do
  [ "$(nomad node status | grep -c ready)" = "$clients" ] && break
  sleep 2
done
nomad node status
[ "$(nomad node status | grep -c ready)" = "$clients" ]

nomad job run -detach "$job" >/dev/null
for _ in $(seq 60); do
  status=$(nomad job allocs -t '{{range .}}{{.ClientStatus}}{{end}}' hello)
  [ "$status" = complete ] && break
  sleep 2
done
nomad job status hello
[ "$status" = complete ]
alloc=$(nomad job allocs -t '{{range .}}{{.ID}}{{end}}' hello)
nomad alloc logs "$alloc" hello | grep 'hello from'
