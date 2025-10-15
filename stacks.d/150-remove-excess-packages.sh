#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }

export DEBIAN_FRONTEND=noninteractive

# ---------------- List the apps you want to remove ----------------
APPS=(thunderbird)

# --------------- Helpers ---------------
apt_has() { dpkg -s "$1" >/dev/null 2>&1; }
snap_has() { command -v snap >/dev/null 2>&1 && snap list "$1" >/dev/null 2>&1; }
flatpak_has() { command -v flatpak >/dev/null 2>&1 && flatpak list --app | awk '{print $1}' | grep -qx "$1"; }

apt_prep_done=false
apt_remove() {
  local pkg="$1"
  if ! $apt_prep_done; then
    log "Refreshing APT metadata"
    sudo apt-get update -y || { warn "apt update failed"; exit 1; }
    apt_prep_done=true
  fi
  log "Purging APT package: $pkg"
  sudo apt-get purge -y "$pkg" "${pkg}-*" || warn "apt purge failed for $pkg"
}

snap_remove() {
  local pkg="$1"
  log "Removing Snap: $pkg"
  sudo snap remove "$pkg" || warn "snap remove failed for $pkg"
}

flatpak_remove() {
  local app="$1"
  # Try exact-name uninstall; some apps need full ID (e.g., org.mozilla.Thunderbird)
  if flatpak_has "$app"; then
    log "Removing Flatpak (by name): $app"
    flatpak uninstall -y "$app" || warn "flatpak uninstall failed for $app"
  else
    # Fallback: uninstall any ref that ends with .$app
    local refs
    refs="$(flatpak list --app --columns=application | grep -E "\.${app}\$" || true)"
    if [[ -n "${refs}" ]]; then
      while IFS= read -r ref; do
        [[ -z "$ref" ]] && continue
        log "Removing Flatpak (by ref): $ref"
        flatpak uninstall -y "$ref" || warn "flatpak uninstall failed for $ref"
      done <<< "$refs"
    else
      warn "Flatpak app not found: $app"
    fi
  fi
}

# --------------- Work ---------------
nothing_to_do=true

for app in "${APPS[@]}"; do
  found=false

  if apt_has "$app"; then
    apt_remove "$app"
    found=true
    nothing_to_do=false
  fi

  if snap_has "$app"; then
    snap_remove "$app"
    found=true
    nothing_to_do=false
  fi

  if command -v flatpak >/dev/null 2>&1; then
    # Only attempt if flatpak exists
    if flatpak_has "$app" || flatpak list --app --columns=application | grep -qE "\.${app}\$"; then
      flatpak_remove "$app"
      found=true
      nothing_to_do=false
    fi
  fi

  if ! $found; then
    log "Not installed (APT/Snap/Flatpak): $app"
  fi
done

# Clean up unused deps if we touched APT
if $apt_prep_done; then
  log "Autoremoving unused APT dependencies"
  sudo apt-get autoremove -y || warn "apt autoremove failed"
fi

if $nothing_to_do; then
  log "Nothing to remove. All apps absent."
else
  log "Done."
fi
