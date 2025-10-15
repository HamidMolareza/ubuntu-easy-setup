#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }

export DEBIAN_FRONTEND=noninteractive

# -------- Guard: skip if boot-repair already installed --------
if command -v boot-repair >/dev/null 2>&1; then
  log "boot-repair already installed; skipping."
  exit 0
fi

# -------- Ensure prerequisites for add-apt-repository --------
log "Installing prerequisites"
if ! sudo apt-get update -y; then
  warn "apt update failed"
  exit 1
fi
if ! dpkg -s software-properties-common >/dev/null 2>&1; then
  if ! sudo apt-get install -y software-properties-common; then
    warn "Failed to install software-properties-common"
    exit 1
  fi
else
  log "software-properties-common already present"
fi

# -------- Add PPA if missing --------
log "Ensuring PPA yannubuntu/boot-repair is configured"
if ! ls /etc/apt/sources.list.d/ 2>/dev/null | grep -q '^yannubuntu-ubuntu-boot-repair'; then
  if ! sudo add-apt-repository -y ppa:yannubuntu/boot-repair; then
    warn "Failed to add PPA yannubuntu/boot-repair"
    exit 1
  fi
else
  log "PPA already present; skipping add-apt-repository"
fi

# -------- Install boot-repair --------
log "Updating package lists"
if ! sudo apt-get update -y; then
  warn "apt update after adding PPA failed"
  exit 1
fi

log "Installing boot-repair"
if ! sudo apt-get install -y boot-repair; then
  warn "apt install boot-repair failed"
  exit 1
fi

log "Done. Launch with: boot-repair"
