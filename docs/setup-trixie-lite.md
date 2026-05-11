# Setup: Debian 13 (Trixie) Lite on Pi Zero 2W

## 1. Base install

Flash Debian 13 (Trixie) Lite, boot with keyboard and HDMI attached, then clone this repo on the device and run:

```bash
sudo ./scripts/install-trixie-lite.sh
```

The installer prompts for console resolution, rotation, and screen blanking timeout. On reruns it detects existing values and preserves them where possible.

This installs:

- `wordgrinder-ncurses`
- `cage` + `foot` (Wayland terminal compositor)
- `syncthing`
- `tailscale`
- WriterDeck scripts and config
- Foot terminal config at `~/.config/foot/foot.ini`
- Screen blanking via kernel `consoleblank` (default: 600 seconds)

The installer targets `$SUDO_USER` by default. To install for a different user:

```bash
WRITERDECK_USER=<username> sudo ./scripts/install-trixie-lite.sh
```

**Idempotency:** safe to rerun. Existing config files (`/etc/writerdeck/config.toml`, `~/.config/foot/foot.ini`) are preserved; updated defaults are written alongside as `.dist` files for manual comparison.

### WordGrinder 0.9 (optional)

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

- `tty1` boots into a full-screen `cage` + `foot` Wayland terminal running `wd-session`.
- `foot` launches with `--fullscreen` so the terminal fills the display rather than fitting a cell grid.
- UK keyboard layout is set via `XKB_DEFAULT_LAYOUT=gb`.
- If `cage` or `foot` is unavailable, the session falls back to raw tty.
- WordGrinder intercepts some Alt/function-key combinations. If `Alt+F2` does not switch tty while WordGrinder is open, quit to the WriterDeck menu first.
- `tty2+` is a normal login shell.

### Uninstalling

```bash
sudo ./scripts/uninstall-trixie-lite.sh
```

This removes the tty1 autologin and session hook, restores backed-up system files, stops and disables `syncthing@<user>.service`, and removes WriterDeck binaries and config. Packages and writing data are left in place.

## 3. Configure Syncthing (Phase 1)

No desktop is needed on the Pi. Access Syncthing via SSH port forwarding.

### 3.1 Verify Syncthing is running

```bash
sudo systemctl status "syncthing@$(whoami).service"
```

If not running:

```bash
sudo systemctl enable --now "syncthing@$(whoami).service"
```

### 3.2 Open the Syncthing UI via SSH tunnel

From your laptop or desktop (not on the Pi):

```bash
ssh -L 58384:127.0.0.1:8384 <pi-user>@<writerdeck-ip>
```

Then open `http://127.0.0.1:58384` in a browser. Keep the SSH session open while configuring.

### 3.3 Configure the WriterDeck folder

In the Syncthing UI on the Pi:

- **Add Folder**
  - Folder Label: `writing`
  - Folder ID: `writing` (must match `sync.folder_id` in `/etc/writerdeck/config.toml`)
  - Folder Path: `/home/<pi-user>/Writing`
  - Folder Type: `Send Only`
- **Add Remote Device** — paste your home node device ID and share the `writing` folder.

### 3.4 Configure the home node

Tunnel to the home node if needed:

```bash
ssh -L 18384:127.0.0.1:8384 <home-user>@<home-node>
```

In the Syncthing UI on the home node:

- Accept the WriterDeck as a remote device.
- **Add Folder**
  - Folder ID: `writing`
  - Folder Path: your storage path (e.g. `/data/writing` for the Docker template)
  - Folder Type: `Receive Only`
  - File Versioning: Staggered, 30-day retention

Once both sides are connected:

```bash
wd sync status
wd sync now
```

## 4. Configure Tailscale

On both the Pi and home node:

```bash
sudo tailscale up
```

Use tailnet addresses for connectivity when away from the home LAN.

## 5. Optional firewall

The installer does not configure a firewall. To apply the repo's baseline ruleset:

```bash
sudo apt install ufw
sudo ./deploy/ufw-writerdeck.sh
```

Review the CIDR ranges in the script before enabling if your network differs.

## 6. Verification checklist

- Reboot — `tty1` opens into WordGrinder inside `cage` + `foot`.
- Leave idle — display blanks after the configured timeout and wakes on keypress.
- Quit WordGrinder — menu appears with `w/s/r/p` options.
- Choose `s` — shell opens. Type `exit` — menu reappears.
- `wd new` — blank WordGrinder document, save dialog rooted in `~/Writing/inbox`.
- `wd new notes` — blank WordGrinder document, save dialog rooted in `~/Writing/notes`.
- `systemctl status syncthing@$(whoami).service` — `active (running)`.
- `wd sync status` — returns folder status without error.
- `wd sync now` — completes without timeout.
