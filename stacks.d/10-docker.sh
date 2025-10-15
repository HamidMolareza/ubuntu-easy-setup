#!/usr/bin/env bash

set -euo pipefail

log()  { echo "$*"; }
warn() { echo "[WARN] $*" >&2; }

# Guard: skip work if already done
if command -v docker >/dev/null 2>&1; then
  log "docker already installed; skipping."
  exit 0
fi

log "uninstall all conflicting packages"
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done

log "Installing docker"

# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Fix permission denied issue:
sudo usermod -aG docker "$USER"
sudo chown root:docker /var/run/docker.sock
sudo service docker restart

# Arvan docker registry
sudo bash -c 'cat > /etc/docker/daemon.json <<EOF
{
  "insecure-registries" : ["https://docker.arvancloud.ir"],
  "registry-mirrors": ["https://docker.arvancloud.ir"]
}
EOF' 
docker logout
sudo systemctl restart docker 

log "Done."
