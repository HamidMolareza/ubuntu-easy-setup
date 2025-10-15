#!/usr/bin/env bash
###############################################################################
# Ubuntu Bootstrap Installer (fail-safe / continue-on-error)
# - Idempotent where reasonable
# - Reads optional scripts from stacks.d/ (runs only existing + executable)
# - Prompts before steps unless -y/--yes is used
# - Logs everything to ~/.bootstrap-logs/<timestamp>.log
###############################################################################

#--------------------------- fail-safe shell mode -----------------------------#
# Do NOT set -e (we want continue-on-error)
set -uo pipefail
set -E  # allow ERR trap to fire in functions

#------------------------------- logging --------------------------------------#
SCRIPT_NAME="$(basename "$0")"
LOG_DIR="${HOME}/.bootstrap-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/$(date +%F_%H-%M-%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "==> ${SCRIPT_NAME} starting at $(date)"

#=========================== argument parsing =================================#
ASSUME_YES=0
ASK_EACH_ITEM=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1; shift ;;
    --ask-each-item) ASK_EACH_ITEM=1; shift ;;
    -h|--help)
      cat <<'USAGE'
Usage: ./installer.sh [options]

Options:
  -y, --yes           Run non-interactively; assume "yes" to all prompts.
  --ask-each-item     Ask per package/app and per stacks.d script. Default: ask per section only.
  -h, --help          Show this help and exit.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 2
      ;;
  esac
done

#============================ prompting helpers ===============================#
# Read from TTY even when stdout is piped to log
read_from_tty() {
  if [[ -t 0 ]]; then
    read -r "$@"
  else
    if exec 3</dev/tty 2>/dev/null; then
      read -r -u 3 "$@"
      exec 3<&-
    else
      REPLY=""
    fi
  fi
}

# Accept n, no, o as negative (plus common yes forms)
negatives_regex='^(n|no|o)$'  # case-insensitive

confirm() {
  local prompt="${1:-Proceed?}"
  local default_yes="${2:-1}"  # 1=yes default, 0=no default
  local suffix="[Y/n]"
  [[ "$default_yes" -eq 0 ]] && suffix="[y/N]"

  if [[ "$ASSUME_YES" -eq 1 ]]; then
    echo "--> (auto) ${prompt} : yes"
    return 0
  fi

  while true; do
    printf "%s %s " "$prompt" "$suffix"
    read_from_tty
    local ans="${REPLY:-}"
    ans="${ans,,}"  # lowercase

    # empty -> default
    if [[ -z "$ans" ]]; then
      [[ "$default_yes" -eq 1 ]] && return 0 || return 1
    fi

    if [[ "$ans" =~ $negatives_regex ]]; then
      return 1
    fi

    if [[ "$ans" =~ ^(y|yes)$ ]]; then
      return 0
    fi

    echo "Please answer yes or no (y/n)."
  done
}

# attempt "Description" cmd...
# Ask, then run as a step() if confirmed.
attempt() {
  local desc="$1"; shift
  if confirm "Do you want to ${desc}?"; then
    step "$desc" "$@"
  else
    warn "User skipped: ${desc}"
  fi
}

# attempt_item respects --ask-each-item flag; otherwise runs without prompting.
attempt_item() {
  local desc="$1"; shift
  if [[ "$ASK_EACH_ITEM" -eq 1 ]]; then
    attempt "$desc" "$@"
  else
    step "$desc" "$@"
  fi
}

#----------------------------- helpers: logging -------------------------------#
declare -a __SUCCESSES=()
declare -a __FAILS=()

ok()   { echo "--> $*"; }
warn() { echo "!!  $*"; }

# step "desc" cmd args...
step() {
  local desc="$1"; shift
  ok "$desc"
  if "$@"; then
    __SUCCESSES+=("$desc")
    echo "    ✓ done"
    return 0
  else
    local rc=$?
    __FAILS+=("$desc (rc=${rc})")
    warn "$desc failed (rc=${rc}) — continuing"
    return $rc
  fi
}

