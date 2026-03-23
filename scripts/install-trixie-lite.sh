#!/bin/sh
#
# WriterDeck installation script for Raspberry Pi Zero 2W on Debian Trixie Lite.
# Run as: ./install-trixie-lite.sh  (uses sudo for privileged operations)
#

set -eu

# -----------------------------------------------------------------------------
# Initial setup - determine if we need sudo
# -----------------------------------------------------------------------------
INITIAL_USER=$(whoami)
NEEDS_SUDO=false

# Check if we have sudo access
if [ "$(id -u)" -ne 0 ]; then
  if sudo -n true 2>/dev/null; then
    # Already have sudo access
    SUDO_CMD="sudo"
  else
    NEEDS_SUDO=true
  fi
else
  SUDO_CMD=""
fi

# Resolve repo root directory (script is in scripts/ subdirectory)
REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIG_PATH=/etc/writerdeck/config.toml
DEFAULT_CONFIG_PATH="$REPO_DIR/config/config.toml"

# Logging helper - prefix with sudo if needed
log() {
  printf '%s\n' "$*"
}

# Wrapper for privileged commands
sudo_if_needed() {
  if [ -n "$SUDO_CMD" ]; then
    $SUDO_CMD "$@"
  else
    "$@"
  fi
}

# -----------------------------------------------------------------------------
# Interactive prompts - get user preferences
# -----------------------------------------------------------------------------

# Map common resolutions to hdmi_mode values
get_hdmi_mode() {
  case "$1" in
    640x480)    echo "1" ;;
    800x600)    echo "9" ;;
    1024x768)   echo "16" ;;
    1280x720)    echo "82" ;;
    1280x1024)   echo "35" ;;
    1920x1080)  echo "86" ;;
    *)          echo "" ;;
  esac
}

# Probe current connected HDMI resolution
probe_resolution() {
  for conn in /sys/class/drm/card*-HDMI-1/status; do
    if [ -f "$conn" ] && grep -q "connected" "$conn" 2>/dev/null; then
      for mode_file in /sys/class/drm/card*/HDMI-1/mode; do
        if [ -f "$mode_file" ]; then
          mode=$(cat "$mode_file" 2>/dev/null)
          if [ -n "$mode" ]; then
            width=$(echo "$mode" | cut -dx -f1)
            height=$(echo "$mode" | cut -dx -f2)
            hdmi_mode=$(get_hdmi_mode "${width}x${height}")
            if [ -n "$hdmi_mode" ]; then
              echo "$hdmi_mode"
              return
            fi
          fi
        fi
      done
    fi
  done
  
  if command -v tvservice >/dev/null 2>&1; then
    preferred=$(tvservice -p 2>/dev/null | grep -oE '[0-9]+x[0-9]+' | head -1)
    if [ -n "$preferred" ]; then
      hdmi_mode=$(get_hdmi_mode "$preferred")
      if [ -n "$hdmi_mode" ]; then
        echo "$hdmi_mode"
        return
      fi
    fi
  fi
  echo ""
}

show_header() {
  echo ""
  echo "========================================"
  echo "  WriterDeck Setup"
  echo "========================================"
}

prompt_target_user() {
  # Default to the user running the script (not root)
  if [ "$INITIAL_USER" = "root" ] && [ -n "${SUDO_USER:-}" ]; then
    DEFAULT_USER=$SUDO_USER
  elif [ "$INITIAL_USER" != "root" ]; then
    DEFAULT_USER=$INITIAL_USER
  else
    DEFAULT_USER=""
  fi
  
  if [ -n "$DEFAULT_USER" ] && [ "$DEFAULT_USER" != "root" ]; then
    printf "Target user [%s]: " "$DEFAULT_USER"
  else
    printf "Target user: "
  fi
  
  read -r user_input
  if [ -z "$user_input" ]; then
    if [ -z "$DEFAULT_USER" ]; then
      echo "error: please specify a target user" >&2
      exit 1
    fi
    TARGET_USER=$DEFAULT_USER
  else
    TARGET_USER=$user_input
  fi
  
  if ! id -u "$TARGET_USER" >/dev/null 2>&1; then
    echo "error: user does not exist: $TARGET_USER" >&2
    exit 1
  fi
}

