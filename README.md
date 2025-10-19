# Ubuntu Easy Setup

Fail-safe, **continue-on-error** bootstrap for Ubuntu. It installs base tooling, applies timezone/locale, enables unattended upgrades and UFW, optionally imports GNOME settings, configures Git/SSH, processes **APT**, **Snap**, and **Flatpak** lists, and finally runs any custom scripts in `stacks.d/`. Everything is **logged** and you get a **success/failure summary** at the end.

```
.
├── config.env
├── flatpaks.txt
├── gnome.dconf
├── installer.sh
├── offline-packages/
│   └── README.md
├── packages.txt
├── README.md
├── snaps.txt
└── stacks.d
    ├── 100-update.sh
    ├── 110-boot-repair.sh
    ├── 120-firewall-config.sh
    ├── 130-github-cli.sh
    ├── 140-v2ray.sh
    ├── 150-remove-excess-packages.sh
    ├── 160-vscode-extensions-install.sh
    ├── 170-safebox.sh
    ├── 180-move-files-to-private.sh
    ├── 190-zsh.sh
    ├── 200-docker.sh
    └── template.sh.sample
```

> **Highlights**
>
> * **Safe by design:** no `set -e`. Steps log errors and continue.
> * **Idempotent where reasonable:** skips things that already exist.
> * **Interactive or headless:** prompts by default; `-y` for fully non-interactive; `--ask-each-item` to prompt per package/app/stack script.
> * **Full logs:** `~/.bootstrap-logs/<timestamp>.log` (+ dconf backup when importing GNOME settings).
> * **Summary report:** lists all succeeded and failed steps at the end.

---

## 1) Prerequisites

* Ubuntu (desktop or server). The script warns if `ID!=ubuntu` but continues.
* A sudo-capable user. The script validates sudo once and keeps it alive.
* Internet connectivity for package repositories.

Optional, auto-handled if relevant:

* `snapd` (for `snaps.txt`)
* `flatpak` (and `gnome-software-plugin-flatpak` if on GNOME)
* `dconf-cli` (for `gnome.dconf` import)

---

## 2) Quick start

```bash
git clone <your-repo> ubuntu-bootstrap
cd ubuntu-bootstrap
chmod +x installer.sh

# Interactive (default: prompts per section)
./installer.sh

# Non-interactive (assume "yes" everywhere)
./installer.sh -y

# Prompt for each package/app and each stacks.d script
./installer.sh --ask-each-item

# Help
./installer.sh -h
```

**Where are logs?**
`~/.bootstrap-logs/<YYYY-MM-DD_HH-MM-SS>.log`

---

## 3) What the installer does (in order)

1. **Fail-safe shell & logging**
   Continues on error; logs to `~/.bootstrap-logs/...` with `tee`.

2. **Argument parsing**

   * `-y, --yes` – non-interactive mode
   * `--ask-each-item` – ask for each APT/Snap/Flatpak item and each `stacks.d` script
   * `-h, --help` – usage and exit

3. **Environment & sanity**
   Prints detected Ubuntu version/codename (warns for non-Ubuntu).
   Acquires `sudo` and keeps credentials warm.

4. **APT base**

   * `apt-get update`
   * `dist-upgrade`
   * Installs base tools:
     `build-essential curl wget git ca-certificates gnupg lsb-release apt-transport-https software-properties-common ufw unzip zip jq`

5. **Timezone & locale**

   * `timedatectl set-timezone "$TIMEZONE"`
   * Ensure & set `"$LOCALE"` (generates if missing)

6. **Unattended upgrades**
   Installs and configures `unattended-upgrades`.

7. **Firewall (UFW)**
   Allows `OpenSSH`, enables UFW.

8. **Bulk package installs (optional)**

   * **APT** from `packages.txt` (per line, `#` and blank lines ignored)
   * **Offline .deb packages** from `offline-packages/` (installs all `*.deb` with `dpkg -i`, then attempts `apt-get -f install`)
   * **Snaps** from `snaps.txt` (format: `name [flags]`, e.g., `code --classic`)
   * **Flatpaks** from `flatpaks.txt` (app IDs; adds Flathub if needed)

9. **GNOME settings (optional)**
   If `gnome.dconf` exists, prompts to backup current settings and import the file.

10. **Git & SSH (optional)**

    * Sets global identity if `GIT_NAME` and `GIT_EMAIL` are provided
    * Generates SSH key if missing (`SSH_KEY_TYPE`, default `ed25519`), adds to agent, prints public key

11. **Dotfiles (optional)**
    If `DOTFILES_REPO` is set and `~/.dotfiles` doesn’t exist, clones and optionally runs `DOTFILES_BOOTSTRAP`.

