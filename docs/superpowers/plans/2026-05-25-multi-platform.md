# Multi-Platform Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the WriterDeck installer to support any Debian machine (Pi remains primary; x86/ARM Debian is a supported secondary target).

**Architecture:** Single installer with `is_pi()` detection gates all Pi-specific logic (boot config, HDMI modes, Pi Plymouth framebuffer). Non-Pi path installs the same packages and session stack but skips boot config writes; Plymouth uses GRUB instead of cmdline.txt.

**Tech Stack:** POSIX sh, Debian packaging tools (`dpkg`, `apt-get`), `update-grub`, `update-initramfs`, Python 3 (for `wd`/`wd-menu`), pytest + sh-based unit tests.

---

### Task 1: Rename files and update all references

**Files:**
- Rename: `scripts/install-trixie-lite.sh` → `scripts/install.sh`
- Rename: `scripts/uninstall-trixie-lite.sh` → `scripts/uninstall.sh`
- Rename: `docs/setup-trixie-lite.md` → `docs/setup.md`
- Modify: `tests/test_installer_resolution.sh` (INSTALLER path)
- Modify: `tests/test_installer_status.sh` (INSTALLER path)
- Modify: `README.md` (description, commands, doc link)
- Modify: `scripts/uninstall.sh` (header comment)

- [ ] **Step 1: Rename the three files**

```bash
git -C "$(git rev-parse --show-toplevel)" mv scripts/install-trixie-lite.sh scripts/install.sh
git -C "$(git rev-parse --show-toplevel)" mv scripts/uninstall-trixie-lite.sh scripts/uninstall.sh
git -C "$(git rev-parse --show-toplevel)" mv docs/setup-trixie-lite.md docs/setup.md
```

- [ ] **Step 2: Update INSTALLER path in test_installer_resolution.sh**

In `tests/test_installer_resolution.sh` line 28, change:
```sh
INSTALLER="$(cd "$(dirname "$0")/.." && pwd)/scripts/install-trixie-lite.sh"
```
to:
```sh
INSTALLER="$(cd "$(dirname "$0")/.." && pwd)/scripts/install.sh"
```

- [ ] **Step 3: Update INSTALLER path in test_installer_status.sh**

In `tests/test_installer_status.sh` line 53, change:
```sh
INSTALLER="$(cd "$(dirname "$0")/.." && pwd)/scripts/install-trixie-lite.sh"
```
to:
```sh
INSTALLER="$(cd "$(dirname "$0")/.." && pwd)/scripts/install.sh"
```

- [ ] **Step 4: Update header comment in scripts/uninstall.sh**

Change line 3:
```sh
# WriterDeck uninstaller for Raspberry Pi Zero 2W on Debian Trixie Lite.
# Run as: ./uninstall-trixie-lite.sh  (uses sudo for privileged operations)
```
to:
```sh
# WriterDeck uninstaller for Debian (Raspberry Pi primary, any Debian machine supported).
# Run as: sudo ./scripts/uninstall.sh
```

- [ ] **Step 5: Update scripts/install.sh header comment**

Change lines 2-4:
```sh
# WriterDeck installation script for Raspberry Pi Zero 2W on Debian Trixie Lite.
# Run as: ./install-trixie-lite.sh  (uses sudo for privileged operations)
```
to:
```sh
# WriterDeck installation script for Debian (Raspberry Pi primary, any Debian machine supported).
# Run as: sudo ./scripts/install.sh
```

- [ ] **Step 6: Update README.md**

Change the first paragraph under `# WriterDeck`:
```markdown
A distraction-free writing appliance for Raspberry Pi Zero 2W running Debian 13 (Trixie) Lite.
```
to:
```markdown
A distraction-free writing appliance built on Debian. Primarily targets the Raspberry Pi Zero 2W; also works on any Debian machine (x86, ARM, or otherwise) — handy for testing before buying hardware.
```

