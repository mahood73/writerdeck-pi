# Start the writer session only on the physical console.
if [ "${WD_NO_AUTOSESSION:-0}" != "1" ] \
  && [ -z "${SSH_TTY:-}" ] \
  && [ "$(tty)" = "/dev/tty1" ]; then
  exec /usr/local/bin/wd-session
fi
