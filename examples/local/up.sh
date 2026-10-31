#!/usr/bin/env sh
# Starts two throwaway hosts, a server on 127.0.0.1:$PORT (default 2222) and a
# client on the next port, with a fresh SSH key and their host keys in
# ./known_hosts. CONTAINERFILE picks another image, such as one of Conn3x's
# test images. Needs Podman, since the hosts run systemd. The client starts
# jobs in chroots and cgroups of its own, so the containers are privileged,
# which is simplest with rootful Podman:
# CONTAINER_CONNECTION=podman-machine-default-root on a Mac, or
# PODMAN="sudo podman" on Linux.
set -eu
cd "$(dirname "$0")"
port=${PORT:-2222}
containerfile=${CONTAINERFILE:-Containerfile}
name=${NAME:-circuit-nomad}

podman=${PODMAN:-podman}
[ -f id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -C "$name" -f id_ed25519
$podman build -q -f "$containerfile" -t "$name" "$(dirname "$containerfile")" >/dev/null
: > known_hosts
: > container_ids

for role in server client; do
  $podman run -d --rm --name "$name-$role" --systemd=always --privileged -v /opt/nomad \
    -p "127.0.0.1:$port:22" "$name" >> container_ids
  $podman exec -i "$name-$role" sh -c 'cat > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys' < id_ed25519.pub
  $podman exec "$name-$role" timeout 60 systemctl is-system-running --wait >/dev/null 2>&1 || true
  # Fedora's udev derives eth0's MAC address from the machine ID, which both
  # containers share, and two hosts with one address can't reach each other.
  $podman exec "$name-$role" ip link set eth0 address "$($podman inspect -f '{{.NetworkSettings.MacAddress}}' "$name-$role")" 2>/dev/null || true
  for try in 1 2 3 4 5 6 7 8 9 10; do
    keys=$(ssh-keyscan -p "$port" 127.0.0.1 2>/dev/null) && [ -n "$keys" ] && break
    [ "$try" = 10 ] && { echo "The $role container started, but SSH didn't answer on 127.0.0.1:$port." >&2; exit 1; }
    sleep 1
  done
  echo "$keys" >> known_hosts
  port=$((port + 1))
done

echo "server_ip = \"$($podman inspect -f '{{.NetworkSettings.IPAddress}}' "$name-server")\"" > terraform.tfvars
echo "port      = ${PORT:-2222}" >> terraform.tfvars
echo "Ready. Now run: conn3x init && conn3x apply"
