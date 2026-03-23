#!/bin/sh
#
# WriterDeck installation script for Raspberry Pi Zero 2W on Debian Trixie Lite.
# Run with: sudo ./install-trixie-lite.sh
#
# Environment variables (optional):
#   WRITERDECK_USER       - Target user (defaults to $SUDO_USER)
#   WD_CONSOLE_FONTSIZE   - Console font: ter-v32n (large), VGA8x16, etc.
#   WD_CONSOLE_RESOLUTION - HDMI mode: 82 (720p), 86 (1080p), 0 (skip)
#   WD_CONSOLE_ROTATE     - Screen rotation: 0=normal, 1=90°, 2=180°, 3=270° cw
#

set -eu

# -----------------------------------------------------------------------------
# Root check - must run as root (via sudo)
# -----------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo "error: run as root (sudo)" >&2
  exit 1
fi

# Resolve repo root directory (script is in scripts/ subdirectory)
REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIG_PATH=/etc/writerdeck/config.toml
DEFAULT_CONFIG_PATH="$REPO_DIR/config/config.toml"

# Determine target user - prefer explicit WRITERDECK_USER, fall back to SUDO_USER
TARGET_USER=${WRITERDECK_USER:-${SUDO_USER:-}}

# Validate target user
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
  echo "error: cannot determine target user. Re-run with sudo, or set WRITERDECK_USER=<username>" >&2
  exit 1
fi

if ! id -u "$TARGET_USER" >/dev/null 2>&1; then
  echo "error: target user does not exist: $TARGET_USER" >&2
  exit 1
fi

# Resolve target user's home directory and primary group
TARGET_GROUP=$(id -gn "$TARGET_USER")
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
  echo "error: could not resolve home directory for user: $TARGET_USER" >&2
  exit 1
fi

# Logging helper
log() {
  printf '%s\n' "$*"
}

# -----------------------------------------------------------------------------
# Package installation - ensure required tools are present
# -----------------------------------------------------------------------------
install_required_packages() {
  # Core dependencies for WriterDeck operation
  required_packages="micro syncthing tailscale ufw python3"
  missing_packages=""

  for pkg in $required_packages; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q '^install ok installed$'; then
      missing_packages="$missing_packages $pkg"
    fi
  done

  missing_packages=$(printf '%s' "$missing_packages" | xargs)

  if [ -z "$missing_packages" ]; then
    log "All required packages already installed; skipping apt update/install."
    return
  fi

  log "Installing missing packages: $missing_packages"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $missing_packages
}

# -----------------------------------------------------------------------------
# Config file management - create/manage /etc/writerdeck/config.toml
# -----------------------------------------------------------------------------
render_default_config() {
  destination=$1
  # Replace placeholder path "/home/writer/..." with actual target home directory
  sed "s|^root = \"/home/writer/writing/projects\"$|root = \"$TARGET_HOME/writing/projects\"|" \
    "$DEFAULT_CONFIG_PATH" > "$destination"
}

install_config() {
  rendered_default=$(mktemp)
  render_default_config "$rendered_default"

  # Case 1: No existing config - install default
  if [ ! -f "$CONFIG_PATH" ]; then
    install -m 0644 "$rendered_default" "$CONFIG_PATH"
    rm -f "$rendered_default"
    log "Installed default config at $CONFIG_PATH"
    return
  fi

  # Case 2: Config is the old default (/home/writer/...) - migrate to target user
  if cmp -s "$DEFAULT_CONFIG_PATH" "$CONFIG_PATH"; then
    install -m 0644 "$CONFIG_PATH" "${CONFIG_PATH}.bak"
    install -m 0644 "$rendered_default" "$CONFIG_PATH"
    rm -f "$rendered_default"
    log "Migrated default config path for user $TARGET_USER"
    log "Backup written to: ${CONFIG_PATH}.bak"
    return
  fi

  # Case 3: Config already matches rendered default - nothing to do
  if cmp -s "$rendered_default" "$CONFIG_PATH" || cmp -s "$DEFAULT_CONFIG_PATH" "$CONFIG_PATH"; then
    rm -f "$rendered_default"
    log "Config already matches defaults: $CONFIG_PATH"
    return
  fi

  # Case 4: User has custom config - preserve it, install defaults alongside
  install -m 0644 "$rendered_default" "${CONFIG_PATH}.dist"
  rm -f "$rendered_default"
  log "Kept existing config: $CONFIG_PATH"
  log "Wrote updated defaults to: ${CONFIG_PATH}.dist"
}

