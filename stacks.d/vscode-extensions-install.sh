#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }

# --- Config ---
# Provide your own list file as $1 OR set EXT_URL to download.
EXT_URL="${EXT_URL:-https://gist.githubusercontent.com/HamidMolareza/51095290142d1fb83b15c0923db82c38/raw/2367257a899e2b8eaedf8153f245d7e926634c03/My%2520VSCode%2520Extensions}"

# Prefer explicit override, otherwise auto-detect code vs code-insiders
CODE_BIN="${CODE_BIN:-}"
if [[ -z "${CODE_BIN}" ]]; then
  if command -v code >/dev/null 2>&1; then
    CODE_BIN="code"
  elif command -v code-insiders >/dev/null 2>&1; then
    CODE_BIN="code-insiders"
  else
    warn "VS Code CLI not found (code/code-insiders). Install VS Code and ensure the CLI is on PATH."
    exit 1
  fi
fi

# --- Input handling (filename arg optional) ---
LIST_FILE="${1:-}"
TEMP_CREATED=false

download_list() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$out"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$url" -O "$out"
  else
    warn "Neither curl nor wget is available to download the list."
    exit 1
  fi
}

if [[ -z "${LIST_FILE}" ]]; then
  LIST_FILE="$(mktemp)"
  TEMP_CREATED=true
  log "No list filename provided; downloading to temporary file"
  download_list "$EXT_URL" "$LIST_FILE"
else
  # If a filename is given but doesn't exist, fetch to it
  if [[ ! -f "$LIST_FILE" ]]; then
    log "List file not found, downloading to: $LIST_FILE"
    mkdir -p "$(dirname "$LIST_FILE")"
    download_list "$EXT_URL" "$LIST_FILE"
  else
    log "Using existing list file: $LIST_FILE"
  fi
fi

# Ensure the list file is non-empty
if [[ ! -s "$LIST_FILE" ]]; then
  warn "Extension list is empty: $LIST_FILE"
  $TEMP_CREATED && rm -f "$LIST_FILE"
  exit 1
fi

# Gather currently installed extensions (publisher.name)
mapfile -t INSTALLED < <("$CODE_BIN" --list-extensions || true)

is_installed() {
  local want="$1" base
  # If the line has a version suffix like publisher.name@1.2.3, compare only the id part
  base="${want%%@*}"
  # Exact match among installed IDs
  for e in "${INSTALLED[@]}"; do
    [[ "$e" == "$base" ]] && return 0
  done
  return 1
}

installed_count=0
skipped_count=0
total_count=0

log "Installing extensions using: $CODE_BIN"
while IFS= read -r line || [[ -n "$line" ]]; do
  # Trim leading/trailing whitespace
  ext="$(echo "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  # Skip blanks and comments
  [[ -z "$ext" ]] && continue
  [[ "$ext" =~ ^# ]] && continue

  total_count=$((total_count + 1))
  if is_installed "$ext"; then
    log "Already installed: $ext"
    skipped_count=$((skipped_count + 1))
    continue
  fi

  log "Installing: $ext"
  if "$CODE_BIN" --install-extension "$ext" >/dev/null; then
    installed_count=$((installed_count + 1))
  else
    warn "Failed to install: $ext"
  fi
done < "$LIST_FILE"

$TEMP_CREATED && rm -f "$LIST_FILE"

log "Done. Processed: $total_count | Installed: $installed_count | Skipped: $skipped_count"
