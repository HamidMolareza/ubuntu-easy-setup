#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }

# ------------------------ Config ------------------------
SAFEBOX="${SAFEBOX:-$HOME/Private}"

DEFAULT_ITEMS=(
  ".zsh_history"
  ".bash_history"
  ".ssh"
  ".gnupg"
  ".aws"
  ".kube"
  ".pki"
  ".config/git"
  ".gitconfig"
  ".git-credentials"
)

ITEMS=("$@")
if [ "${#ITEMS[@]}" -eq 0 ]; then
  ITEMS=("${DEFAULT_ITEMS[@]}")
fi

# ------------------------ Helpers ------------------------
# Merge two history files (dedup lines, keep first occurrence)
merge_history_files() {
  local src="$1" dst="$2" tmp
  tmp="$(mktemp)"
  # Ensure destination exists so awk has a file to read
  : > "$dst"
  # concatenate dest then src so older content stays earlier
  awk '{
    if (!seen[$0]++) print
  }' "$dst" "$src" > "$tmp"
  mv "$tmp" "$dst"
}

# Generic append with a clear separator (for non-history files)
append_with_separator() {
  local src="$1" dst="$2"
  {
    printf '\n# ---- Merged on %s from: %s ---- #\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$src"
    cat "$src"
    printf '\n# ---- End merge ---- #\n'
  } >> "$dst"
}

# Fix safe permissions inside ~/.ssh
fix_ssh_perms() {
  local base="$1"
  [ -d "$base" ] || return 0
  find "$base" -type d -exec chmod 700 {} +
  find "$base" -type f -name "*.pub" -exec chmod 644 {} +
  # private keys + config/known_hosts 600
  find "$base" -type f ! -name "*.pub" -exec chmod 600 {} +
}

# Merge/copy a directory tree from src -> dst (non-destructive to dst)
merge_dir() {
  local src="$1" dst="$2"
  mkdir -p "$dst"
  rsync -a --ignore-existing "$src"/ "$dst"/
}

# Decide if every requested item is already symlinked into the safebox
all_items_linked() {
  local rel src dst
  for rel in "${ITEMS[@]}"; do
    src="$HOME/$rel"
    dst="$SAFEBOX/$rel"
    if [ -e "$src" ]; then
      if [ -L "$src" ]; then
        local target
        target="$(readlink "$src" || true)"
        [[ "$target" == "$dst" ]] || return 1
      else
        return 1
      fi
    else
      # src missing is fine only if dst also missing (nothing to do),
      # but that still means not "fully linked"
      [ -e "$dst" ] || continue
      return 1
    fi
  done
  return 0
}

process_item() {
  local rel="$1"
  local src="$HOME/$rel"
  local dst="$SAFEBOX/$rel"

  # If src is already a symlink to dst, skip
  if [ -L "$src" ] && [ "$(readlink "$src")" = "$dst" ]; then
    log "✓ $rel already linked to safebox"
    return 0
  fi

  # If nothing at src but something at dst, just ensure symlink
  if [ ! -e "$src" ] && [ -e "$dst" ]; then
    log "Linking missing $rel -> safebox"
    mkdir -p "$(dirname "$src")"
    ln -s "$dst" "$src"
    return 0
  fi

  # If neither exists, nothing to do
  if [ ! -e "$src" ] && [ ! -e "$dst" ]; then
    log "… Skipping $rel (not found)"
    return 0
  fi

  # Ensure destination parent exists
  mkdir -p "$(dirname "$dst")"

  # Directories (non-symlink)
  if [ -d "$src" ] && [ ! -L "$src" ]; then
    if [ -e "$dst" ]; then
      log "Merging directory $rel into safebox"
      merge_dir "$src" "$dst"
      rm -rf "$src"
    else
      log "Moving directory $rel into safebox"
      mv "$src" "$dst"
    fi
    ln -s "$dst" "$src"
    if [ "$rel" = ".ssh" ]; then
      fix_ssh_perms "$dst"
    fi
    return 0
  fi

  # Regular files (non-symlink)
  if [ -f "$src" ] && [ ! -L "$src" ]; then
    if [ -e "$dst" ]; then
      log "Combining file $rel into safebox"
      case "$rel" in
        .zsh_history|.bash_history)
          merge_history_files "$src" "$dst"
          ;;
        *)
          append_with_separator "$src" "$dst"
          ;;
      esac
      rm -f "$src"
    else
      log "Moving file $rel into safebox"
      mkdir -p "$(dirname "$dst")"
      mv "$src" "$dst"
    fi
    ln -s "$dst" "$src"
    return 0
  fi

  # If src is a symlink but pointing elsewhere, relink to safebox
  if [ -L "$src" ]; then
    log "Relinking $rel to safebox"
    rm -f "$src"
    # If dst missing, create an empty file as a safe default
    if [ ! -e "$dst" ]; then
      mkdir -p "$(dirname "$dst")"
      : > "$dst"
    fi
    ln -s "$dst" "$src"
    return 0
  fi

  warn "Skipping $rel (unsupported file type)"
}

# ------------------------ Guard ------------------------
# Skip work if everything is already linked into the safebox
if all_items_linked; then
  log "All requested items already linked to $SAFEBOX; nothing to do."
  exit 0
fi

# ------------------------ Main ------------------------
main() {
  # Preflight: rsync is required for safe directory merges
  if ! command -v rsync >/dev/null 2>&1; then
    warn "rsync is required. Please install rsync and re-run."
    exit 1
  fi

  log "Using safebox: $SAFEBOX"
  mkdir -p "$SAFEBOX"

  local rel
  for rel in "${ITEMS[@]}"; do
    process_item "$rel"
  done

  # Final: ensure .ssh perms if linked
  if [ -e "$SAFEBOX/.ssh" ]; then
    fix_ssh_perms "$SAFEBOX/.ssh"
  fi

  log "Done."
}

main "$@"