Change the Quick start command in README.md:
```markdown
2. Run `sudo ./scripts/install-trixie-lite.sh` on the Pi.
```
to:
```markdown
2. Run `sudo ./scripts/install.sh` on the device.
```

Change the docs link:
```markdown
1. Read [docs/setup-trixie-lite.md](docs/setup-trixie-lite.md).
```
to:
```markdown
1. Read [docs/setup.md](docs/setup.md).
```

Update the installer path in the What's included table:
```markdown
| `scripts/install-trixie-lite.sh`   | Installer                                    |
| `scripts/uninstall-trixie-lite.sh` | Uninstaller                                  |
```
to:
```markdown
| `scripts/install.sh`   | Installer                                    |
| `scripts/uninstall.sh` | Uninstaller                                  |
```

- [ ] **Step 7: Run existing tests to verify nothing broke**

```bash
sh tests/test_installer_resolution.sh && sh tests/test_installer_status.sh
```
Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add scripts/install.sh scripts/uninstall.sh docs/setup.md \
        tests/test_installer_resolution.sh tests/test_installer_status.sh \
        README.md
git commit -m "refactor: rename installer/uninstaller/setup-doc, drop trixie-lite suffix"
```

---

### Task 2: Add is_pi() and check_platform(), with tests

**Files:**
- Modify: `scripts/install.sh` (add PLATFORM-FUNCTIONS sentinel block, update show_status)
- Create: `tests/test_installer_platform.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_installer_platform.sh`:

```sh
#!/bin/sh
# Shell unit tests for platform detection functions.
# Run with: sh tests/test_installer_platform.sh

set -eu

PASS=0
FAIL=0

