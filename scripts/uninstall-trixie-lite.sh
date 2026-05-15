#!/bin/sh
#
# WriterDeck uninstaller for Raspberry Pi Zero 2W on Debian Trixie Lite.
# Run as: ./uninstall-trixie-lite.sh  (uses sudo for privileged operations)
#

set -eu

INITIAL_USER=$(whoami)
NEEDS_SUDO=false

if [ "$(id -u)" -ne 0 ]; then
  if sudo -n true 2>/dev/null; then
    SUDO_CMD="sudo"
  else
    NEEDS_SUDO=true
  fi
else
  SUDO_CMD=""
fi

CONFIG_PATH=/etc/writerdeck/config.toml
STATE_DIR=/etc/writerdeck/uninstall

log() {
  printf '%s\n' "$*"
}

sudo_if_needed() {
  if [ -n "$SUDO_CMD" ]; then
    $SUDO_CMD "$@"
  else
    "$@"
  fi
}

show_header() {
  echo ""
  echo "========================================"
  echo "  WriterDeck Uninstall"
  echo "========================================"
}

detect_default_target_user() {
  if [ -f /etc/systemd/system/getty@tty1.service.d/override.conf ]; then
    detected_user=$(sed -n 's/.*--autologin \([^ ]*\) .*/\1/p' /etc/systemd/system/getty@tty1.service.d/override.conf | head -1)
    if [ -n "$detected_user" ]; then
      echo "$detected_user"
      return
    fi
  fi

  if [ -f "$CONFIG_PATH" ]; then
    detected_user=$(sed -n 's|^root = "/home/\([^/]*\)/Writing"$|\1|p' "$CONFIG_PATH" | head -1)
    if [ -n "$detected_user" ]; then
      echo "$detected_user"
      return
    fi
    detected_user=$(sed -n 's|^root = "/home/\([^/]*\)/writing/projects"$|\1|p' "$CONFIG_PATH" | head -1)
    if [ -n "$detected_user" ]; then
      echo "$detected_user"
      return
    fi
  fi

  if [ "$INITIAL_USER" = "root" ] && [ -n "${SUDO_USER:-}" ]; then
    echo "$SUDO_USER"
    return
  fi

  if [ "$INITIAL_USER" != "root" ]; then
    echo "$INITIAL_USER"
    return
  fi

  echo ""
}

prompt_target_user() {
  DEFAULT_USER=$(detect_default_target_user)

  echo ""
  echo "This will remove the tty1 WriterDeck login/session integration and undo"
  echo "WriterDeck-managed console boot overrides where possible."
  echo ""

  if [ -n "$DEFAULT_USER" ]; then
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

  TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)
}

prompt_data_removal() {
  REMOVE_WRITING_DATA=false

  if [ -n "${TARGET_HOME:-}" ] && [ -d "$TARGET_HOME/Writing" ]; then
    echo ""
    printf "Remove writing data at %s/Writing too? [y/N]: " "$TARGET_HOME"
    read -r remove_data_input
    case "$remove_data_input" in
      y|Y|yes|Yes) REMOVE_WRITING_DATA=true ;;
      *) ;;
    esac
  elif [ -n "${TARGET_HOME:-}" ] && [ -d "$TARGET_HOME/writing" ]; then
    echo ""
    printf "Remove writing data at %s/writing too? [y/N]: " "$TARGET_HOME"
    read -r remove_data_input
    case "$remove_data_input" in
      y|Y|yes|Yes) REMOVE_WRITING_DATA=true ;;
      *) ;;
    esac
  fi
}

restore_file_from_backup() {
  destination=$1
  backup_relative_path=$2
  backup_path="$STATE_DIR/$backup_relative_path"

  if [ ! -f "$backup_path" ]; then
    return 1
  fi

  sudo_if_needed install -d -m 0755 "$(dirname "$destination")"
  sudo_if_needed cp -a "$backup_path" "$destination"
  return 0
}

remove_file_if_present() {
  path=$1
  if [ -e "$path" ]; then
    sudo_if_needed rm -f "$path"
  fi
}

remove_dir_if_empty() {
  path=$1
  if [ -d "$path" ]; then
    sudo_if_needed rmdir "$path" 2>/dev/null || true
  fi
}

remove_config_key() {
  config_path=$1
  key=$2

  if [ -f "$config_path" ] && grep -q "^${key}=" "$config_path" 2>/dev/null; then
    sudo_if_needed sed -i "/^${key}=/d" "$config_path"
  fi
}

configure_cmdline_video() {
  cmdline_path=$1
  video_arg=$2

  if [ ! -f "$cmdline_path" ]; then
    return 1
  fi

  current_cmdline=$(cat "$cmdline_path")
  updated_cmdline=""

  for arg in $current_cmdline; do
    case "$arg" in
      video=HDMI-A-1:*) ;;
      *) updated_cmdline="${updated_cmdline}${updated_cmdline:+ }$arg" ;;
    esac
  done

  if [ -n "$video_arg" ]; then
    updated_cmdline="${updated_cmdline}${updated_cmdline:+ }$video_arg"
  fi

  if [ "$updated_cmdline" = "$current_cmdline" ]; then
    return 1
  fi

  rendered_cmdline=$(mktemp)
  printf '%s\n' "$updated_cmdline" > "$rendered_cmdline"
  sudo_if_needed install -m 0644 "$rendered_cmdline" "$cmdline_path"
  rm -f "$rendered_cmdline"
  return 0
}

