#!/usr/bin/env bash
# stacks.d/10-example.sh
set -euo pipefail

log()  { echo "$*"; }
warn() { echo "[WARN] $*" >&2; }

# (Optional) use values from config.env if present
: "${MY_OPTIONAL_VAR:=default_value}"

# Detect Ubuntu version if you need it
UBU_CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME}")"

# Guard: skip work if already done
if command -v example-tool >/dev/null 2>&1; then
  log "example-tool already installed; skipping."
  exit 0
fi

log "Installing example-tool (for ${UBU_CODENAME})"
if ! sudo apt-get install -y example-tool; then
  warn "apt install failed"
  exit 1
fi

log "Done."
