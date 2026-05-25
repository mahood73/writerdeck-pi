# Multi-Platform Support Design

**Date:** 2026-05-25  
**Status:** Approved

## Goal

Expand WriterDeck beyond Raspberry Pi to run on any Debian machine (any architecture). Pi remains the primary target; generic Debian (x86, ARM, or otherwise) is a supported secondary target useful for testing before buying hardware.

## Approach

Single installer with automatic platform detection. A `is_pi()` function gates Pi-specific logic. No stored variable — called inline where paths diverge.

```sh
is_pi() {
  grep -qi "raspberry pi" /proc/device-tree/model 2>/dev/null
}
```

## File Renames

| Old | New |
|-----|-----|
| `scripts/install-trixie-lite.sh` | `scripts/install.sh` |
| `scripts/uninstall-trixie-lite.sh` | `scripts/uninstall.sh` |
| `docs/setup-trixie-lite.md` | `docs/setup.md` |

All references in `README.md`, `docs/setup.md`, and tests updated to match.

## Installer Behaviour by Platform

### Shared (both platforms)

- Package install: `wordgrinder-ncurses cage foot labwc wlopm swayidle python3 plymouth plymouth-label`
- Writing folder setup
- Config at `/etc/writerdeck/config.toml`
- Foot terminal config
- Autologin on tty1 via systemd getty override
- Session scripts: `wd`, `wd-menu`, `wd-session`, `wd-labwc-session`
- Plymouth theme install, default theme set, `plymouthd.conf` (DeviceTimeout, ShowDelay), `MODULES=most` in initramfs.conf, `update-initramfs -u`
- Blank timeout written to `config.toml` (used by swayidle)

### Pi-only

- Prompt for HDMI resolution, rotation, and blank timeout
- Write resolution/rotation to `/boot/firmware/config.txt` or `/boot/cmdline.txt`
- Write `consoleblank=N` to cmdline.txt
- Set `disable_splash=1`, `framebuffer_width=1024`, `framebuffer_height=600` in config.txt
- Remove serial console from cmdline.txt
- Add `quiet splash vt.global_cursor_default=0` to cmdline.txt

### Non-Pi only

- Prompt for blank timeout only (no resolution or rotation)
- No boot config writes
- Plymouth kernel cmdline: if `/etc/default/grub` exists, add `quiet splash vt.global_cursor_default=0` to `GRUB_CMDLINE_LINUX_DEFAULT` and run `update-grub`

## Status Output

`install.sh --status` gains a detected-platform line (e.g. `[OK] platform: Raspberry Pi` or `[OK] platform: generic Debian`) so it's easy to verify detection at a glance.

## Docs and README

- `README.md` description: "Debian writing appliance, primarily targeting Raspberry Pi — also works on any Debian machine"
- Quick start updated to `sudo ./scripts/install.sh`
- `docs/setup.md` covers both platforms; Pi-specific steps clearly marked

## Out of Scope

- Non-Debian Linux support
- Resolution configuration on non-Pi (Wayland session always uses native; splash is too brief to matter)
- Automated GRUB backup/restore in the uninstaller (GRUB edits are low-risk and reversible manually)
