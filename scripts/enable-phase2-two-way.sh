#!/bin/sh
set -eu

CONFIG_PATH=${1:-/etc/writerdeck/config.toml}

if [ ! -f "$CONFIG_PATH" ]; then
  echo "error: config not found: $CONFIG_PATH" >&2
  exit 1
fi

tmp=$(mktemp)
sed 's/^mode = "single_writer"$/mode = "two_way"/' "$CONFIG_PATH" > "$tmp"
install -m 0644 "$tmp" "$CONFIG_PATH"
rm -f "$tmp"

echo "Updated sync.mode to two_way in $CONFIG_PATH"
echo "Also update Syncthing folder type to Send & Receive on WriterDeck and home node."
