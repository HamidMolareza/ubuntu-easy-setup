#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }

need_pkg() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "Installing $1"
    export DEBIAN_FRONTEND=noninteractive
    if ! sudo apt-get update -y; then
      warn "apt update failed"
      exit 1
    fi
    if ! sudo apt-get install -y "$1"; then
      warn "apt install $1 failed"
      exit 1
    fi
  fi
}

has_rule() {
  # Case-insensitive grep of current rules; avoids duplicates
  sudo ufw status | grep -iq -- "$1"
}

ensure_rule() {
  local rule="$1"
  if has_rule "$2"; then
    log "Rule already present: $rule"
  else
    log "Adding rule: ufw $rule"
    sudo ufw "$rule"
  fi
}

# -------- Guard: skip if already configured to desired state --------
if command -v ufw >/dev/null 2>&1; then
  if sudo ufw status | grep -q "Status: active"; then
    if sudo ufw status verbose | grep -q "Default: deny (incoming), allow (outgoing)"; then
      if has_rule "http" && has_rule "https" && has_rule "dns"; then
        log "UFW already active with desired defaults and rules; skipping."
        exit 0
      fi
    fi
  fi
fi

# -------- Ensure ufw exists --------
need_pkg ufw

# -------- Enable UFW (non-interactive) --------
log "Enabling UFW"
sudo ufw --force enable

# -------- Set default policies --------
log "Setting default policies"
sudo ufw default deny incoming
sudo ufw default allow outgoing

# -------- Allow common services (idempotent) --------
ensure_rule "allow http"  "http"
ensure_rule "allow https" "https"
ensure_rule "allow dns"   "dns"

# Optional: allow SSH (uncomment to enable, or set SSH_PORT to a custom port)
# SSH_PORT="${SSH_PORT:-22}"
# ensure_rule "allow ${SSH_PORT}/tcp" " ${SSH_PORT}/tcp"

# -------- Enable logging --------
log "Enabling UFW logging"
sudo ufw logging on

# -------- Reload & show status --------
log "Reloading UFW"
sudo ufw reload

log "Current UFW status:"
sudo ufw status verbose

log "Done."
