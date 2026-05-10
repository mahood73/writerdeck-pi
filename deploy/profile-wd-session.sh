# Start the writer session only on the physical console.
if [ "${WD_NO_AUTOSESSION:-0}" != "1" ] \
  && [ -z "${SSH_TTY:-}" ] \
  && [ "$(tty)" = "/dev/tty1" ]; then
  if [ "${WD_IN_TERMINAL:-0}" != "1" ] \
    && command -v cage >/dev/null 2>&1 \
    && command -v foot >/dev/null 2>&1; then
    echo "WriterDeck starting up..."
    WD_IN_TERMINAL=1 XKB_DEFAULT_LAYOUT=${WD_XKB_LAYOUT:-gb} \
      cage -- foot --fullscreen /usr/local/bin/wd-session && exit 0

    echo "warning: cage/foot session failed; falling back to tty."
  fi

  WD_IN_TERMINAL=1 exec /usr/local/bin/wd-session
fi