# -----------------------------------------------------------------------------
# Console/display configuration - font size, resolution, rotation
# -----------------------------------------------------------------------------
setup_console() {
  # Default values - large font for 7" screens, 720p resolution, no rotation
  WD_CONSOLE_FONTSIZE=${WD_CONSOLE_FONTSIZE:-ter-v32n}
  WD_CONSOLE_RESOLUTION=${WD_CONSOLE_RESOLUTION:-82}
  WD_CONSOLE_ROTATE=${WD_CONSOLE_ROTATE:-0}

  log "Configuring console: font=$WD_CONSOLE_FONTSIZE, resolution=$WD_CONSOLE_RESOLUTION, rotation=$WD_CONSOLE_ROTATE"

  # Update console-setup for terminal font (applies to all virtual terminals)
  if [ -f /etc/default/console-setup ]; then
    sed -i "^FONTFACE=.*$|FONTFACE=Terminus" /etc/default/console-setup
    sed -i "^FONTSIZE=.*$|FONTSIZE=$WD_CONSOLE_FONTSIZE" /etc/default/console-setup
    update-alternatives --set console-font /usr/share/consolefonts/"$WD_CONSOLE_FONTSIZE" 2>/dev/null || true
    setupcon 2>/dev/null || true
    log "Console font set to $WD_CONSOLE_FONTSIZE"
  fi

  # Update bootloader config for HDMI resolution and display rotation
  # Note: display_rotate applies to the physical display, not just console
  if [ -f /boot/firmware/config.txt ] || [ -f /boot/config.txt ]; then
    CONFIG_TXT=${CONFIG_TXT:-/boot/firmware/config.txt}
    
    # Set HDMI mode for framebuffer resolution (only if non-zero)
    if [ "$WD_CONSOLE_RESOLUTION" != "0" ]; then
      if ! grep -q "^hdmi_group=2" "$CONFIG_TXT" 2>/dev/null; then
        echo "hdmi_group=2" >> "$CONFIG_TXT"
      fi
      if ! grep -q "^hdmi_mode=$WD_CONSOLE_RESOLUTION" "$CONFIG_TXT" 2>/dev/null; then
        echo "hdmi_mode=$WD_CONSOLE_RESOLUTION" >> "$CONFIG_TXT"
      fi
    fi

    # Set display rotation (0=normal, 1=90° clockwise, 2=180°, 3=270° clockwise)
    if [ "$WD_CONSOLE_ROTATE" != "0" ]; then
      if ! grep -q "^display_rotate=$WD_CONSOLE_ROTATE" "$CONFIG_TXT" 2>/dev/null; then
        echo "display_rotate=$WD_CONSOLE_ROTATE" >> "$CONFIG_TXT"
      fi
      log "Screen rotated by ${WD_CONSOLE_ROTATE}° (0=normal, 1=90° clockwise, 2=180°, 3=270° clockwise)"
    fi
    log "Display config updated in $CONFIG_TXT"
  fi
}

# =============================================================================
# Main execution
# =============================================================================

# Install required packages
install_required_packages

# Create writing directory structure and set ownership
install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$TARGET_HOME/writing/projects/inbox"
chown -R "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/writing"

# Install configuration file
install -d -m 0755 /etc/writerdeck
install_config

# Configure console display (font, resolution, rotation)
setup_console

# Install CLI tools
install -d -m 0755 /usr/local/bin
install -m 0755 "$REPO_DIR/bin/wd" /usr/local/bin/wd
install -m 0755 "$REPO_DIR/bin/wd-session" /usr/local/bin/wd-session

# Configure tty1 autologin for physical console session
install -d -m 0755 /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $TARGET_USER --noclear %I \$TERM
Type=idle
EOF

# Install profile script for session handling
install -m 0644 "$REPO_DIR/deploy/profile-wd-session.sh" /etc/profile.d/wd-session.sh

# Enable required services
systemctl daemon-reload
systemctl enable getty@tty1.service
if [ -f /lib/systemd/system/syncthing@.service ] || [ -f /usr/lib/systemd/system/syncthing@.service ]; then
  systemctl enable --now "syncthing@${TARGET_USER}.service"
else
  log "warning: syncthing@.service not found; skip enable/start"
fi

# Print completion message with next steps
echo "WriterDeck base installation complete."
echo ""
echo "Console display options (set before running, or edit later):"
echo "  WD_CONSOLE_FONTSIZE   - Font: ter-v32n (large), ter-v16n (small), VGA8x16 (default)"
echo "  WD_CONSOLE_RESOLUTION - HDMI mode: 82=1280x720, 86=1920x1080, 0=skip"
echo "  WD_CONSOLE_ROTATE     - 0=normal, 1=90° clockwise, 2=180°, 3=270° clockwise"
echo ""
echo "Next:"
echo "1) Configure tailscale: tailscale up"
echo "2) Configure syncthing folder id and devices (headless: ssh -L 58384:127.0.0.1:8384 ${TARGET_USER}@<deck>)"
echo "3) Adjust /etc/writerdeck/config.toml if needed"
echo "4) Reboot for display/console changes to take effect"