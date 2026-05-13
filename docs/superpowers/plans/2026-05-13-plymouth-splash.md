# Plymouth Splash Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Plymouth boot splash screen showing a "WriterDeck" wordmark and animated dot-ring spinner, suppressing the default Raspberry Pi scrolling boot text.

**Architecture:** Two Plymouth theme files are added to `assets/plymouth/writerdeck/` in the repo. The installer copies them to `/usr/share/plymouth/themes/writerdeck/`, adds `quiet splash vt.global_cursor_default=0` to `cmdline.txt`, sets `disable_splash=1` in `config.txt` (to suppress the Pi GPU rainbow), and runs `update-initramfs -u`. The uninstaller reverses all of this.

**Tech Stack:** POSIX sh, Plymouth script module, Debian Trixie `plymouth` package, DejaVu Sans (already installed via `foot`)

---

## File Structure

**New files:**
- `assets/plymouth/writerdeck/writerdeck.plymouth` — theme descriptor
- `assets/plymouth/writerdeck/writerdeck.script` — animation: black background, "WriterDeck" wordmark, 10-dot chasing ring

**Modified files:**
- `scripts/install-trixie-lite.sh` — add `plymouth` to packages, add `configure_cmdline_splash` and `install_plymouth_splash` functions, call `install_plymouth_splash` in main flow
- `scripts/uninstall-trixie-lite.sh` — add `configure_cmdline_remove_splash` and `remove_plymouth_splash` functions, strip splash params in no-backup fallback path, call `remove_plymouth_splash` in main flow

---

## Task 1: Create feature branch

- [ ] **Step 1: Create and switch to feature branch**

```bash
git checkout -b feat/plymouth-splash
```

Expected: `Switched to a new branch 'feat/plymouth-splash'`

---

## Task 2: Create Plymouth theme files

**Files:**
- Create: `assets/plymouth/writerdeck/writerdeck.plymouth`
- Create: `assets/plymouth/writerdeck/writerdeck.script`

No automated tests — Plymouth themes can only be tested by rebooting on Pi hardware.

- [ ] **Step 1: Create the theme descriptor**

```bash
mkdir -p assets/plymouth/writerdeck
```

Create `assets/plymouth/writerdeck/writerdeck.plymouth` with this content:

```ini
[Plymouth Theme]
Name=WriterDeck
Description=WriterDeck boot splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/writerdeck
ScriptFile=/usr/share/plymouth/themes/writerdeck/writerdeck.script
```

- [ ] **Step 2: Create the animation script**

Create `assets/plymouth/writerdeck/writerdeck.script` with this content:

```
Plymouth.SetBackgroundTopColor(0, 0, 0);
Plymouth.SetBackgroundBottomColor(0, 0, 0);

screen_width = Window.GetWidth();
screen_height = Window.GetHeight();

wordmark_image = Image.Text("WriterDeck", 1, 1, 1, 1, "DejaVu Sans 48");
wordmark_sprite = Sprite(wordmark_image);
wordmark_sprite.SetX(Math.Int((screen_width - wordmark_image.GetWidth()) / 2));
wordmark_sprite.SetY(Math.Int((screen_height / 2) - wordmark_image.GetHeight() - 50));
wordmark_sprite.SetZ(1);

num_dots = 10;
ring_radius = 30;
ring_center_x = screen_width / 2;
ring_center_y = screen_height / 2 + 30;

dot_image = Image.Text("●", 1, 1, 1, 1, "DejaVu Sans 10");
dot_half_w = Math.Int(dot_image.GetWidth() / 2);
dot_half_h = Math.Int(dot_image.GetHeight() / 2);

for (i = 0; i < num_dots; i++) {
    angle = (i * 2 * Math.Pi) / num_dots - (Math.Pi / 2);
    dot_x = Math.Int(ring_center_x + Math.Cos(angle) * ring_radius) - dot_half_w;
    dot_y = Math.Int(ring_center_y + Math.Sin(angle) * ring_radius) - dot_half_h;
    dot_sprite[i] = Sprite(dot_image);
    dot_sprite[i].SetX(dot_x);
    dot_sprite[i].SetY(dot_y);
    dot_sprite[i].SetZ(1);
    dot_sprite[i].SetOpacity(0.2);
}

fun refresh() {
    now = Plymouth.GetMilliseconds();
    frame = Math.Int(now / 80) % num_dots;
    for (i = 0; i < num_dots; i++) {
        diff = (frame - i + num_dots) % num_dots;
        opacity = 0.2 + 0.8 * (1.0 - diff / num_dots);
        dot_sprite[i].SetOpacity(opacity);
    }
}

Plymouth.SetRefreshFunction(refresh);
```