# Log unexpected errors but do NOT exit
trap 'warn "Unhandled error at line ${LINENO}: ${BASH_COMMAND}"' ERR

#----------------------------- helpers: misc ----------------------------------#
have() { command -v "$1" >/dev/null 2>&1; }

ubuntu_codename() {
  . /etc/os-release 2>/dev/null || true
  echo "${UBUNTU_CODENAME:-}"
}

is_wsl() {
  grep -qi microsoft /proc/version 2>/dev/null
}

add_ppa() {
  local ppa="$1"
  if ! grep -Rq "$ppa" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    step "add PPA ${ppa}" sudo add-apt-repository -y "ppa:${ppa}"
  else
    ok "PPA ${ppa} already present, skipping"
  fi
}

require_sudo() {
  if [[ "$(id -u)" -ne 0 ]]; then
    step "initialize sudo credentials" sudo -v
    # Keep-alive sudo timestamp in background (best-effort)
    ( while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done ) 2>/dev/null &
  fi
}

#----------------------------- repo layout ------------------------------------#
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${ROOT_DIR}/config.env"
APT_LIST="${ROOT_DIR}/packages.txt"
SNAPS_LIST="${ROOT_DIR}/snaps.txt"
FLATPAKS_LIST="${ROOT_DIR}/flatpaks.txt"
TASKS_DIR="${ROOT_DIR}/stacks.d"

export DEBIAN_FRONTEND=noninteractive

#----------------------------- load config ------------------------------------#
# shellcheck source=/dev/null
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Defaults if not in config.env
TIMEZONE="${TIMEZONE:-Asia/Tehran}"
LOCALE="${LOCALE:-en_US.UTF-8}"
GIT_NAME="${GIT_NAME:-}"
GIT_EMAIL="${GIT_EMAIL:-}"
DOTFILES_REPO="${DOTFILES_REPO:-}"           # e.g. "git@github.com:user/dotfiles.git"
DOTFILES_BOOTSTRAP="${DOTFILES_BOOTSTRAP:-}" # e.g. "setup.sh"
SSH_KEY_TYPE="${SSH_KEY_TYPE:-ed25519}"

#----------------------------- sanity / sudo ----------------------------------#
if [[ ! -f /etc/os-release ]]; then
  warn "/etc/os-release not found; this script targets Ubuntu."
else
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    warn "Detected ID='${ID:-?}', this script targets Ubuntu; proceeding cautiously."
  fi
  ok "Ubuntu ${VERSION:-unknown} ($(ubuntu_codename))"
fi

require_sudo

#----------------------------- APT base ---------------------------------------#
attempt "refresh apt index" sudo apt-get update -y
attempt "upgrade packages (dist-upgrade)" sudo apt-get dist-upgrade -y

attempt "install base tooling" \
  sudo apt-get install -y build-essential curl wget git ca-certificates gnupg lsb-release apt-transport-https software-properties-common ufw unzip zip jq

#----------------------------- timezone & locale ------------------------------#
attempt "set timezone to ${TIMEZONE}" sudo timedatectl set-timezone "$TIMEZONE"

attempt "ensure locale ${LOCALE}" bash -c '
  set -euo pipefail
  if ! locale -a | grep -q "^'"${LOCALE}"'$"; then sudo locale-gen "'"${LOCALE}"'"; fi
  sudo update-locale LANG="'"${LOCALE}"'"
'

#----------------------------- unattended upgrades ----------------------------#
attempt "enable unattended-upgrades" bash -euo pipefail -c '
  sudo apt-get install -y unattended-upgrades
  sudo dpkg-reconfigure -f noninteractive unattended-upgrades
'

#----------------------------- firewall ---------------------------------------#
attempt "configure UFW (allow OpenSSH + enable)" bash -c '
  sudo ufw allow OpenSSH || true
  sudo ufw --force enable