prompt_console_settings() {
  echo ""
  echo "Console display settings:"
  echo "  Press Enter to accept the default [recommended]."
  echo ""
  
  detected=$(probe_resolution)
  default_res=${detected:-82}
  
  printf "Console font size (ter-v32n, ter-v24n, VGA8x16) [ter-v32n]: "
  read -r font_input
  if [ -z "$font_input" ]; then
    CONSOLE_FONTSIZE="ter-v32n"
  else
    CONSOLE_FONTSIZE=$font_input
  fi
  
  echo ""
  echo "HDMI resolution (current: ${default_res:-unknown}):"
  echo "  82 = 1280x720 (720p)"
  echo "  86 = 1920x1080 (1080p)"
  echo "  0  = skip (use current)"
  printf "Choice [%s]: " "$default_res"
  read -r res_input
  if [ -z "$res_input" ]; then
    CONSOLE_RESOLUTION="$default_res"
  else
    CONSOLE_RESOLUTION=$res_input
  fi
  
  echo ""
  echo "Screen rotation:"
  echo "  0 = normal [recommended]"
  echo "  1 = 90 degrees clockwise"
  echo "  2 = 180 degrees"
  echo "  3 = 270 degrees clockwise"
  printf "Choice [0]: "
  read -r rot_input
  if [ -z "$rot_input" ]; then
    CONSOLE_ROTATE="0"
  else
    CONSOLE_ROTATE=$rot_input
  fi
  
  echo ""
  echo "Console configuration:"
  echo "  Font:      $CONSOLE_FONTSIZE"
  echo "  Resolution: $CONSOLE_RESOLUTION"
  echo "  Rotation:  $CONSOLE_ROTATE"
  echo ""
  printf "Proceed with these settings? [Y/n]: "
  read -r confirm
  case "$confirm" in
    n|N|no|No) exit 0 ;;
    *) ;;
  esac
}

# -----------------------------------------------------------------------------
# Main flow
# -----------------------------------------------------------------------------

# If we need sudo and don't have it, request it for the rest of the script
if [ "$NEEDS_SUDO" = "true" ]; then
  echo "This script requires sudo for system installation."
  echo "Please enter your password when prompted."
  SUDO_CMD="sudo"
fi

# Run interactive prompts as current user
show_header
prompt_target_user

# Resolve target user's home directory
TARGET_GROUP=$(id -gn "$TARGET_USER")
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
  echo "error: could not resolve home directory for user: $TARGET_USER" >&2
  exit 1
fi

prompt_console_settings

# -----------------------------------------------------------------------------
# Unprivileged operations (as current user)
# -----------------------------------------------------------------------------

# Create writing directory structure in user's home
mkdir -p "$TARGET_HOME/writing/projects/inbox"
chown -R "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/writing"
log "Created writing directory at $TARGET_HOME/writing"

# -----------------------------------------------------------------------------
# Privileged operations (via sudo)
# -----------------------------------------------------------------------------

install_required_packages() {
  required_packages="micro syncthing tailscale ufw python3"
  missing_packages=""
  
  for pkg in $required_packages; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q '^install ok installed$'; then
      missing_packages="$missing_packages $pkg"
    fi
  done
  
  missing_packages=$(printf '%s' "$missing_packages" | xargs)
  
  if [ -z "$missing_packages" ]; then
    log "All required packages already installed."
    return
  fi
  
  log "Installing missing packages: $missing_packages"
  sudo_if_needed apt-get update
  DEBIAN_FRONTEND=noninteractive sudo_if_needed apt-get install -y --no-install-recommends $missing_packages
}

render_default_config() {
  destination=$1
  sed "s|^root = \"/home/writer/writing/projects\"$|root = \"$TARGET_HOME/writing/projects\"|" \
    "$DEFAULT_CONFIG_PATH" > "$destination"
}

install_config() {
  rendered_default=$(mktemp)
  render_default_config "$rendered_default"
  
  if [ ! -f "$CONFIG_PATH" ]; then
    sudo_if_needed install -m 0644 "$rendered_default" "$CONFIG_PATH"
    rm -f "$rendered_default"
    log "Installed default config at $CONFIG_PATH"
    return
  fi
  
  if cmp -s "$DEFAULT_CONFIG_PATH" "$CONFIG_PATH"; then
    sudo_if_needed install -m 0644 "$CONFIG_PATH" "${CONFIG_PATH}.bak"
    sudo_if_needed install -m 0644 "$rendered_default" "$CONFIG_PATH"
    rm -f "$rendered_default"
    log "Migrated default config path for user $TARGET_USER"
    log "Backup written to: ${CONFIG_PATH}.bak"
    return
  fi
  
  if cmp -s "$rendered_default" "$CONFIG_PATH" || cmp -s "$DEFAULT_CONFIG_PATH" "$CONFIG_PATH"; then
    rm -f "$rendered_default"
    log "Config already matches defaults: $CONFIG_PATH"
    return
  fi
  
  sudo_if_needed install -m 0644 "$rendered_default" "${CONFIG_PATH}.dist"
  rm -f "$rendered_default"
  log "Kept existing config: $CONFIG_PATH"
  log "Wrote updated defaults to: ${CONFIG_PATH}.dist"
}