configure_cmdline_consoleblank() {
  cmdline_path=$1
  blank_seconds=$2

  if [ ! -f "$cmdline_path" ]; then
    return 1
  fi

  current_cmdline=$(cat "$cmdline_path")
  updated_cmdline=""

  for arg in $current_cmdline; do
    case "$arg" in
      consoleblank=*) ;;
      *) updated_cmdline="${updated_cmdline}${updated_cmdline:+ }$arg" ;;
    esac
  done

  if [ -n "$blank_seconds" ]; then
    updated_cmdline="${updated_cmdline}${updated_cmdline:+ }consoleblank=${blank_seconds}"
  fi

  if [ "$updated_cmdline" = "$current_cmdline" ]; then
    return 1
  fi

  rendered_cmdline=$(mktemp)
  printf '%s\n' "$updated_cmdline" > "$rendered_cmdline"
  sudo_if_needed install -m 0644 "$rendered_cmdline" "$cmdline_path"
  rm -f "$rendered_cmdline"
  return 0
}

configure_cmdline_remove_splash() {
  cmdline_path=$1

  if [ ! -f "$cmdline_path" ]; then
    return 1
  fi

  current_cmdline=$(cat "$cmdline_path")
  updated_cmdline=""

  for arg in $current_cmdline; do
    case "$arg" in
      quiet|splash|vt.global_cursor_default=*) ;;
      *) updated_cmdline="${updated_cmdline}${updated_cmdline:+ }$arg" ;;
    esac
  done

  if [ "$updated_cmdline" = "$current_cmdline" ]; then
    return 1
  fi

  rendered_cmdline=$(mktemp)
  printf '%s\n' "$updated_cmdline" > "$rendered_cmdline"
  sudo_if_needed install -m 0644 "$rendered_cmdline" "$cmdline_path"
  rm -f "$rendered_cmdline"
  return 0
}

remove_plymouth_splash() {
  PLYMOUTH_THEME_DEST="/usr/share/plymouth/themes/writerdeck"

  if [ -d "$PLYMOUTH_THEME_DEST" ]; then
    sudo_if_needed rm -rf "$PLYMOUTH_THEME_DEST"
    log "Removed Plymouth theme at $PLYMOUTH_THEME_DEST"
  fi

  HOOK_DEST="/etc/initramfs-tools/hooks/writerdeck-plymouth"
  if [ -f "$HOOK_DEST" ]; then
    sudo_if_needed rm -f "$HOOK_DEST"
    log "Removed initramfs hook at $HOOK_DEST"
  fi

  PLYMOUTH_CONF=/etc/plymouth/plymouthd.conf
  if [ -f "$PLYMOUTH_CONF" ]; then
    sudo_if_needed sed -i "/^DeviceTimeout=/d;/^ShowDelay=/d" "$PLYMOUTH_CONF"
    log "Removed DeviceTimeout and ShowDelay from $PLYMOUTH_CONF"
  fi

  INITRAMFS_CONF=/etc/initramfs-tools/initramfs.conf
  if [ -f "$INITRAMFS_CONF" ] && grep -q "^MODULES=most" "$INITRAMFS_CONF"; then
    sudo_if_needed sed -i "s/^MODULES=most/MODULES=dep/" "$INITRAMFS_CONF"
    log "Restored MODULES=dep in $INITRAMFS_CONF"
  fi

  PLYMOUTH_RESET_CMD=""
  if [ -x /usr/sbin/plymouth-set-default-theme ]; then
    PLYMOUTH_RESET_CMD=/usr/sbin/plymouth-set-default-theme
  elif command -v plymouth-set-default-theme >/dev/null 2>&1; then
    PLYMOUTH_RESET_CMD=$(command -v plymouth-set-default-theme)
  fi
  if [ -n "$PLYMOUTH_RESET_CMD" ]; then
    sudo_if_needed "$PLYMOUTH_RESET_CMD" text
    log "Reset Plymouth theme to text"
    log "Rebuilding initramfs — this may take about a minute on Pi Zero 2W..."
    sudo_if_needed update-initramfs -u
  fi
}

