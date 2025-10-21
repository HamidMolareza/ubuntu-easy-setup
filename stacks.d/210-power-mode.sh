#!/usr/bin/env bash

set -euo pipefail

log()  { echo "$*"; }
warn() { echo "[WARN] $*" >&2; }

# --- helpers --------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

gs_set() {
  local schema="$1" key="$2" value="$3"
  if gsettings set "$schema" "$key" "$value"; then
    log "gsettings: set ${schema} ${key} -> ${value}"
  else
    warn "gsettings: failed to set ${schema} ${key}"
  fi
}

# --- Power Mode (NOT a gsettings key) -------------------------------------
# GNOME’s power mode is handled by power-profiles-daemon via powerprofilesctl.

if ! have powerprofilesctl; then
  warn "powerprofilesctl not found; attempting to install power-profiles-daemon (needs sudo)."
  if have sudo && have apt-get; then
    sudo apt-get update -y || warn "apt-get update failed"
    sudo apt-get install -y power-profiles-daemon || warn "install failed"
    if systemctl list-unit-files | grep -q '^power-profiles-daemon\.service'; then
      sudo systemctl enable --now power-profiles-daemon.service || warn "failed to enable power-profiles-daemon"
    fi
  else
    warn "Cannot install power-profiles-daemon automatically (sudo/apt-get not available)."
  fi
fi

if have powerprofilesctl; then
  if powerprofilesctl list | grep -q '\*.*performance\| performance'; then
    if powerprofilesctl set performance; then
      log "Power profile set to: performance"
    else
      warn "Could not set performance (may be blocked on battery or unsupported hardware)."
    fi
  else
    warn "Performance profile not available on this machine; leaving default."
  fi
else
  warn "powerprofilesctl still unavailable; skip setting Power Mode."
fi

log "Done."
