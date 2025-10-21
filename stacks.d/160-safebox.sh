#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }

export DEBIAN_FRONTEND=noninteractive

# ---- Must run as a regular user (not root) ----
if [[ "${EUID:-0}" -eq 0 ]]; then
  warn "Do not run this script as root. Re-run as your normal user."
  exit 1
fi

# ---- Guards: skip if already configured ----
if [[ -d "$HOME/.Private" || -d "$HOME/.ecryptfs" ]]; then
  log "Encrypted Private directory already appears to be configured; skipping setup."
  log "If you need to mount it:  ecryptfs-mount-private"
  exit 0
fi

# ---- Ensure ecryptfs-utils is installed ----
if ! command -v ecryptfs-setup-private >/dev/null 2>&1; then
  log "Installing ecryptfs-utils"
  sudo apt-get update -y || { warn "apt update failed"; exit 1; }
  sudo apt-get install -y ecryptfs-utils || { warn "apt install ecryptfs-utils failed"; exit 1; }
else
  log "ecryptfs-utils already installed"
fi

# ---- Run interactive setup (creates ~/.Private and ~/Private) ----
log "Running ecryptfs-setup-private (interactive). You will be prompted for a passphrase."
if ! ecryptfs-setup-private; then
  warn "ecryptfs-setup-private failed"
  exit 1
fi

# ---- Post-setup tips ----
log "Setup complete."
log "Mount your encrypted directory with:  ecryptfs-mount-private"
log "Unmount with:                        ecryptfs-umount-private"
log "Docs: https://help.ubuntu.com/community/EncryptedPrivateDirectory"
