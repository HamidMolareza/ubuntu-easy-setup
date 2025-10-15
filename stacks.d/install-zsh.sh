#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }

# -------- Guard: skip if Oh My Zsh already present (covers zsh & plugins config path) --------
if [[ -d "$HOME/.oh-my-zsh" ]]; then
  log "Oh My Zsh already installed; skipping setup."
  exit 0
fi

# -------- Prereqs --------
log "Updating package list and installing prerequisites"
export DEBIAN_FRONTEND=noninteractive
if ! sudo apt-get update -y; then
  warn "apt update failed"
  exit 1
fi
if ! sudo apt-get install -y zsh git curl fzf autojump; then
  warn "apt install failed"
  exit 1
fi

# -------- Make zsh default (only if not already) --------
if [[ "${SHELL:-}" != */zsh ]]; then
  log "Setting default shell to zsh for user: $USER"
  if ! chsh -s "$(command -v zsh)"; then
    warn "Failed to change default shell with chsh"
  fi
else
  log "Default shell already zsh; skipping chsh"
fi

# -------- Install Oh My Zsh (unattended; don't auto-run zsh) --------
log "Installing Oh My Zsh (unattended)"
if ! RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
  "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"; then
  warn "Oh My Zsh install failed"
  exit 1
fi

# Determine ZSH_CUSTOM now that OMZ is installed
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# -------- Install plugins (idempotent) --------
log "Installing zsh-autosuggestions plugin"
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
  git clone https://github.com/zsh-users/zsh-autosuggestions.git \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
else
  log "zsh-autosuggestions already present; skipping clone"
fi

log "Installing zsh-syntax-highlighting plugin"
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
else
  log "zsh-syntax-highlighting already present; skipping clone"
fi

# -------- Enable plugins in ~/.zshrc (safe edit) --------
log "Ensuring plugins are enabled in ~/.zshrc"
ZSHRC="$HOME/.zshrc"
touch "$ZSHRC"

# Build desired plugin list (git is default; add our tools)
desired_plugins=(git zsh-autosuggestions zsh-syntax-highlighting autojump fzf)

# Create a plugins line from array
plugins_line="plugins=(${desired_plugins[*]})"

if grep -qE '^\s*plugins\s*\(' "$ZSHRC"; then
  # Replace the existing plugins=() line entirely
  sed -i.bak -E "s|^\s*plugins\s*\(.*\)|$plugins_line|" "$ZSHRC"
else
  # Append if not present
  {
    echo ""
    echo "# Managed by setup script"
    echo "$plugins_line"
  } >> "$ZSHRC"
fi

# Ensure autojump is sourced when using its plugin (some distros require this)
if ! grep -q "/usr/share/autojump/autojump.zsh" "$ZSHRC"; then
  echo '[[ -r /usr/share/autojump/autojump.zsh ]] && . /usr/share/autojump/autojump.zsh' >> "$ZSHRC"
fi

# fzf keybindings (if package provided shell integration)
if [[ -d "/usr/share/doc/fzf" ]] && ! grep -q "key-bindings.zsh" "$ZSHRC"; then
  echo '[[ -r /usr/share/doc/fzf/examples/key-bindings.zsh ]] && . /usr/share/doc/fzf/examples/key-bindings.zsh' >> "$ZSHRC"
  echo '[[ -r /usr/share/doc/fzf/examples/completion.zsh ]] && . /usr/share/doc/fzf/examples/completion.zsh' >> "$ZSHRC"
fi

# -------- (Optional) Powerlevel10k theme --------
# Uncomment to install + activate:
# log "Installing Powerlevel10k theme"
# if [[ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]]; then
#   git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
#     "$ZSH_CUSTOM/themes/powerlevel10k"
# fi
# if grep -qE '^\s*ZSH_THEME=' "$ZSHRC"; then
#   sed -i.bak -E 's|^\s*ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC"
# else
#   echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$ZSHRC"
# fi

# -------- Final notes --------
log "Zsh + Oh My Zsh installed. Plugins configured: ${desired_plugins[*]}"
log "Open a new terminal OR run: exec zsh   to start using the new configuration."
log "Done."
