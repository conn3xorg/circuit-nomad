# Local example

Applies circuit-nomad to two throwaway containers with systemd, a server and a client, then runs a small job on the client. You need Conn3x and Podman. Nomad itself is under the Business Source License; see the main [README](../../README.md#nomads-licence).

The client starts jobs in chroots and cgroups of its own, so the containers run privileged, which is simplest with rootful Podman. On a Mac, use the Podman machine's root connection. On Linux, use `sudo podman`:

```sh
export CONTAINER_CONNECTION=podman-machine-default-root   # macOS
export PODMAN="sudo podman"                               # Linux
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The second plan says `No changes.` `up.sh` writes the server's address and port to `terraform.tfvars`, so you don't pass them yourself. To see the cluster run a job, bootstrap its ACLs and hand it `hello.nomad.hcl`, which `test/check-job.sh` does in one go:

```sh
podman cp ../../test/check-job.sh circuit-nomad-server:/tmp/check-job.sh
podman exec -i circuit-nomad-server sh /tmp/check-job.sh 1 1 < hello.nomad.hcl
```

It ends with the line the job printed, `hello from` and an allocation ID. ACLs can only be bootstrapped once, so that script works once per cluster.

`up.sh` listens on `127.0.0.1:2222` for the server and `2223` for the client. Set `PORT` for another pair. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` stops the containers, which removes them and their volumes, and removes the key and the state.
