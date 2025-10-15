#!/usr/bin/env bash
set -euo pipefail

#=== metadata & logging =======================================================#
SCRIPT_NAME="$(basename "$0")"
LOG_DIR="${HOME}/.bootstrap-logs"
LOG_FILE="${LOG_DIR}/$(date +%F_%H-%M-%S).log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "==> ${SCRIPT_NAME} starting at $(date)"

#=== helpers ==================================================================#
require_sudo() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "This script needs sudo for some steps. You may be prompted for your password."
    sudo -v
    # keep-alive: update existing `sudo` time stamp if set, otherwise do nothing.
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

ubuntu_codename() {
  . /etc/os-release
  echo "${UBUNTU_CODENAME:-}"
}

is_wsl() {
  grep -qi microsoft /proc/version 2>/dev/null
}

# Idempotent add-apt-repository
add_ppa() {
  local ppa="$1"
  if ! grep -Rq "$ppa" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    sudo add-apt-repository -y "ppa:${ppa}"
  else
    echo "PPA ${ppa} already present, skipping."
  fi
}

#=== config ===================================================================#
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${ROOT_DIR}/config.env"
APT_LIST="${ROOT_DIR}/packages.txt"
SNAPS_LIST="${ROOT_DIR}/snaps.txt"
FLATPAKS_LIST="${ROOT_DIR}/flatpaks.txt"
POST_D="${ROOT_DIR}/postinstall.d"

# shellcheck source=/dev/null
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

export DEBIAN_FRONTEND=noninteractive

# Defaults if not set in config.env
TIMEZONE="${TIMEZONE:-Asia/Tehran}"
LOCALE="${LOCALE:-en_US.UTF-8}"
GIT_NAME="${GIT_NAME:-}"
GIT_EMAIL="${GIT_EMAIL:-}"
DOTFILES_REPO="${DOTFILES_REPO:-}"             # e.g. "git@github.com:user/dotfiles.git"
DOTFILES_BOOTSTRAP="${DOTFILES_BOOTSTRAP:-}"   # e.g. "setup.sh"
SSH_KEY_TYPE="${SSH_KEY_TYPE:-ed25519}"

#=== sanity checks ============================================================#
if [[ ! -f /etc/os-release ]]; then
  echo "This script is intended for Ubuntu. /etc/os-release not found."
  exit 1
fi
. /etc/os-release
if [[ "${ID}" != "ubuntu" ]]; then
  echo "Detected ID=${ID}. This script targets Ubuntu; continue at your own risk."
fi

echo "==> Ubuntu ${VERSION} (${UBUNTU_CODENAME})"
require_sudo

#=== apt base =================================================================#
echo "==> Refreshing apt index & upgrading..."
sudo apt-get update -y
sudo apt-get dist-upgrade -y

echo "==> Installing base tooling..."
BASE_DEBS=(build-essential curl wget git ca-certificates gnupg lsb-release apt-transport-https software-properties-common ufw unzip zip jq)
sudo apt-get install -y "${BASE_DEBS[@]}"

#=== timezone & locale ========================================================#
echo "==> Setting timezone to ${TIMEZONE}"
sudo timedatectl set-timezone "$TIMEZONE" || true

echo "==> Ensuring locale ${LOCALE}"
if ! locale -a | grep -q "^${LOCALE}$"; then
  sudo locale-gen "$LOCALE"
fi
sudo update-locale LANG="${LOCALE}"

#=== unattended security updates =============================================#
echo "==> Enabling unattended-upgrades"
sudo apt-get install -y unattended-upgrades
sudo dpkg-reconfigure -f noninteractive unattended-upgrades

#=== firewall (simple) ========================================================#
echo "==> Configuring UFW"
sudo ufw allow OpenSSH || true
sudo ufw --force enable

#=== PPAs or vendor repos (optional examples) =================================#
# Example: Git PPA for newer git (comment out if not needed)
# add_ppa "git-core/ppa" && sudo apt-get update -y && sudo apt-get install -y git

