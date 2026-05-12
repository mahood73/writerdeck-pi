#!/bin/sh
# Launched by labwc -s as the Wayland session startup script.
# Starts swayidle for screen blanking (if configured), then runs the
# WriterDeck terminal session. Exits labwc when the session ends.

_blank=$(python3 -c "
import tomllib
try:
    c = tomllib.load(open('/etc/writerdeck/config.toml', 'rb'))
    print(int(c.get('display', {}).get('blank_timeout', 600)))
except Exception:
    print(600)
" 2>/dev/null)

if [ "${_blank:-0}" -gt 0 ]; then
    swayidle -w \
        timeout "$_blank" "WAYLAND_DISPLAY=$WAYLAND_DISPLAY wlopm --off \\*" \
        resume "WAYLAND_DISPLAY=$WAYLAND_DISPLAY wlopm --on \\*" &
fi

foot --fullscreen /usr/local/bin/wd-session
labwc --exit
