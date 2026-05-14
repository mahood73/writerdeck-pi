# Plymouth Splash Screen Design

## Goal

Replace the default Raspberry Pi scrolling boot text with a clean, appliance-like splash screen: a "WriterDeck" wordmark with an animated dot-ring spinner, displayed from early boot until `wd-menu` takes over the TTY.

## Approach

Custom Plymouth `script` theme — code-generated visuals, no image assets. Plymouth is the standard Linux boot splash daemon, integrated with systemd and the kernel framebuffer. It handles the clean handoff to the TTY when the system is ready.

## Theme

**Background:** Solid black.

**Wordmark:** "WriterDeck" in DejaVu Sans ~48pt, white, horizontally and vertically centred (slightly above centre to leave room for the spinner). DejaVu Sans is already installed as a dependency of `foot`.

**Spinner:** A ring of 10 dots arranged in a circle via `Math.Sin()` / `Math.Cos()`, each dot a small filled circle sprite. Dots cycle brightness in a chasing sequence driven by an internal tick accumulator (`dots.tick`, incremented each refresh call), producing a smooth rotating animation. `Plymouth.GetMilliseconds()` is not used — it returns NaN in the initramfs context, silently breaking all opacity comparisons. No image files — pure Plymouth script.

## Files

Two files added to the repo:

```
assets/plymouth/writerdeck/
  writerdeck.plymouth   # theme descriptor
  writerdeck.script     # animation script
```

Installed to `/usr/share/plymouth/themes/writerdeck/` by the installer.

## Installer Changes (`install-trixie-lite.sh`)

Four additions, following existing patterns:

1. **Package:** Add `plymouth` to `required_packages`. DejaVu Sans is already present via `foot`.

2. **`install_plymouth_theme` function:** Copies `assets/plymouth/writerdeck/` to `/usr/share/plymouth/themes/writerdeck/`, runs `plymouth-set-default-theme writerdeck`, then `update-initramfs -u`. Logs a message before `update-initramfs` warning that this step takes ~1 minute on the Pi Zero 2W.

3. **`configure_cmdline_splash` function:** Adds `quiet splash vt.global_cursor_default=0` to `cmdline.txt`, following the same pattern as `configure_cmdline_video` and `configure_cmdline_consoleblank`. `quiet` suppresses kernel messages, `splash` activates Plymouth early, `vt.global_cursor_default=0` hides the blinking cursor.

4. **`disable_splash=1` in `/boot/firmware/config.txt`:** Suppresses the Pi GPU rainbow splash that appears before the kernel boots. Backed up to the uninstall state directory before modification.

## Uninstaller Changes (`uninstall-trixie-lite.sh`)

Mirrors the install:

- Removes `/usr/share/plymouth/themes/writerdeck/`
- Resets Plymouth default theme to `text` via `plymouth-set-default-theme text`
- Removes `quiet splash vt.global_cursor_default=0` from `cmdline.txt`
- Restores `/boot/firmware/config.txt` from backup (removing `disable_splash=1`)
- Runs `update-initramfs -u`

## Testing

Manual only — no unit tests applicable. Test procedure:

1. Run installer on Pi
2. Reboot
3. Verify: Pi GPU rainbow is suppressed, Plymouth splash appears with wordmark and spinning dot ring, `wd-menu` launches cleanly after boot

## Out of Scope

- Shutdown splash
- Custom typeface / PNG wordmark (can be added later by replacing text rendering with a sprite)
- Per-service progress tracking