restore_or_remove_console_files() {
  if restore_file_from_backup /etc/default/console-setup etc/default/console-setup; then
    log "Restored /etc/default/console-setup from backup"
    sudo_if_needed setupcon 2>/dev/null || true
  else
    log "warning: no backup for /etc/default/console-setup; leaving current console font settings in place"
  fi

  CONFIG_TXT=""
  if [ -f /boot/firmware/config.txt ]; then
    CONFIG_TXT=/boot/firmware/config.txt
  elif [ -f /boot/config.txt ]; then
    CONFIG_TXT=/boot/config.txt
  fi

  CMDLINE_TXT=""
  if [ -f /boot/firmware/cmdline.txt ]; then
    CMDLINE_TXT=/boot/firmware/cmdline.txt
  elif [ -f /boot/cmdline.txt ]; then
    CMDLINE_TXT=/boot/cmdline.txt
  fi

  if [ -n "$CONFIG_TXT" ]; then
    if restore_file_from_backup "$CONFIG_TXT" "${CONFIG_TXT#/}"; then
      log "Restored $CONFIG_TXT from backup"
    else
      remove_config_key "$CONFIG_TXT" "display_rotate"
      remove_config_key "$CONFIG_TXT" "hdmi_group"
      remove_config_key "$CONFIG_TXT" "hdmi_mode"
      remove_config_key "$CONFIG_TXT" "disable_splash"
      remove_config_key "$CONFIG_TXT" "framebuffer_width"
      remove_config_key "$CONFIG_TXT" "framebuffer_height"
      log "Removed WriterDeck display keys from $CONFIG_TXT"
    fi
  fi

  if [ -n "$CMDLINE_TXT" ]; then
    if restore_file_from_backup "$CMDLINE_TXT" "${CMDLINE_TXT#/}"; then
      log "Restored $CMDLINE_TXT from backup"
    else
      configure_cmdline_video "$CMDLINE_TXT" "" || true
      configure_cmdline_consoleblank "$CMDLINE_TXT" "" || true
      configure_cmdline_remove_splash "$CMDLINE_TXT" || true
      log "Removed WriterDeck kernel cmdline overrides from $CMDLINE_TXT"
    fi
  fi
}

restore_or_remove_file() {
  destination=$1
  backup_relative_path=$2

  if restore_file_from_backup "$destination" "$backup_relative_path"; then
    log "Restored $destination from backup"
  else
    remove_file_if_present "$destination"
    log "Removed $destination"
  fi
}

cleanup_state_dir() {
  if [ -d "$STATE_DIR" ]; then
    sudo_if_needed rm -rf "$STATE_DIR"
  fi
}

if [ "$NEEDS_SUDO" = "true" ]; then
  echo "This script requires sudo for system changes."
  echo "Please enter your password when prompted."
  SUDO_CMD="sudo"
fi

show_header
prompt_target_user
prompt_data_removal

restore_or_remove_console_files
remove_plymouth_splash
remove_file_if_present /etc/systemd/system/getty@tty1.service.d/override.conf
log "Removed /etc/systemd/system/getty@tty1.service.d/override.conf"
remove_file_if_present /etc/profile.d/wd-session.sh
log "Removed /etc/profile.d/wd-session.sh"
remove_file_if_present /usr/local/bin/wd
log "Removed /usr/local/bin/wd"
remove_file_if_present /usr/local/bin/wd-session
log "Removed /usr/local/bin/wd-session"
remove_file_if_present /usr/local/bin/wd-menu
log "Removed /usr/local/bin/wd-menu"
remove_file_if_present /usr/local/bin/wd-labwc-session
log "Removed /usr/local/bin/wd-labwc-session"
remove_file_if_present /usr/local/scripts/wd-export.lua
log "Removed /usr/local/scripts/wd-export.lua"

if restore_file_from_backup "$CONFIG_PATH" etc/writerdeck/config.toml; then
  log "Restored $CONFIG_PATH from backup"
else
  remove_file_if_present "$CONFIG_PATH"
  remove_file_if_present "${CONFIG_PATH}.dist"
  remove_file_if_present "${CONFIG_PATH}.bak"
  log "Removed WriterDeck config files"
fi

cleanup_state_dir

remove_dir_if_empty /etc/systemd/system/getty@tty1.service.d
remove_dir_if_empty /etc/writerdeck

if [ "$REMOVE_WRITING_DATA" = "true" ] && [ -n "${TARGET_HOME:-}" ] && [ -d "$TARGET_HOME/Writing" ]; then
  sudo_if_needed rm -rf "$TARGET_HOME/Writing"
  log "Removed $TARGET_HOME/Writing"
elif [ "$REMOVE_WRITING_DATA" = "true" ] && [ -n "${TARGET_HOME:-}" ] && [ -d "$TARGET_HOME/writing" ]; then
  sudo_if_needed rm -rf "$TARGET_HOME/writing"
  log "Removed $TARGET_HOME/writing"
fi

sudo_if_needed systemctl daemon-reload
sudo_if_needed systemctl restart getty@tty1.service 2>/dev/null || true

echo ""
echo "========================================"
echo "  Uninstall Complete!"
echo "========================================"
echo ""
echo "WriterDeck tty1 autologin/session hooks have been removed."
echo "Packages such as wordgrinder-ncurses, cage, foot, labwc, and plymouth were left installed."
echo "Reboot if you want the restored console boot settings applied immediately."
