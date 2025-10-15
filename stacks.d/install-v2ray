#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }

export DEBIAN_FRONTEND=noninteractive

# -------- Guard: skip if v2ray service is installed & active --------
if command -v v2ray >/dev/null 2>&1 && systemctl is-active --quiet v2ray; then
  log "V2Ray already installed and running; skipping."
  exit 0
fi

# -------- Ensure prerequisites --------
log "Installing prerequisites (curl)"
if ! command -v curl >/dev/null 2>&1; then
  if ! sudo apt-get update -y; then
    warn "apt update failed"
    exit 1
  fi
  if ! sudo apt-get install -y curl; then
    warn "failed to install curl"
    exit 1
  fi
else
  log "curl already present"
fi

# -------- Install / update V2Ray via official script --------
log "Running V2Ray installer"
if ! bash <(curl -fsSL https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh); then
  warn "V2Ray install script failed"
  exit 1
fi

# -------- Enable & start service (idempotent) --------
log "Reloading systemd units"
sudo systemctl daemon-reload

log "Enabling v2ray to start on boot"
if ! sudo systemctl enable v2ray >/dev/null 2>&1; then
  warn "failed to enable v2ray (continuing)"
fi

log "Starting (or restarting) v2ray"
if systemctl is-active --quiet v2ray; then
  sudo systemctl restart v2ray
else
  sudo systemctl start v2ray
fi

# -------- Show concise status --------
log "V2Ray service status:"
sudo systemctl --no-pager --full status v2ray || true

# -------- Tips --------
log "UFW tips (optional):"
echo "  sudo ufw allow <port>/tcp"
echo "  sudo ufw reload"

log "Done."