setup_console() {
  log "Configuring console: font=$CONSOLE_FONTSIZE, resolution=$CONSOLE_RESOLUTION, rotation=$CONSOLE_ROTATE"
  
  if [ -f /etc/default/console-setup ]; then
    sudo_if_needed sed -i "s|^FONTFACE=.*|FONTFACE=Terminus|" /etc/default/console-setup
    sudo_if_needed sed -i "s|^FONTSIZE=.*|FONTSIZE=$CONSOLE_FONTSIZE|" /etc/default/console-setup
    sudo_if_needed update-alternatives --set console-font /usr/share/consolefonts/"$CONSOLE_FONTSIZE" 2>/dev/null || true
    sudo_if_needed setupcon 2>/dev/null || true
    log "Console font set to $CONSOLE_FONTSIZE"
  fi
  
  CONFIG_TXT=""
  if [ -f /boot/firmware/config.txt ]; then
    CONFIG_TXT=/boot/firmware/config.txt
  elif [ -f /boot/config.txt ]; then
    CONFIG_TXT=/boot/config.txt
  fi
  
  if [ -n "$CONFIG_TXT" ]; then
    if [ "$CONSOLE_RESOLUTION" != "0" ]; then
      if ! grep -q "^hdmi_group=2" "$CONFIG_TXT" 2>/dev/null; then
        echo "hdmi_group=2" | sudo_if_needed tee -a "$CONFIG_TXT" >/dev/null
      fi
      if ! grep -q "^hdmi_mode=$CONSOLE_RESOLUTION" "$CONFIG_TXT" 2>/dev/null; then
        echo "hdmi_mode=$CONSOLE_RESOLUTION" | sudo_if_needed tee -a "$CONFIG_TXT" >/dev/null
      fi
    fi
    
    if [ "$CONSOLE_ROTATE" != "0" ]; then
      if ! grep -q "^display_rotate=$CONSOLE_ROTATE" "$CONFIG_TXT" 2>/dev/null; then
        echo "display_rotate=$CONSOLE_ROTATE" | sudo_if_needed tee -a "$CONFIG_TXT" >/dev/null
      fi
      log "Screen rotated by ${CONSOLE_ROTATE}°"
    fi
    log "Display config updated in $CONFIG_TXT"
  fi
}

# Run privileged installation steps
install_required_packages

sudo_if_needed install -d -m 0755 /etc/writerdeck
install_config
setup_console

sudo_if_needed install -d -m 0755 /usr/local/bin
sudo_if_needed install -m 0755 "$REPO_DIR/bin/wd" /usr/local/bin/wd
sudo_if_needed install -m 0755 "$REPO_DIR/bin/wd-session" /usr/local/bin/wd-session

sudo_if_needed install -d -m 0755 /etc/systemd/system/getty@tty1.service.d
sudo_if_needed tee /etc/systemd/system/getty@tty1.service.d/override.conf >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $TARGET_USER --noclear %I \$TERM
Type=idle
EOF

sudo_if_needed install -m 0644 "$REPO_DIR/deploy/profile-wd-session.sh" /etc/profile.d/wd-session.sh

# Enable services
sudo_if_needed systemctl daemon-reload
sudo_if_needed systemctl enable getty@tty1.service
if [ -f /lib/systemd/system/syncthing@.service ] || [ -f /usr/lib/systemd/system/syncthing@.service ]; then
  sudo_if_needed systemctl enable --now "syncthing@${TARGET_USER}.service"
else
  log "warning: syncthing@.service not found; skip enable/start"
fi

echo ""
echo "========================================"
echo "  Installation Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1) Configure tailscale: tailscale up"
echo "2) Configure syncthing folder id and devices"
echo "   (headless: ssh -L 58384:127.0.0.1:8384 ${TARGET_USER}@<deck>)"
echo "3) Adjust /etc/writerdeck/config.toml if needed"
echo "4) Reboot for display/console changes to take effect"
echo ""
echo "After reboot, tty1 will launch directly into the editor."
echo "Press Ctrl+Q in the editor to return to the menu."