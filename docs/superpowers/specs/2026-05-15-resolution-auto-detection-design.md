# Resolution Auto-Detection — Design Spec

**Issue:** #14
**Date:** 2026-05-15

## Problem

The installer's resolution prompt always shows a generic "current: 82" label regardless of whether that value was auto-detected from the display, read from an existing boot config, or just a hardcoded fallback. Users have no signal about where the default came from.

## Goal

Make the resolution prompt header clearly communicate the source of the default value. Auto-apply nothing — the user can always override — but make it obvious when the installer has successfully detected the display.

## Scope

Single change inside `prompt_console_settings` in `scripts/install-trixie-lite.sh`. No new functions, no changes to detection logic, no changes to downstream config-writing code.

## Design

Replace the static header line:

```sh
echo "HDMI resolution (current: ${default_res:-unknown}):"
```

With a three-way branch on the source of the default:

```sh
if [ -n "$configured_res" ]; then
  echo "HDMI resolution (configured: mode $configured_res):"
elif [ -n "$detected_res" ]; then
  res_label=$(hdmi_mode_to_resolution "$detected_res")
  echo "HDMI resolution (detected from display: ${res_label}, mode ${detected_res}):"
else
  echo "HDMI resolution (no display detected; suggested: mode 82):"
fi
```

Priority (unchanged from current logic):
1. `configured_res` — value already in `/boot/firmware/config.txt` or `cmdline.txt`
2. `detected_res` — value from `probe_drm_resolution` → `probe_framebuffer_resolution` → `tvservice`
3. Fallback `82` (1280x720)

The `default_res` variable and `Choice [N]:` prompt are unchanged. Enter still accepts the default; typing a value overrides it. Validation loop is unchanged.

## Example Output

**Display connected, resolution detected:**
```
HDMI resolution (detected from display: 1920x1080, mode 86):
  51 = 1024x600 (WriterDeck panel)
  82 = 1280x720 (720p)
  86 = 1920x1080 (1080p)
  0  = skip (use current)
Choice [86]:
```

**Headless / no EDID:**
```
HDMI resolution (no display detected; suggested: mode 82):
  51 = 1024x600 (WriterDeck panel)
  82 = 1280x720 (720p)
  86 = 1920x1080 (1080p)
  0  = skip (use current)
Choice [82]:
```

**Re-running installer with existing config:**
```
HDMI resolution (configured: mode 86):
  ...
Choice [86]:
```

## Testing

- Pi with HDMI display connected → "detected from display" label with correct resolution
- Pi headless (no display) → "no display detected; suggested: mode 82"
- Re-run installer on Pi that already has `hdmi_mode` set in config → "configured: mode X"
