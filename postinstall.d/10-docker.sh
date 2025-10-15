#!/usr/bin/env bash
set -euo pipefail
# Put any advanced/isolated setup here
echo "Configuring Docker daemon default address pools..."
sudo mkdir -p /etc/docker
if [[ ! -f /etc/docker/daemon.json ]]; then
  cat <<'JSON' | sudo tee /etc/docker/daemon.json >/dev/null
{
  "bip": "172.31.0.1/16",
  "default-address-pools": [{"base":"172.80.0.0/16","size":24}]
}
JSON
  sudo systemctl restart docker || true
fi