'

#----------------------------- apt packages.txt (per item) --------------------#
if [[ -f "$APT_LIST" ]]; then
  if confirm "Process APT packages from ${APT_LIST}?"; then
    echo "==> Installing apt packages from ${APT_LIST}"
    while IFS= read -r pkg; do
      [[ -z "$pkg" || "$pkg" =~ ^\s*# ]] && continue
      attempt_item "apt install ${pkg}" sudo apt-get install -y "$pkg"
    done < <(grep -Ev '^\s*#|^\s*$' "$APT_LIST")
  else
    warn "User skipped APT packages section"
  fi
else
  warn "No ${APT_LIST} found. Skipping apt bulk install."
fi

#----------------------------- snaps.txt (per item) ---------------------------#
if have snap && [[ -f "$SNAPS_LIST" ]]; then
  if confirm "Process snaps from ${SNAPS_LIST}?"; then
    echo "==> Installing snaps from ${SNAPS_LIST}"
    while IFS= read -r line; do
      [[ -z "$line" || "$line" =~ ^\s*# ]] && continue
      name="$(awk '{print $1}' <<<"$line")"
      flags="$(awk '{$1=""; sub("^ ", ""); print}' <<<"$line")"
      if snap list | awk '{print $1}' | grep -qx "$name"; then
        ok "snap ${name} already installed, skipping"
      else
        attempt_item "snap install ${name} ${flags}" sudo snap install $name $flags
      fi
    done < "$SNAPS_LIST"
  else
    warn "User skipped snaps section"
  fi
elif [[ -f "$SNAPS_LIST" ]]; then
  warn "snapd not available; cannot process ${SNAPS_LIST}"
fi

#----------------------------- flatpaks.txt (per item) ------------------------#
if [[ -f "$FLATPAKS_LIST" ]]; then
  if confirm "Process flatpaks from ${FLATPAKS_LIST}?"; then
    if ! have flatpak; then
      attempt "install flatpak" sudo apt-get install -y flatpak
      if have gnome-shell; then
        attempt "install gnome-software-plugin-flatpak" sudo apt-get install -y gnome-software-plugin-flatpak
      fi
      attempt "add Flathub remote" flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    fi
    echo "==> Installing flatpaks"
    while IFS= read -r app; do
      [[ -z "$app" || "$app" =~ ^\s*# ]] && continue
      if flatpak list | awk '{print $1}' | grep -qx "$app"; then
        ok "flatpak ${app} already installed"
      else
        attempt_item "flatpak install ${app}" flatpak install -y flathub "$app"
      fi
    done < "$FLATPAKS_LIST"
  else
    warn "User skipped flatpaks section"
  fi
fi

#----------------------------- GNOME tweaks (best-effort) ---------------------#
if have gsettings; then
  if confirm "Apply GNOME preferences (clock seconds, tap-to-click)?"; then
    step "apply GNOME preference: show seconds on clock" gsettings set org.gnome.desktop.interface clock-show-seconds true
    step "enable touchpad tap-to-click" gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
  else
    warn "User skipped GNOME tweaks"
  fi
fi

#----------------------------- Git & SSH --------------------------------------#
if [[ -n "$GIT_NAME" && -n "$GIT_EMAIL" ]]; then
  if confirm "Configure global Git identity for ${GIT_NAME} <${GIT_EMAIL}>?"; then
    step "configure git user.name" git config --global user.name "$GIT_NAME"
    step "configure git user.email" git config --global user.email "$GIT_EMAIL"
    step "set git default branch=main" git config --global init.defaultBranch main
    step "set git pull.rebase=false" git config --global pull.rebase false
  else
    warn "User skipped Git identity configuration"
  fi
else
  warn "GIT_NAME/GIT_EMAIL not set; skipping global git identity"
fi

if [[ ! -f "$HOME/.ssh/id_${SSH_KEY_TYPE}.pub" ]]; then
  attempt "generate SSH key (${SSH_KEY_TYPE})" bash -c '
    set -euo pipefail
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keygen -t "'"$SSH_KEY_TYPE"'" -C "'"${GIT_EMAIL:-bootstrap}"'" -f "$HOME/.ssh/id_'"$SSH_KEY_TYPE"'" -N ""
    eval "$(ssh-agent -s)"
    ssh-add "$HOME/.ssh/id_'"$SSH_KEY_TYPE"'"
    echo "Public key:"
    cat "$HOME/.ssh/id_'"$SSH_KEY_TYPE"'.pub"
  '
else
  ok "SSH key id_${SSH_KEY_TYPE} already exists; skipping"
fi

#----------------------------- Dotfiles (optional) ----------------------------#
if [[ -n "$DOTFILES_REPO" && ! -d "$HOME/.dotfiles" ]]; then
  if confirm "Clone dotfiles from ${DOTFILES_REPO}?"; then
    step "clone dotfiles from ${DOTFILES_REPO}" git clone --recursive "$DOTFILES_REPO" "$HOME/.dotfiles"
    if [[ -n "$DOTFILES_BOOTSTRAP" && -x "$HOME/.dotfiles/${DOTFILES_BOOTSTRAP}" ]]; then
      attempt "run dotfiles bootstrap ${DOTFILES_BOOTSTRAP}" bash -c 'cd "$HOME/.dotfiles" && "./'"$DOTFILES_BOOTSTRAP"'"'
    elif [[ -n "$DOTFILES_BOOTSTRAP" ]]; then
      warn "Dotfiles bootstrap '$DOTFILES_BOOTSTRAP' not executable or missing; skipping"
    fi
  else
    warn "User skipped dotfiles clone"
  fi
elif [[ -n "$DOTFILES_REPO" ]]; then
  ok "Dotfiles directory already present; skipping clone"
fi

#----------------------------- WSL tweaks -------------------------------------#
if is_wsl; then
  attempt "apply WSL tweak: switch iptables to legacy" sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
fi

#----------------------------- stacks.d runner --------------------------------#
run_custom_scripts() {
  local dir="$1"
  if ! confirm "Run custom stack scripts in ${dir}?"; then
    warn "User skipped stacks.d"
    return
  fi

  echo "==> Running custom stack scripts in ${dir}"

  if [[ ! -d "$dir" ]]; then
    warn "Directory ${dir} not found. Skipping."
    return
  fi

  shopt -s nullglob
  local scripts=( "$dir"/*.sh )
  if ((${#scripts[@]} == 0)); then
    warn "No *.sh scripts found in ${dir}. Skipping."
    shopt -u nullglob
    return
  fi

  # Sorted lexicographically: numeric prefixes control order
  for f in "${scripts[@]}"; do
    if [[ -f "$f" && -x "$f" ]]; then
      if [[ "$ASK_EACH_ITEM" -eq 1 ]]; then
        attempt "run $(basename "$f")" "$f"
      else
        step "run $(basename "$f")" "$f"
      fi
    else
      warn "Skipping $(basename "$f") — file missing or not executable."
    fi
  done
  shopt -u nullglob
}
run_custom_scripts "$TASKS_DIR"

#----------------------------- cleanup ----------------------------------------#
attempt "APT autoremove" sudo apt-get autoremove -y
attempt "APT clean" sudo apt-get clean

#----------------------------- summary ----------------------------------------#
echo
echo "================ SUMMARY ================"
echo "Successful steps: ${#__SUCCESSES[@]}"
for s in "${__SUCCESSES[@]}"; do echo "  ✓ $s"; done
echo
echo "Failed steps: ${#__FAILS[@]}"
for f in "${__FAILS[@]}"; do echo "  ✗ $f"; done
echo "========================================="
echo
echo "==> Done at $(date). Log saved to: ${LOG_FILE}"
echo "Note: You may need to log out/in (or reboot) for group/shell changes to take effect."