assert_eq() {
  label=$1
  expected=$2
  actual=$3
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_returns() {
  label=$1
  expected_code=$2
  command=$3

  set +e
  eval "$command"
  actual_code=$?
  set -e

  if [ "$actual_code" -eq "$expected_code" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected return code: $expected_code"
    echo "    actual return code:   $actual_code"
    FAIL=$((FAIL + 1))
  fi
}

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

INSTALLER="$(cd "$(dirname "$0")/.." && pwd)/scripts/install.sh"
eval "$(awk '/^# STATUS-FUNCTIONS-START$/,/^# STATUS-FUNCTIONS-END$/' "$INSTALLER")"
eval "$(awk '/^# PLATFORM-FUNCTIONS-START$/,/^# PLATFORM-FUNCTIONS-END$/' "$INSTALLER")"

echo "is_pi tests:"

PLATFORM_MODEL_FILE="$WORK_DIR/model_empty"
touch "$PLATFORM_MODEL_FILE"
assert_returns "empty model file returns false" 1 "is_pi"

PLATFORM_MODEL_FILE="$WORK_DIR/model_laptop"
printf 'System76 Galago Pro\0' > "$WORK_DIR/model_laptop"
assert_returns "non-Pi model returns false" 1 "is_pi"

PLATFORM_MODEL_FILE="$WORK_DIR/model_pi"
printf 'Raspberry Pi Zero 2 W Rev 1.0\0' > "$WORK_DIR/model_pi"
assert_returns "Pi Zero 2W model returns true" 0 "is_pi"

PLATFORM_MODEL_FILE="$WORK_DIR/model_pi4"
printf 'Raspberry Pi 4 Model B Rev 1.5\0' > "$WORK_DIR/model_pi4"
assert_returns "Pi 4 model returns true" 0 "is_pi"

PLATFORM_MODEL_FILE="$WORK_DIR/model_pi_upper"
printf 'RASPBERRY PI 4 MODEL B\0' > "$WORK_DIR/model_pi_upper"
assert_returns "Pi model case-insensitive" 0 "is_pi"

PLATFORM_MODEL_FILE="$WORK_DIR/missing_model"
assert_returns "missing model file returns false" 1 "is_pi"

echo ""
echo "check_platform tests:"

PLATFORM_MODEL_FILE="$WORK_DIR/model_pi"
assert_eq "Pi shows Raspberry Pi" \
  "  [OK]   platform: Raspberry Pi" \
  "$(check_platform)"

PLATFORM_MODEL_FILE="$WORK_DIR/model_laptop"
assert_eq "non-Pi shows generic Debian" \
  "  [OK]   platform: generic Debian" \
  "$(check_platform)"

echo ""
echo "configure_grub_splash tests:"

sudo_if_needed() { :; }
log() { :; }

GRUB_CONF_FILE="$WORK_DIR/missing_grub"
assert_returns "missing grub conf is a no-op" 0 "configure_grub_splash"

GRUB_CONF_FILE="$WORK_DIR/grub_with_splash"
printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"\n' > "$GRUB_CONF_FILE"
assert_returns "grub conf with splash is idempotent" 0 "configure_grub_splash"

GRUB_CONF_FILE="$WORK_DIR/grub_no_splash"
printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"\n' > "$GRUB_CONF_FILE"
assert_returns "grub conf without splash returns 0" 0 "configure_grub_splash"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

```bash
sh tests/test_installer_platform.sh
```
Expected: FAIL — `is_pi` and related functions not found.

- [ ] **Step 3: Add PLATFORM-FUNCTIONS sentinel block to scripts/install.sh**

Insert the following block in `scripts/install.sh` after the `# STATUS-FUNCTIONS-END` line (currently around line 145):

```sh
# PLATFORM-FUNCTIONS-START
is_pi() {
  grep -qi "raspberry pi" "${PLATFORM_MODEL_FILE:-/proc/device-tree/model}" 2>/dev/null
}

check_platform() {
  if is_pi; then
    status_ok "platform: Raspberry Pi"
  else
    status_ok "platform: generic Debian"
  fi
}

configure_grub_splash() {
  _grub_conf="${GRUB_CONF_FILE:-/etc/default/grub}"
  if [ ! -f "$_grub_conf" ]; then
    log "No GRUB config found at $_grub_conf; skipping GRUB splash setup"
    return 0
  fi
  if grep -q 'splash' "$_grub_conf" 2>/dev/null; then
    log "GRUB splash params already present in $_grub_conf"
    return 0
  fi
  _tmp=$(mktemp)
  sed 's/^\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 quiet splash vt.global_cursor_default=0"/' \
    "$_grub_conf" > "$_tmp"
  sudo_if_needed install -m 0644 "$_tmp" "$_grub_conf"
  rm -f "$_tmp"
  log "Added splash params to GRUB_CMDLINE_LINUX_DEFAULT in $_grub_conf"
  sudo_if_needed update-grub
  log "Ran update-grub"
}
# PLATFORM-FUNCTIONS-END
```

- [ ] **Step 4: Add check_platform() call to show_status()**

In `scripts/install.sh`, in `show_status()`, add a `check_platform` call as the first check, before the package loop:

```sh
show_status() {
  echo ""
  echo "WriterDeck installation status:"
  _fails=0

  check_platform

  # Required packages
  _required_pkgs="wordgrinder-ncurses cage foot labwc wlopm swayidle python3 plymouth plymouth-label"
  ...
```

- [ ] **Step 5: Run test to verify it passes**

```bash
sh tests/test_installer_platform.sh
```
Expected: all tests pass.

- [ ] **Step 6: Run full test suite**

```bash
sh tests/test_installer_resolution.sh && sh tests/test_installer_status.sh && sh tests/test_installer_platform.sh
```
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add scripts/install.sh tests/test_installer_platform.sh
git commit -m "feat: add is_pi() platform detection and check_platform() status output"
```

---

### Task 3: Gate display prompts and confirmation summary for Pi-only settings

**Files:**
- Modify: `scripts/install.sh` (`prompt_console_settings`, confirmation summary block)

- [ ] **Step 1: Gate resolution and rotation prompts inside prompt_console_settings()**

`prompt_console_settings()` currently always prompts for resolution, rotation, and blank timeout. Wrap the resolution and rotation sections in `if is_pi; then`. The blank timeout section runs unconditionally.

Replace the body of `prompt_console_settings()` with:

```sh
prompt_console_settings() {
  CONFIG_TXT=""
  if [ -f /boot/firmware/config.txt ]; then
    CONFIG_TXT=/boot/firmware/config.txt
  elif [ -f /boot/config.txt ]; then
    CONFIG_TXT=/boot/config.txt
  fi

  CMDLINE_TXT=""
  if [ -f /boot/firmware/cmdline.txt ]; then
    CMDLINE_TXT=/boot/firmware/cmdline.txt
  elif [ -f /boot/cmdline.txt ]; then
    CMDLINE_TXT=/boot/cmdline.txt
  fi

  echo ""
  echo "Display settings:"
  echo "  Press Enter to keep the current setting shown in brackets."
  echo ""

  configured_blank=$(probe_configured_consoleblank "$CMDLINE_TXT")
  default_blank=${configured_blank:-$DEFAULT_CONSOLE_BLANK_SECONDS}

  if is_pi; then
    configured_res=$(probe_configured_resolution "$CMDLINE_TXT" "$CONFIG_TXT")
    detected_res=$(probe_resolution)
    DETECTED_RESOLUTION=${configured_res:-$detected_res}
    default_res=${configured_res:-${detected_res:-82}}

    configured_rotate=$(probe_configured_rotation "$CMDLINE_TXT" "$CONFIG_TXT")
    default_rotate=${configured_rotate:-0}

    resolution_prompt_label "${configured_res:-}" "${detected_res:-}"
    echo "  51 = 1024x600 (WriterDeck panel)"
    echo "  82 = 1280x720 (720p)"
    echo "  86 = 1920x1080 (1080p)"
    echo "  0  = skip (use current)"
    while :; do
      printf "Choice [%s]: " "$default_res"
      read -r res_input
      if [ -z "$res_input" ]; then
        CONSOLE_RESOLUTION="$default_res"
      else
        CONSOLE_RESOLUTION=$res_input
      fi

      if is_supported_resolution "$CONSOLE_RESOLUTION"; then
        break
      fi

      echo "Please choose one of: 0, 51, 82, or 86."
    done

    echo ""
    echo "Physical screen orientation:"
    echo "  Choose how the display is mounted right now."
    echo "  The installer will rotate the console to match."
    echo "  0 = mounted normally"
    echo "  1 = display is turned 90 degrees clockwise"
    echo "  2 = display is upside down"
    echo "  3 = display is turned 90 degrees anti-clockwise"
    while :; do
      printf "Choice [%s]: " "$default_rotate"
      read -r rot_input
      if [ -z "$rot_input" ]; then
        CONSOLE_ROTATE=$default_rotate
      else
        CONSOLE_ROTATE=$rot_input
      fi

      if is_supported_rotation "$CONSOLE_ROTATE"; then
        break
      fi

      echo "Please choose one of: 0, 1, 2, or 3."
    done
  fi

  echo ""
  echo "Console blanking timeout in seconds:"
  echo "  600 = blank after 10 minutes [recommended]"
  echo "  0   = disable blanking"
  while :; do
    printf "Choice [%s]: " "$default_blank"
    read -r blank_input
    if [ -z "$blank_input" ]; then
      CONSOLE_BLANK_SECONDS=$default_blank
    else
      CONSOLE_BLANK_SECONDS=$blank_input
    fi

    if is_non_negative_integer "$CONSOLE_BLANK_SECONDS"; then
      break
    fi

    echo "Please enter a whole number of seconds, or 0 to disable blanking."
  done
}
```

- [ ] **Step 2: Gate Pi-only lines in the confirmation summary**

Find the confirmation block (after `prompt_writing_folder` call, before `Proceed?`) — currently:

```sh
echo "Configuration:"
echo "  Resolution: $CONSOLE_RESOLUTION"
echo "  Screen orientation: $CONSOLE_ROTATE"
echo "  Screen blanking: $CONSOLE_BLANK_SECONDS seconds"
echo "  Writing folder: $WRITING_ROOT"
```

Replace with:

```sh
echo "Configuration:"
if is_pi; then
  echo "  Resolution: $CONSOLE_RESOLUTION"
  echo "  Screen orientation: $CONSOLE_ROTATE"
fi
echo "  Screen blanking: $CONSOLE_BLANK_SECONDS seconds"
echo "  Writing folder: $WRITING_ROOT"
```

- [ ] **Step 3: Run existing tests**

```bash
sh tests/test_installer_resolution.sh && sh tests/test_installer_status.sh && sh tests/test_installer_platform.sh
```
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add scripts/install.sh
git commit -m "feat: gate HDMI resolution/rotation prompts behind is_pi()"
```

---

### Task 4: Gate console setup; keep blank timeout write for all platforms

**Files:**
- Modify: `scripts/install.sh` (`setup_console`, main install flow)

- [ ] **Step 1: Remove configure_config_blank_timeout from setup_console()**

At the end of `setup_console()`, find and remove these two lines:

```sh
    configure_config_blank_timeout "$CONFIG_PATH" "$CONSOLE_BLANK_SECONDS"
    log "Set display blank_timeout to $CONSOLE_BLANK_SECONDS seconds in $CONFIG_PATH"
```

- [ ] **Step 2: Gate setup_console in main flow, add unconditional blank timeout write**

In the main install flow, find the current call:

```sh
setup_console
```

Replace with:

```sh
if is_pi; then
  setup_console
fi
configure_config_blank_timeout "$CONFIG_PATH" "$CONSOLE_BLANK_SECONDS"
log "Set display blank_timeout to $CONSOLE_BLANK_SECONDS seconds in $CONFIG_PATH"
```

- [ ] **Step 3: Run existing tests**

```bash
sh tests/test_installer_resolution.sh && sh tests/test_installer_status.sh && sh tests/test_installer_platform.sh
```
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add scripts/install.sh
git commit -m "feat: skip Pi boot config on non-Pi; always write blank_timeout to config.toml"
```

---

### Task 5: Split Plymouth for Pi vs non-Pi

**Files:**
- Modify: `scripts/install.sh` (`install_plymouth_splash`)

The Pi-specific Plymouth steps are: setting `disable_splash=1`, `framebuffer_width`, `framebuffer_height` in config.txt; removing serial console from cmdline.txt; adding `quiet splash vt.global_cursor_default=0` to cmdline.txt. The non-Pi path instead calls `configure_grub_splash()` (already added in Task 2).

- [ ] **Step 1: Restructure install_plymouth_splash()**

Replace the full body of `install_plymouth_splash()` with the version below. The shared steps (theme copy, set-default-theme, plymouthd.conf, MODULES=most, update-initramfs) are unchanged. Pi-specific config.txt/cmdline.txt writes move inside `if is_pi; then`. The `else` branch calls `configure_grub_splash`.

```sh
install_plymouth_splash() {
  PLYMOUTH_THEME_SRC="$REPO_DIR/assets/plymouth/writerdeck"
  PLYMOUTH_THEME_DEST="/usr/share/plymouth/themes/writerdeck"

  LOCAL_CONFIG_TXT=""
  if [ -f /boot/firmware/config.txt ]; then
    LOCAL_CONFIG_TXT=/boot/firmware/config.txt
  elif [ -f /boot/config.txt ]; then
    LOCAL_CONFIG_TXT=/boot/config.txt
  fi

  LOCAL_CMDLINE_TXT=""
  if [ -f /boot/firmware/cmdline.txt ]; then
    LOCAL_CMDLINE_TXT=/boot/firmware/cmdline.txt
  elif [ -f /boot/cmdline.txt ]; then
    LOCAL_CMDLINE_TXT=/boot/cmdline.txt
  fi

  sudo_if_needed install -d -m 0755 "$PLYMOUTH_THEME_DEST"
  sudo_if_needed install -m 0644 "$PLYMOUTH_THEME_SRC/writerdeck.plymouth" "$PLYMOUTH_THEME_DEST/writerdeck.plymouth"
  sudo_if_needed install -m 0644 "$PLYMOUTH_THEME_SRC/writerdeck.script" "$PLYMOUTH_THEME_DEST/writerdeck.script"
  log "Installed Plymouth theme at $PLYMOUTH_THEME_DEST"

  HOOK_SRC="$REPO_DIR/assets/initramfs-hooks/writerdeck-plymouth"
  HOOK_DEST="/etc/initramfs-tools/hooks/writerdeck-plymouth"
  if [ -f "$HOOK_SRC" ]; then
    sudo_if_needed install -m 0755 "$HOOK_SRC" "$HOOK_DEST"
    log "Installed initramfs hook at $HOOK_DEST"
  fi

  if is_pi; then
    if [ -n "$LOCAL_CONFIG_TXT" ]; then
      backup_file_if_missing "$LOCAL_CONFIG_TXT" "${LOCAL_CONFIG_TXT#/}"
      set_config_key "$LOCAL_CONFIG_TXT" "disable_splash" "1"
      log "Set disable_splash=1 in $LOCAL_CONFIG_TXT"
      set_config_key "$LOCAL_CONFIG_TXT" "framebuffer_width" "1024"
      set_config_key "$LOCAL_CONFIG_TXT" "framebuffer_height" "600"
      log "Set framebuffer_width=1024 framebuffer_height=600 in $LOCAL_CONFIG_TXT"
    fi

    if [ -n "$LOCAL_CMDLINE_TXT" ]; then
      backup_file_if_missing "$LOCAL_CMDLINE_TXT" "${LOCAL_CMDLINE_TXT#/}"
      if configure_cmdline_remove_serial_console "$LOCAL_CMDLINE_TXT"; then
        log "Removed serial console from $LOCAL_CMDLINE_TXT"
      fi
      if configure_cmdline_splash "$LOCAL_CMDLINE_TXT"; then
        log "Added quiet splash vt.global_cursor_default=0 to $LOCAL_CMDLINE_TXT"
      fi
    fi
  else
    configure_grub_splash
  fi

  sudo_if_needed /usr/sbin/plymouth-set-default-theme writerdeck
  PLYMOUTH_CONF=/etc/plymouth/plymouthd.conf
  if [ -f "$PLYMOUTH_CONF" ]; then
    if ! grep -q "^DeviceTimeout=" "$PLYMOUTH_CONF"; then
      sudo_if_needed sed -i "/^\[Daemon\]/a DeviceTimeout=2" "$PLYMOUTH_CONF"
      log "Set DeviceTimeout=2 in $PLYMOUTH_CONF"
    fi
    if ! grep -q "^ShowDelay=" "$PLYMOUTH_CONF"; then
      sudo_if_needed sed -i "/^\[Daemon\]/a ShowDelay=0" "$PLYMOUTH_CONF"
      log "Set ShowDelay=0 in $PLYMOUTH_CONF"
    fi
  fi

  INITRAMFS_CONF=/etc/initramfs-tools/initramfs.conf
  if [ -f "$INITRAMFS_CONF" ] && grep -q "^MODULES=dep" "$INITRAMFS_CONF"; then
    sudo_if_needed sed -i "s/^MODULES=dep/MODULES=most/" "$INITRAMFS_CONF"
    log "Set MODULES=most in $INITRAMFS_CONF (required for early Plymouth display)"
  fi
  log "Rebuilding initramfs to apply Plymouth theme — this takes a few minutes."
  sudo_if_needed update-initramfs -u
  log "Plymouth splash screen configured."
}
```

- [ ] **Step 2: Run all tests**

```bash
sh tests/test_installer_resolution.sh && sh tests/test_installer_status.sh && sh tests/test_installer_platform.sh
```
Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add scripts/install.sh
git commit -m "feat: split Plymouth install for Pi (cmdline.txt) vs non-Pi (GRUB)"
```

---

### Task 6: Rewrite docs/setup.md for both platforms

**Files:**
- Modify: `docs/setup.md`

- [ ] **Step 1: Rewrite docs/setup.md**

Replace the full content of `docs/setup.md` with:

```markdown
# Setup: WriterDeck on Debian

WriterDeck runs on any Debian machine. The installer detects the platform and applies hardware-specific steps automatically.

- **Raspberry Pi Zero 2W** — full path including HDMI mode, display rotation, Pi boot config, and Plymouth splash
- **Any other Debian machine** — same packages and session stack; skips boot config; Plymouth splash uses GRUB

## 1. Base install

Clone this repo on the device and run:

```bash
sudo ./scripts/install.sh
```

The installer prompts for your writing folder and screen blanking timeout. On Raspberry Pi it also prompts for console resolution and rotation. On reruns it detects existing values and preserves them where possible.

This installs:

- `wordgrinder-ncurses`
- `labwc`, `cage`, `foot`, `swayidle`, and `wlopm` for the fullscreen writing session
- WriterDeck scripts and config
- Foot terminal config at `~/.config/foot/foot.ini`
- Screen blanking via swayidle (default: 600 seconds)
- Plymouth splash screen

The installer targets `$SUDO_USER` by default and prompts for confirmation. To install for a different user, enter that username at the prompt.

**Idempotency:** safe to rerun. Existing config files (`/etc/writerdeck/config.toml`, `~/.config/foot/foot.ini`) are preserved; updated defaults are written alongside as `.dist` files for manual comparison.

### Raspberry Pi only: WordGrinder 0.9 (optional)

The installer pulls WordGrinder 0.8 from the Trixie package archive. That is sufficient for normal use. WordGrinder 0.9 exists upstream but is not packaged — only build it from source if a specific 0.9 fix is needed.

Install build dependencies:

```bash
sudo apt install git build-essential make ninja-build pkg-config python3 libncursesw5-dev zlib1g-dev
```

Clone and patch (the upstream build tries to materialise Windows/Haiku OpenGL targets, which fail on a console-only device):

```bash
mkdir -p ~/src && cd ~/src
git clone https://github.com/davidgiven/wordgrinder.git
cd wordgrinder

python3 <<'PY'
from pathlib import Path

p = Path("src/c/build.py")
s = p.read_text()
p.with_suffix(".py.bak").write_text(s)

s = s.replace(
    "    HAS_XWORDGRINDER,\n"
    "    DEFAULT_DICTIONARY_PATH,\n"
    ")\n",
    "    HAS_XWORDGRINDER,\n"
    "    DEFAULT_DICTIONARY_PATH,\n"
    "    IS_WINDOWS,\n"
    "    HAS_HAIKU,\n"
    ")\n",
)

def wrap_block(text, start, end_marker, guard):
    i = text.index(start)
    j = text.index(end_marker, i)
    block = text[i:j]
    indented = "".join("    " + line if line.strip() else line for line in block.splitlines(True))
    return text[:i] + guard + ":\n" + indented + text[j:]

s = wrap_block(s, 'make_wordgrinder(\n    "wordgrinder-wincon",', "\nif HAS_XWORDGRINDER:", "if IS_WINDOWS")
s = wrap_block(s, 'make_wordgrinder(\n    "wordgrinder-glfw-windows",', '\nmake_wordgrinder(\n    "wordgrinder-glfw-haiku",', "if IS_WINDOWS")
s = wrap_block(s, 'make_wordgrinder(\n    "wordgrinder-glfw-haiku",', "\n", "if HAS_HAIKU")

p.write_text(s)
PY
```

Build and install to `~/.local`:

```bash
BUILDTYPE=unix-ncurses-only make
PREFIX="$HOME/.local" BUILDTYPE=unix-ncurses-only make install
```

If `which wordgrinder` still points to `/usr/bin/wordgrinder`, add this to `~/.profile`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## 2. Auto-login and session launch

The installer configures:

- `/etc/systemd/system/getty@tty1.service.d/override.conf` — autologin on `tty1`
- `/etc/profile.d/wd-session.sh` — launches WriterDeck session on `tty1` only

Backups of modified system files are kept under `/etc/writerdeck/uninstall/` so the uninstaller can restore them.

Apply without rebooting:

```bash
sudo systemctl daemon-reload
sudo systemctl restart getty@tty1
```

### Session behaviour

- `tty1` boots into a full-screen Wayland terminal running `wd-session`.
- `labwc` is preferred when available because it supports display power management; `cage` remains the fallback compositor.
- `foot` launches with `--fullscreen` so the terminal fills the display rather than fitting a cell grid.
- UK keyboard layout is set via `XKB_DEFAULT_LAYOUT=gb`.
- If the Wayland session cannot start, WriterDeck falls back to raw tty.
- WordGrinder intercepts some Alt/function-key combinations. If `Alt+F2` does not switch tty while WordGrinder is open, quit to the WriterDeck menu first.
- `tty2+` is a normal login shell.

### Uninstalling

```bash
sudo ./scripts/uninstall.sh
```

This removes the tty1 autologin and session hook, restores backed-up system files, and removes WriterDeck binaries and config. Packages and writing data are left in place.

## 3. Optional firewall

The installer does not configure a firewall. To apply the repo's baseline ruleset:

```bash
sudo apt install ufw
sudo ./deploy/ufw-writerdeck.sh
```

Review the CIDR ranges in the script before enabling if your network differs.

## 4. Verification checklist

- Reboot — `tty1` opens into WordGrinder inside the fullscreen terminal session.
- Leave idle — display blanks after the configured timeout and wakes on keypress.
- Quit WordGrinder — menu appears with write, export, settings, shell, reboot, and poweroff options.
- Choose `e` — export menu appears with latest, all drafts, and pick-a-file options.
- Choose `,` — settings menu appears with screen blank timeout, keyboard layout, and startup mode options.
- Choose `s` — shell opens. Type `exit` — menu reappears.
- `wd new` — blank WordGrinder document, save dialog rooted in `~/Writing/inbox`.
- `wd new notes` — blank WordGrinder document, save dialog rooted in `~/Writing/notes`.
```

- [ ] **Step 2: Commit spec and plan alongside docs**

```bash
git add docs/setup.md docs/superpowers/specs/2026-05-25-multi-platform-design.md \
        docs/superpowers/plans/2026-05-25-multi-platform.md
git commit -m "docs: rewrite setup.md for multi-platform; add spec and plan"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| Rename install-trixie-lite.sh → install.sh | Task 1 |
| Rename uninstall-trixie-lite.sh → uninstall.sh | Task 1 |
| Rename setup-trixie-lite.md → setup.md | Task 1 |
| is_pi() via /proc/device-tree/model | Task 2 |
| --status shows detected platform | Task 2 |
| Pi path: full HDMI/rotation/blank prompts | Task 3 |
| Non-Pi path: blank timeout prompt only | Task 3 |
| Pi path: writes config.txt/cmdline.txt | Task 4 |
| Non-Pi path: skips boot config writes | Task 4 |
| Both paths: write blank_timeout to config.toml | Task 4 |
| Both paths: Plymouth theme, plymouthd.conf, update-initramfs | Task 5 |
| Pi path: config.txt framebuffer, cmdline.txt splash | Task 5 |
| Non-Pi path: GRUB cmdline splash via update-grub | Task 5 |
| README description updated | Task 1 |
| docs/setup.md covers both platforms | Task 6 |

All spec requirements covered. No TBDs. No placeholder steps.
