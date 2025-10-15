#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }

export DEBIAN_FRONTEND=noninteractive

# -------- Guard: skip if gh already installed --------
if command -v gh >/dev/null 2>&1; then
  log "gh already installed; skipping."
  exit 0
fi

# -------- Ensure prerequisites --------
log "Installing prerequisites (wget, ca-certificates)"
if ! sudo apt-get update -y; then
  warn "apt update failed"
  exit 1
fi
if ! sudo apt-get install -y wget ca-certificates; then
  warn "failed to install prerequisites"
  exit 1
fi

# -------- Setup keyring --------
KEYRING_DIR="/etc/apt/keyrings"
KEYFILE="$KEYRING_DIR/githubcli-archive-keyring.gpg"
REPO_FILE="/etc/apt/sources.list.d/github-cli.list"
ARCH="$(dpkg --print-architecture)"
REPO_LINE="deb [arch=${ARCH} signed-by=${KEYFILE}] https://cli.github.com/packages stable main"

log "Ensuring keyring directory exists: $KEYRING_DIR"
sudo install -d -m 0755 "$KEYRING_DIR"

# Download key if missing
if [[ ! -f "$KEYFILE" ]]; then
  log "Downloading GitHub CLI archive keyring"
  if ! wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | sudo tee "$KEYFILE" >/dev/null; then
    warn "failed to fetch GitHub CLI keyring"
    exit 1
  fi
  sudo chmod go+r "$KEYFILE"
else
  log "Keyring already present: $KEYFILE"
fi

# -------- Add repo if missing or different --------
if [[ -f "$REPO_FILE" ]] && grep -qxF "$REPO_LINE" "$REPO_FILE"; then
  log "Apt source already configured: $REPO_FILE"
else
  log "Configuring apt source: $REPO_FILE"
  echo "$REPO_LINE" | sudo tee "$REPO_FILE" >/dev/null
fi

# -------- Install gh --------
log "Updating package lists"
if ! sudo apt-get update -y; then
  warn "apt update after adding repo failed"
  exit 1
fi

log "Installing GitHub CLI (gh)"
if ! sudo apt-get install -y gh; then
  warn "apt install gh failed"
  exit 1
fi

log "Done. gh version: $(gh --version | head -n1 || echo 'installed')"