#=== install apt packages from packages.txt ===================================#
if [[ -f "$APT_LIST" ]]; then
  echo "==> Installing apt packages from ${APT_LIST}"
  mapfile -t pkgs < <(grep -Ev '^\s*#|^\s*$' "$APT_LIST")
  if ((${#pkgs[@]})); then
    sudo apt-get install -y "${pkgs[@]}"
  else
    echo "No apt packages listed."
  fi
else
  echo "No ${APT_LIST} found. Skip apt bulk install."
fi

#=== snaps ====================================================================#
if have snap && [[ -f "$SNAPS_LIST" ]]; then
  echo "==> Installing snaps from ${SNAPS_LIST}"
  while read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    # split first token as snap name, rest as flags
    name="$(awk '{print $1}' <<<"$line")"
    flags="$(awk '{$1=""; sub("^ ", ""); print}' <<<"$line")"
    if snap list | awk '{print $1}' | grep -qx "$name"; then
      echo "snap ${name} already installed, skipping."
    else
      sudo snap install $name $flags
    fi
  done < "$SNAPS_LIST"
fi

#=== flatpak (optional) =======================================================#
if [[ -f "$FLATPAKS_LIST" ]]; then
  if ! have flatpak; then
    sudo apt-get install -y flatpak
    # GNOME Software plugin for Flatpak (desktop)
    if have gnome-shell; then
      sudo apt-get install -y gnome-software-plugin-flatpak
    fi
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
  echo "==> Installing flatpaks"
  while read -r app; do
    [[ -z "$app" || "$app" =~ ^# ]] && continue
    if flatpak list | awk '{print $1}' | grep -qx "$app"; then
      echo "flatpak ${app} already installed."
    else
      flatpak install -y flathub "$app"
    fi
  done < "$FLATPAKS_LIST"
fi

#=== developer stacks (examples) ==============================================#
install_docker() {
  if have docker; then echo "Docker present, skipping."; return; fi
  echo "==> Installing Docker Engine (official repo)"
  sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release; echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER" || true
}

install_zsh_ohmyzsh() {
  if [[ -d "$HOME/.oh-my-zsh" ]]; then echo "oh-my-zsh present, skipping."; return; fi
  echo "==> Installing zsh + oh-my-zsh"
  sudo apt-get install -y zsh
  chsh -s "$(command -v zsh)" "$USER" || true
  RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
}

install_node() {
  if have node; then echo "Node present, skipping."; return; fi
  echo "==> Installing Node.js (nvm)"
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  # shellcheck source=/dev/null
  . "$HOME/.nvm/nvm.sh"
  nvm install --lts
}

install_python_tooling() {
  echo "==> Installing Python dev tooling"
  sudo apt-get install -y python3-pip python3-venv python3-dev
  pip3 install --user pipx || true
  ~/.local/bin/pipx ensurepath || true
}

#=== custom stacks: run any executable *.sh in stacks.d =======================#
TASKS_DIR="${ROOT_DIR}/stacks.d"

run_custom_scripts() {
  local dir="$1"
  echo "==> Running custom stack scripts in ${dir}"

  if [[ ! -d "$dir" ]]; then
    echo "!! Directory ${dir} not found. Skipping."
    return
  fi

  shopt -s nullglob
  # Sorted lexicographically -> numeric prefixes control order
  local scripts=( "$dir"/*.sh )

  if ((${#scripts[@]} == 0)); then
    echo "!! No *.sh scripts found in ${dir}. Skipping."
    return
  fi

  for f in "${scripts[@]}"; do
    if [[ -f "$f" && -x "$f" ]]; then
      echo "--> $(basename "$f"): starting"
      if ! "$f"; then
        rc=$?
        echo "!! $(basename "$f") exited with status ${rc}. Continuing."
      else
        echo "--> $(basename "$f"): done"
      fi
    else
      echo "!! Skipping $(basename "$f")) — file missing or not executable."
    fi
  done
  shopt -u nullglob
}

run_custom_scripts "$TASKS_DIR"

#=== GNOME desktop tweaks (if applicable) =====================================#
if have gsettings; then
  echo "==> Applying GNOME preferences"
  # examples; tweak as you like
  gsettings set org.gnome.desktop.interface clock-show-seconds true || true
  gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true || true
fi

#=== Git identity & SSH keys ==================================================#
if [[ -n "$GIT_NAME" && -n "$GIT_EMAIL" ]]; then
  echo "==> Configuring git"
  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  git config --global init.defaultBranch main
  git config --global pull.rebase false
fi

if [[ ! -f "$HOME/.ssh/id_${SSH_KEY_TYPE}.pub" ]]; then
  echo "==> Generating SSH key (${SSH_KEY_TYPE})"
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  ssh-keygen -t "$SSH_KEY_TYPE" -C "${GIT_EMAIL:-bootstrap}" -f "$HOME/.ssh/id_${SSH_KEY_TYPE}" -N ""
  eval "$(ssh-agent -s)"
  ssh-add "$HOME/.ssh/id_${SSH_KEY_TYPE}"
  echo "Public key:"
  cat "$HOME/.ssh/id_${SSH_KEY_TYPE}.pub"
fi

#=== dotfiles =================================================================#
if [[ -n "$DOTFILES_REPO" && ! -d "$HOME/.dotfiles" ]]; then
  echo "==> Cloning dotfiles"
  git clone --recursive "$DOTFILES_REPO" "$HOME/.dotfiles"
  if [[ -n "$DOTFILES_BOOTSTRAP" && -x "$HOME/.dotfiles/${DOTFILES_BOOTSTRAP}" ]]; then
    echo "==> Running dotfiles bootstrap"
    (cd "$HOME/.dotfiles" && "./${DOTFILES_BOOTSTRAP}")
  fi
fi

#=== WSL-specific tweaks ======================================================#
if is_wsl; then
  echo "==> Detected WSL; applying WSL-friendly settings"
  sudo update-alternatives --set iptables /usr/sbin/iptables-legacy || true
fi

#=== postinstall.d hooks ======================================================#
if [[ -d "$POST_D" ]]; then
  echo "==> Running postinstall hooks in ${POST_D}"
  for f in "$POST_D"/*; do
    [[ -x "$f" ]] || continue
    echo "--> $f"
    "$f"
  done
fi

#=== cleanup ==================================================================#
echo "==> Final apt cleanup"
sudo apt-get autoremove -y
sudo apt-get clean

echo "==> Done! Log at: ${LOG_FILE}"
echo "You may need to log out/in (or reboot) for group/shell changes to take effect."