**How the script works:**
- `Plymouth.SetBackgroundTopColor/BottomColor(0,0,0)` — solid black background
- `Image.Text(text, r, g, b, alpha, font)` — renders text at given colour/font; font string is Pango notation (e.g. `"DejaVu Sans 48"`)
- Wordmark is centred horizontally, positioned 50px above vertical centre
- 10 dots are arranged in a ring using `Math.Cos`/`Math.Sin`, starting at 12 o'clock (`- Math.Pi / 2`)
- `refresh()` fires every frame; `Plymouth.GetMilliseconds() / 80` gives the current "active" dot index; opacity fades from 1.0 (active) to 0.2 (trailing) around the ring

- [ ] **Step 3: Commit**

```bash
git add assets/plymouth/writerdeck/writerdeck.plymouth assets/plymouth/writerdeck/writerdeck.script
git commit -m "feat: add Plymouth WriterDeck theme files"
```

---

## Task 3: Update installer

**Files:**
- Modify: `scripts/install-trixie-lite.sh`

- [ ] **Step 1: Add `plymouth` to required packages**

Find line 585 (the `required_packages=` line) and add `plymouth` to the string:

```sh
required_packages="wordgrinder-ncurses cage foot labwc wlopm swayidle syncthing tailscale python3 plymouth"
```

- [ ] **Step 2: Add `configure_cmdline_splash` function**

Add this function immediately after the `configure_cmdline_consoleblank` function (after line 537). Follow the exact same pattern as `configure_cmdline_consoleblank`:

```sh
configure_cmdline_splash() {
  cmdline_path=$1
  current_cmdline=$(cat "$cmdline_path")
  updated_cmdline=""

  for arg in $current_cmdline; do
    case "$arg" in
      quiet|splash|vt.global_cursor_default=*) ;;
      *) updated_cmdline="${updated_cmdline}${updated_cmdline:+ }$arg" ;;
    esac
  done

  updated_cmdline="${updated_cmdline}${updated_cmdline:+ }quiet splash vt.global_cursor_default=0"

  if [ "$updated_cmdline" = "$current_cmdline" ]; then
    return 1
  fi

  rendered_cmdline=$(mktemp)
  printf '%s\n' "$updated_cmdline" > "$rendered_cmdline"
  sudo_if_needed install -m 0644 "$rendered_cmdline" "$cmdline_path"
  rm -f "$rendered_cmdline"
  return 0
}
```

The function strips any existing `quiet`, `splash`, or `vt.global_cursor_default=*` params then re-appends them — so it is idempotent if run twice.

- [ ] **Step 3: Add `install_plymouth_splash` function**

Add this function immediately after `configure_cmdline_splash`:

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

  if [ -n "$LOCAL_CONFIG_TXT" ]; then
    backup_file_if_missing "$LOCAL_CONFIG_TXT" "${LOCAL_CONFIG_TXT#/}"
    set_config_key "$LOCAL_CONFIG_TXT" "disable_splash" "1"
    log "Set disable_splash=1 in $LOCAL_CONFIG_TXT"
  fi

  if [ -n "$LOCAL_CMDLINE_TXT" ]; then
    backup_file_if_missing "$LOCAL_CMDLINE_TXT" "${LOCAL_CMDLINE_TXT#/}"
    if configure_cmdline_splash "$LOCAL_CMDLINE_TXT"; then
      log "Added quiet splash vt.global_cursor_default=0 to $LOCAL_CMDLINE_TXT"
    fi
  fi

  sudo_if_needed plymouth-set-default-theme writerdeck
  log "Building initramfs — this may take about a minute on Pi Zero 2W..."
  sudo_if_needed update-initramfs -u
  log "Plymouth splash screen configured."
}
```

Note: `backup_file_if_missing` is idempotent — if `setup_console` already backed up `cmdline.txt` or `config.txt` earlier in the same installer run, these calls are no-ops. The backup therefore reflects the pre-Plymouth state, which is what the uninstaller needs.

- [ ] **Step 4: Call `install_plymouth_splash` in the main flow**

Find the `setup_console` call in the main flow (around line 819) and add the new call immediately after it:

```sh
setup_console
install_plymouth_splash
# Ensure TARGET_USER can edit the config (settings menu writes it directly).
```

`install_plymouth_splash` must come after `install_required_packages` (Plymouth package must exist) and after `setup_console` (so the backup is created in the pre-Plymouth state).

- [ ] **Step 5: Commit**

```bash
git add scripts/install-trixie-lite.sh
git commit -m "feat: add Plymouth splash to installer"
```

---

## Task 4: Update uninstaller

**Files:**
- Modify: `scripts/uninstall-trixie-lite.sh`

- [ ] **Step 1: Add `configure_cmdline_remove_splash` function**

Add immediately after the `configure_cmdline_consoleblank` function (after line 243):

```sh
configure_cmdline_remove_splash() {
  cmdline_path=$1

  if [ ! -f "$cmdline_path" ]; then
    return 1
  fi

  current_cmdline=$(cat "$cmdline_path")
  updated_cmdline=""

  for arg in $current_cmdline; do
    case "$arg" in
      quiet|splash|vt.global_cursor_default=*) ;;
      *) updated_cmdline="${updated_cmdline}${updated_cmdline:+ }$arg" ;;
    esac
  done

  if [ "$updated_cmdline" = "$current_cmdline" ]; then
    return 1
  fi

  rendered_cmdline=$(mktemp)
  printf '%s\n' "$updated_cmdline" > "$rendered_cmdline"
  sudo_if_needed install -m 0644 "$rendered_cmdline" "$cmdline_path"
  rm -f "$rendered_cmdline"
  return 0
}
```

- [ ] **Step 2: Add `remove_plymouth_splash` function**

Add immediately after `configure_cmdline_remove_splash`:

```sh
remove_plymouth_splash() {
  PLYMOUTH_THEME_DEST="/usr/share/plymouth/themes/writerdeck"

  if [ -d "$PLYMOUTH_THEME_DEST" ]; then
    sudo_if_needed rm -rf "$PLYMOUTH_THEME_DEST"
    log "Removed Plymouth theme at $PLYMOUTH_THEME_DEST"
  fi

  if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    sudo_if_needed plymouth-set-default-theme text
    log "Reset Plymouth theme to text"
    log "Rebuilding initramfs — this may take about a minute on Pi Zero 2W..."
    sudo_if_needed update-initramfs -u
  fi
}
```

- [ ] **Step 3: Strip splash params in the no-backup fallback path**

In `restore_or_remove_console_files`, find the block that handles `CMDLINE_TXT` with no backup (around lines 278–286):

```sh
  if [ -n "$CMDLINE_TXT" ]; then
    if restore_file_from_backup "$CMDLINE_TXT" "${CMDLINE_TXT#/}"; then
      log "Restored $CMDLINE_TXT from backup"
    else
      configure_cmdline_video "$CMDLINE_TXT" "" || true
      configure_cmdline_consoleblank "$CMDLINE_TXT" "" || true
      log "Removed WriterDeck kernel cmdline overrides from $CMDLINE_TXT"
    fi
  fi
