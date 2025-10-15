#!/usr/bin/env bash

set -euo pipefail

echo "[node] Installing Node.js via nvm"
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
# shellcheck source=/dev/null
. "$HOME/.nvm/nvm.sh"
nvm install --lts
