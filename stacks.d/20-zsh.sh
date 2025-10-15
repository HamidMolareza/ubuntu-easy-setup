#!/usr/bin/env bash
set -euo pipefail
echo "[zsh] Installing zsh + oh-my-zsh"
sudo apt-get install -y zsh
chsh -s "$(command -v zsh)" "$USER" || true
RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
