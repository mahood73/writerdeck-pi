# Setup: Debian 13.3 (Trixie) Lite on Pi Zero 2W

## 1. Base OS and packages

- Flash Debian 13.3 (Trixie) Lite.
- Boot and connect keyboard + HDMI display.
- Clone this repo on the device.

Run:

```bash
sudo ./scripts/install-trixie-lite.sh
```

The installer now prompts for console resolution, rotation, and blanking timeout. On reruns it prefers the current configured values it finds in `/boot/firmware/cmdline.txt` and related console config files, then falls back to live detection where possible.

On current Trixie images it applies forced HDMI mode and rotation through `/boot/firmware/cmdline.txt` with a `video=HDMI-A-1:...` kernel argument instead of relying on legacy `display_rotate`. It also configures the kernel's built-in console blanking with `consoleblank=<seconds>`; the installer default is `600` seconds (10 minutes).

This installs:

- `micro`
- `syncthing`
- `tailscale`
- `ufw`
- WriterDeck scripts/config
- Configurable text-console screen blanking (default `600` seconds)

Idempotency notes:

- Safe to rerun; existing packages/users/services are reused.
- If required packages are already installed, installer skips `apt-get update` and `apt-get install`.
- Existing `/etc/writerdeck/config.toml` is preserved.
- If repo defaults change, a new `/etc/writerdeck/config.toml.dist` is written for manual merge.
- Installer targets the invoking sudo user by default (`$SUDO_USER`) and uses that user's home for writing data.
- Override target user explicitly with `WRITERDECK_USER=<username> sudo ./scripts/install-trixie-lite.sh`.

## 2. Configure auto-login + session launch

The installer configures:

- `/etc/systemd/system/getty@tty1.service.d/override.conf` (autologin for selected install user on `tty1`)
- `/etc/profile.d/wd-session.sh` (launches WriterDeck session only on `tty1`)

Apply and reboot:

```bash
sudo systemctl daemon-reload
sudo systemctl restart getty@tty1
```

### tty1 session controls

`wd-session` now runs as a session supervisor:

- Boot/login on `tty1` opens `micro` (`wd open-latest`).
- Exiting `micro` shows a menu:
  - `w` reopen editor
  - `s` open shell
  - `r` reboot (with confirmation)
  - `p` poweroff (with confirmation)
- Exiting the shell returns to this menu.
- `tty2+` logins are normal shells and do not launch writer session.

## 3. Configure Syncthing (Phase 1)

You do not need a desktop on the Pi. Use SSH port forwarding from a machine that has a browser.

### 3.1 Verify service is running on WriterDeck

```bash
sudo systemctl status "syncthing@$(whoami).service"
```

If needed:

```bash
sudo systemctl enable --now "syncthing@$(whoami).service"
```

### 3.2 Open WriterDeck Syncthing UI through SSH tunnel

From your laptop/desktop (not on the Pi), run:

```bash
ssh -L 58384:127.0.0.1:8384 <pi-user>@<writerdeck-ip-or-hostname>
```

Then open in your local browser:

- `http://127.0.0.1:58384`

Keep this SSH session open while configuring.

If `58384` is also in use locally, choose any free local port:

```bash
ssh -L <free-local-port>:127.0.0.1:8384 <pi-user>@<writerdeck-ip-or-hostname>
```

### 3.3 Configure WriterDeck folder and remote device

On WriterDeck:

- Create folder id `writing` at `/home/<pi-user>/writing/projects`
- Set folder type: `Send Only`
- Pair with home sync node device id

In the Syncthing web UI:

- `Add Folder`
  - Folder Label: `writing`
  - Folder ID: `writing` (must match `/etc/writerdeck/config.toml`)
  - Folder Path: `/home/<pi-user>/writing/projects`
  - Folder Type: `Send Only`
- `Add Remote Device`
  - Paste home node device ID
  - Share folder `writing`

### 3.4 Configure home node and pair back

On home node:

- Folder id `writing` at target path
- Set folder type: `Receive Only`
- Enable staggered file versioning (30-day retention)

If the home node is remote/headless, tunnel similarly (different local port):

```bash
ssh -L 18384:127.0.0.1:8384 <home-user>@<home-node>
```

Open:

- `http://127.0.0.1:18384`

Then:

- Add/accept WriterDeck as a remote device.
- Add folder:
  - Folder ID: `writing`
  - Folder Path: your storage path (for Docker template, `/data/writing`)
  - Folder Type: `Receive Only` (Phase 1)
  - File Versioning: `Staggered`, 30-day retention

After both sides are connected, run on WriterDeck:

```bash
wd sync status
wd sync now
```

## 4. Configure Tailscale

On deck and home node:

```bash
sudo tailscale up
```

Use tailnet addresses for off-LAN connectivity.

## 5. Optional firewall baseline

```bash
sudo ./deploy/ufw-writerdeck.sh
```

Adjust LAN CIDRs before enabling if your network differs.

## 6. Verification checklist

- Reboot device; `tty1` opens into `micro` via `wd open-latest`.
- Leave the device idle on `tty1`; the display blanks after the configured timeout and wakes on keypress.
- Quit `micro`; menu appears with `w/s/r/p` options.
- Choose `s`; shell opens. Type `exit`; menu appears again.
- `wd new notes first` creates `projects/notes/<timestamp>_first.md`.
- `systemctl status syncthing@$(whoami).service` is `active (running)`.
- `wd sync status` returns folder status.
- `wd sync now` completes without timeout.
