#!/usr/bin/env sh
# Stops the containers up.sh started, which removes them and their volumes,
# then removes everything up.sh and Conn3x created here.
set -eu
cd "$(dirname "$0")"
if [ -f container_ids ]; then
  while read -r id; do
    ${PODMAN:-podman} stop "$id" >/dev/null 2>&1 || true
  done < container_ids
fi
rm -rf id_ed25519 id_ed25519.pub known_hosts container_ids terraform.tfvars .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
echo "Removed."