```

Replace it with:

```sh
  if [ -n "$CMDLINE_TXT" ]; then
    if restore_file_from_backup "$CMDLINE_TXT" "${CMDLINE_TXT#/}"; then
      log "Restored $CMDLINE_TXT from backup"
    else
      configure_cmdline_video "$CMDLINE_TXT" "" || true
      configure_cmdline_consoleblank "$CMDLINE_TXT" "" || true
      configure_cmdline_remove_splash "$CMDLINE_TXT" || true
      log "Removed WriterDeck kernel cmdline overrides from $CMDLINE_TXT"
    fi
  fi
```

Also find the `CONFIG_TXT` no-backup block (around lines 267–276):

```sh
  if [ -n "$CONFIG_TXT" ]; then
    if restore_file_from_backup "$CONFIG_TXT" "${CONFIG_TXT#/}"; then
      log "Restored $CONFIG_TXT from backup"
    else
      remove_config_key "$CONFIG_TXT" "display_rotate"
      remove_config_key "$CONFIG_TXT" "hdmi_group"
      remove_config_key "$CONFIG_TXT" "hdmi_mode"
      log "Removed WriterDeck display keys from $CONFIG_TXT"
    fi
  fi
```

Replace with:

```sh
  if [ -n "$CONFIG_TXT" ]; then
    if restore_file_from_backup "$CONFIG_TXT" "${CONFIG_TXT#/}"; then
      log "Restored $CONFIG_TXT from backup"
    else
      remove_config_key "$CONFIG_TXT" "display_rotate"
      remove_config_key "$CONFIG_TXT" "hdmi_group"
      remove_config_key "$CONFIG_TXT" "hdmi_mode"
      remove_config_key "$CONFIG_TXT" "disable_splash"
      log "Removed WriterDeck display keys from $CONFIG_TXT"
    fi
  fi
```

Note: When a backup exists (the normal case), `restore_file_from_backup` restores the pre-Plymouth state, so these `else` branches are only safety nets for unusual situations.

- [ ] **Step 4: Call `remove_plymouth_splash` in the main flow**

Find `restore_or_remove_console_files` in the main flow (around line 321) and add the call immediately after it:

```sh
restore_or_remove_console_files
remove_plymouth_splash
restore_or_remove_file /etc/systemd/system/getty@tty1.service.d/override.conf ...
```

- [ ] **Step 5: Commit**

```bash
git add scripts/uninstall-trixie-lite.sh
git commit -m "feat: add Plymouth cleanup to uninstaller"
```

---

## Task 5: Push branch for hardware testing

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feat/plymouth-splash
```

- [ ] **Step 2: Pull and test on Pi**

On the Pi:

```bash
git fetch && git checkout feat/plymouth-splash
sudo ./scripts/install-trixie-lite.sh
sudo reboot
```

Expected: Pi GPU rainbow is gone, Plymouth splash appears with "WriterDeck" wordmark and animated dot ring, `wd-menu` launches cleanly after boot.

> Note: `update-initramfs -u` takes ~1 minute on Pi Zero 2W — the installer logs "Building initramfs..." before this step so it doesn't look hung.

- [ ] **Step 3: Open PR once hardware confirmed**
