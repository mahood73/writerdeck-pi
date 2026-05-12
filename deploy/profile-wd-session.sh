# Start the writer session only on the physical console.
if [ "${WD_NO_AUTOSESSION:-0}" != "1" ] \
  && [ -z "${SSH_TTY:-}" ] \
  && [ "$(tty)" = "/dev/tty1" ]; then
  if [ "${WD_IN_TERMINAL:-0}" != "1" ] \
    && command -v foot >/dev/null 2>&1; then
    printf '\n\n\nWriterDeck starting up...\n'
    if command -v labwc >/dev/null 2>&1; then
      WD_IN_TERMINAL=1 XKB_DEFAULT_LAYOUT=${WD_XKB_LAYOUT:-gb} \
        labwc -s /usr/local/bin/wd-labwc-session && exit 0
      echo "warning: labwc session failed; trying cage."
    fi
    if command -v cage >/dev/null 2>&1; then
      WD_IN_TERMINAL=1 XKB_DEFAULT_LAYOUT=${WD_XKB_LAYOUT:-gb} \
        cage -- foot --fullscreen /usr/local/bin/wd-session && exit 0
    fi
    echo "warning: Wayland session failed; falling back to tty."
  fi

  WD_IN_TERMINAL=1 exec /usr/local/bin/wd-session
fi