12. **WSL tweak (if applicable)**
    Switches `iptables` to legacy mode.

13. **Run custom stacks**
    Executes each file in `stacks.d/` (except `*.sample`), lexicographically (your numeric prefixes define order).
    Non-executable files are made executable automatically.

14. **APT cleanup**
    `apt autoremove` and `apt clean`.

15. **Summary**
    Counts and lists all successful and failed steps.

---

## 4) Configuration (`config.env`)

Create/edit `config.env` to override defaults.

> `config.env` is sourced near the top of the run. Missing values fall back to the script’s defaults.

---

## 5) Input files

### `packages.txt` (APT)

* One package per line
* Blank lines and `# comment` lines ignored

```text
# Core CLI
htop
tmux
ripgrep

# Dev
python3-pip
```

### `snaps.txt` (Snap)

* Format: `name [flags]`
* Example:

```text
# name [flags]
code --classic
spotify
```

### `flatpaks.txt` (Flatpak)

* App IDs; Flathub will be added if missing.

```text
org.mozilla.firefox
com.visualstudio.code
```

### `offline-packages/` (Offline .deb packages)

Put your offline `.deb` files into `offline-packages/`.

- The installer will scan the directory for `*.deb` files.
- Files are processed in lexical (sorted) order; if ordering matters, prefix with numbers like `01-`, `02-`.
- Each file is installed via `sudo dpkg -i <file>`.
- After the batch, the installer attempts to fix missing dependencies with `sudo apt-get -f install -y`.

### `gnome.dconf` (GNOME settings dump)

* Import is optional and gated by a prompt.
* Before importing, the script **backs up** current GNOME settings to `~/.bootstrap-logs/dconf-backup-<timestamp>.dconf`.
* To create a dump on a reference machine:

  ```bash
  dconf dump /org/gnome/ > gnome.dconf
  ```

---

## 6) Custom stacks (`stacks.d/`)

All executable files in `stacks.d/` (except `*.sample`) are run in **lexicographic order**:

```
stacks.d/
├── 100-update.sh
├── 110-boot-repair.sh
├── 120-firewall-config.sh
├── 130-github-cli.sh
├── 140-v2ray.sh
├── 150-remove-excess-packages.sh
├── 160-vscode-extensions-install.sh
├── 170-safebox.sh
├── 180-move-files-to-private.sh
├── 190-zsh.sh
├── 200-docker.sh
└── template.sh.sample   # ignored by runner
```

**Notes**

* Files are executed as standalone programs (`"./script"`), not sourced.
  → They do **not** inherit functions from `installer.sh`; write them as self-contained scripts.
* The installer ensures executability:

  * If a file isn’t executable, it runs `chmod +x` for you.
* Use numeric prefixes (like `100-`, `110-`) to control order.
* `template.sh.sample` is an example/placeholder; files ending with `.sample` are **skipped**.

**Creating a new stack script**

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "[my-stack] doing things..."
# your logic here; exit non-zero if you want installer to record a failure
```

---

## 7) Advanced behavior & helpers

* **Prompts even when logging**: prompts are read from `/dev/tty` so interaction still works while stdout/stderr are piped to the log. If no TTY is available and you didn’t pass `-y`, defaults are used per prompt.
* **Per-item prompting**: `--ask-each-item` asks for each APT/Snap/Flatpak entry **and** for each `stacks.d` script.
* **Sudo keep-alive**: once authenticated, the script refreshes sudo in the background (best-effort).
* **PPAs**: there’s a helper `add_ppa "ppa:owner/name"` inside the installer; use PPAs from within your **stack scripts** directly (e.g., calling `sudo add-apt-repository -y ppa:...`) since stacks run in their own shell.

---

## 8) Security considerations

* You are granting the script and everything in `stacks.d/` **sudo**. Review these files carefully.
* Network-fetched installers inside `stacks.d/` (e.g., Docker convenience scripts) should be pinned/verified.

---

## 9) Uninstall / rollback

There is no automatic rollback. However:

* GNOME settings are backed up before import (see `~/.bootstrap-logs/dconf-backup-*.dconf`).
* You can remove installed packages with `apt remove`, `snap remove`, or `flatpak uninstall` as needed.

---

## 10) License & contributions

* **License:** Add your preferred license (e.g., MIT) here.
* **Contributions:** PRs welcome. Keep stack scripts self-contained and idempotent.

---

**That’s it.** Run `./installer.sh` and follow the prompts (or `-y` to go hands-off). Your log and end-of-run summary will tell you exactly what succeeded and what (if anything) needs attention.
