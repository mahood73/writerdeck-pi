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
DEFAULT_FOOT_CONFIG_PATH="$REPO_DIR/deploy/foot.ini"
DEFAULT_CONSOLE_BLANK_SECONDS=600
STATE_DIR=/etc/writerdeck/uninstall

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

backup_file_if_missing() {
  source_path=$1
  backup_relative_path=$2
  backup_path="$STATE_DIR/$backup_relative_path"

  if [ ! -f "$source_path" ] || [ -f "$backup_path" ]; then
    return
  fi

  sudo_if_needed install -d -m 0755 "$(dirname "$backup_path")"
  sudo_if_needed cp -a "$source_path" "$backup_path"
}

# -----------------------------------------------------------------------------
# Interactive prompts - get user preferences
# -----------------------------------------------------------------------------

# MAP-FUNCTIONS-START
# Map common resolutions to hdmi_mode values (DMT modes)
get_hdmi_mode() {
  case "$1" in
    640x480)    echo "1" ;;
    800x600)    echo "9" ;;
    1024x600)   echo "51" ;;
    1024x768)   echo "16" ;;
    1280x720)   echo "82" ;;
    1280x1024)  echo "35" ;;
    1920x1080)  echo "86" ;;
    *)          echo "" ;;
  esac
}

# Map hdmi_mode values back to resolution strings
hdmi_mode_to_resolution() {
  case "$1" in
    1)   echo "640x480" ;;
    9)   echo "800x600" ;;
    51)  echo "1024x600" ;;
    16)  echo "1024x768" ;;
    82)  echo "1280x720" ;;
    35)  echo "1280x1024" ;;
    86)  echo "1920x1080" ;;
    *)   echo "" ;;
  esac
}
# MAP-FUNCTIONS-END

# LABEL-FUNCTION-START
# Returns the resolution prompt header line based on detection source.
# Args: $1 = configured_res (may be empty), $2 = detected_res (may be empty)
resolution_prompt_label() {
  _configured=$1
  _detected=$2
  if [ -n "$_configured" ]; then
    _label=$(hdmi_mode_to_resolution "$_configured")
    if [ -n "$_label" ]; then
      echo "HDMI resolution (configured: ${_label}, mode ${_configured}):"
    else
      echo "HDMI resolution (configured: mode ${_configured}):"
    fi
  elif [ -n "$_detected" ]; then
    _label=$(hdmi_mode_to_resolution "$_detected")
    if [ -n "$_label" ]; then
      echo "HDMI resolution (detected from display: ${_label}, mode ${_detected}):"
    else
      echo "HDMI resolution (detected from display: mode ${_detected}):"
    fi
  else
    echo "HDMI resolution (no display detected; suggested: mode 82):"
  fi
}
# LABEL-FUNCTION-END

probe_drm_resolution() {
  for status_file in /sys/class/drm/card*-HDMI-A-*/status; do
    [ -f "$status_file" ] || continue
    if grep -q "^connected$" "$status_file" 2>/dev/null; then
      mode_file=${status_file%/status}/modes
      if [ -f "$mode_file" ]; then
        preferred=$(sed -n '1p' "$mode_file" 2>/dev/null || true)
        if [ -n "$preferred" ]; then
          hdmi_mode=$(get_hdmi_mode "$preferred")
          if [ -n "$hdmi_mode" ]; then
            echo "$hdmi_mode"
            return 0
          fi
        fi
      fi
    fi
  done
  return 1
}

probe_framebuffer_resolution() {
  if command -v fbset >/dev/null 2>&1; then
    geometry=$(fbset -s 2>/dev/null | awk '/geometry/ { print $2 "x" $3; exit }')
    if [ -n "$geometry" ]; then
      hdmi_mode=$(get_hdmi_mode "$geometry")
      if [ -n "$hdmi_mode" ]; then
        echo "$hdmi_mode"
        return 0
      fi
    fi
  fi
  return 1
}

probe_resolution() {
  detected=$(probe_drm_resolution || true)
  if [ -n "$detected" ]; then
    echo "$detected"
    return
  fi

  detected=$(probe_framebuffer_resolution || true)
  if [ -n "$detected" ]; then
    echo "$detected"
    return
  fi

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

probe_configured_resolution() {
  cmdline_path=$1
  config_path=$2

  if [ -n "$cmdline_path" ] && [ -f "$cmdline_path" ]; then
    for arg in $(cat "$cmdline_path"); do
      case "$arg" in
        video=HDMI-A-1:*)
          video_spec=${arg#video=HDMI-A-1:}
          video_spec=${video_spec%%,*}
          video_spec=${video_spec%%@*}
          video_spec=${video_spec%M}
          hdmi_mode=$(get_hdmi_mode "$video_spec")
          if [ -n "$hdmi_mode" ]; then
            echo "$hdmi_mode"
            return
          fi
          ;;
      esac
    done
  fi

  if [ -n "$config_path" ] && [ -f "$config_path" ]; then
    hdmi_mode=$(sed -n 's/^hdmi_mode=\(.*\)$/\1/p' "$config_path" | head -1)
    if [ -n "$hdmi_mode" ]; then
      echo "$hdmi_mode"
      return
    fi
  fi

  echo ""
}

degrees_to_rotation() {
  case "$1" in
    90) echo "1" ;;
    180) echo "2" ;;
    270) echo "3" ;;
    *) echo "0" ;;
  esac
}

probe_configured_rotation() {
  cmdline_path=$1
  config_path=$2

  if [ -n "$cmdline_path" ] && [ -f "$cmdline_path" ]; then
    for arg in $(cat "$cmdline_path"); do
      case "$arg" in
        video=HDMI-A-1:*)
          rotation=$(printf '%s\n' "$arg" | sed -n 's/.*rotate=\([0-9][0-9]*\).*/\1/p')
          if [ -n "$rotation" ]; then
            degrees_to_rotation "$rotation"
            return
          fi
          ;;
      esac
    done
  fi

  if [ -n "$config_path" ] && [ -f "$config_path" ]; then
    rotation=$(sed -n 's/^display_rotate=\(.*\)$/\1/p' "$config_path" | head -1)
    if [ -n "$rotation" ]; then
      echo "$rotation"
      return
    fi
  fi

  echo ""
}

probe_configured_consoleblank() {
  cmdline_path=$1

  if [ -n "$cmdline_path" ] && [ -f "$cmdline_path" ]; then
    for arg in $(cat "$cmdline_path"); do
      case "$arg" in
        consoleblank=*)
          echo "${arg#consoleblank=}"
          return
          ;;
      esac
    done
  fi

  echo ""
}

is_supported_resolution() {
  case "$1" in
    0|1|9|16|35|51|82|86) return 0 ;;
    *) return 1 ;;
  esac
}

is_supported_rotation() {
  case "$1" in
    0|1|2|3) return 0 ;;
    *) return 1 ;;
  esac
}

is_non_negative_integer() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
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

  echo ""
  echo "Display settings:"
  echo "  Press Enter to keep the current setting shown in brackets."
  echo ""

  configured_res=$(probe_configured_resolution "$CMDLINE_TXT" "$CONFIG_TXT")
  detected_res=$(probe_resolution)
  DETECTED_RESOLUTION=${configured_res:-$detected_res}
  default_res=${configured_res:-${detected_res:-82}}

  configured_rotate=$(probe_configured_rotation "$CMDLINE_TXT" "$CONFIG_TXT")
  default_rotate=${configured_rotate:-0}

  configured_blank=$(probe_configured_consoleblank "$CMDLINE_TXT")
  default_blank=${configured_blank:-$DEFAULT_CONSOLE_BLANK_SECONDS}

  resolution_prompt_label "${configured_res:-}" "${detected_res:-}"
  echo "  51 = 1024x600 (WriterDeck panel)"
  echo "  82 = 1280x720 (720p)"
  echo "  86 = 1920x1080 (1080p)"
  echo "  0  = skip (use current)"
  while :; do
    printf "Choice [%s]: " "$default_res"
    read -r res_input
    if [ -z "$res_input" ]; then
      CONSOLE_RESOLUTION="$default_res"
    else
      CONSOLE_RESOLUTION=$res_input
    fi

    if is_supported_resolution "$CONSOLE_RESOLUTION"; then
      break
    fi

    echo "Please choose one of: 0, 51, 82, or 86."
  done
  
  echo ""
  echo "Physical screen orientation:"
  echo "  Choose how the display is mounted right now."
  echo "  The installer will rotate the console to match."
  echo "  0 = mounted normally"
  echo "  1 = display is turned 90 degrees clockwise"
  echo "  2 = display is upside down"
  echo "  3 = display is turned 90 degrees anti-clockwise"
  while :; do
    printf "Choice [%s]: " "$default_rotate"
    read -r rot_input
    if [ -z "$rot_input" ]; then
      CONSOLE_ROTATE=$default_rotate
    else
      CONSOLE_ROTATE=$rot_input
    fi

    if is_supported_rotation "$CONSOLE_ROTATE"; then
      break
    fi

    echo "Please choose one of: 0, 1, 2, or 3."
  done

  echo ""
  echo "Console blanking timeout in seconds:"
  echo "  600 = blank after 10 minutes [recommended]"
  echo "  0   = disable blanking"
  while :; do
    printf "Choice [%s]: " "$default_blank"
    read -r blank_input
    if [ -z "$blank_input" ]; then
      CONSOLE_BLANK_SECONDS=$default_blank
    else
      CONSOLE_BLANK_SECONDS=$blank_input
    fi

    if is_non_negative_integer "$CONSOLE_BLANK_SECONDS"; then
      break
    fi

    echo "Please enter a whole number of seconds, or 0 to disable blanking."
  done

}

prompt_writing_folder() {
  echo ""
  echo "Writing folder:"

  while true; do
    printf "Writing folder [~/Writing]: "
    read -r folder_input

    if [ -z "$folder_input" ]; then
      WRITING_ROOT="$TARGET_HOME/Writing"
      break
    fi

    # Expand a leading ~/ or bare ~ against the target user's home
    case "$folder_input" in
      "~/"*) folder_input="$TARGET_HOME/${folder_input#~/}" ;;
      "~")   folder_input="$TARGET_HOME" ;;
    esac

    WRITING_ROOT="$folder_input"

    # Warn if path falls outside target user's home
    case "$WRITING_ROOT" in
      "$TARGET_HOME/"*|"$TARGET_HOME")
        break
        ;;
      *)
        printf "Warning: this path is outside your home directory. Are you sure? [y/N]: "
        read -r confirm
        case "$confirm" in
          y|Y|yes|YES) break ;;
          *) echo "Cancelled. Please enter a different path." ;;
        esac
        ;;
    esac
  done
}

set_config_key() {
  config_path=$1
  key=$2
  value=$3

  if grep -q "^${key}=" "$config_path" 2>/dev/null; then
    sudo_if_needed sed -i "s|^${key}=.*|${key}=${value}|" "$config_path"
  else
    echo "${key}=${value}" | sudo_if_needed tee -a "$config_path" >/dev/null
  fi
}

remove_config_key() {
  config_path=$1
  key=$2

  if grep -q "^${key}=" "$config_path" 2>/dev/null; then
    sudo_if_needed sed -i "/^${key}=/d" "$config_path"
  fi
}

rotation_to_degrees() {
  case "$1" in
    1) echo "90" ;;
    2) echo "180" ;;
    3) echo "270" ;;
    *) echo "" ;;
  esac
}

configure_cmdline_video() {
  cmdline_path=$1
  video_arg=$2
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

configure_config_blank_timeout() {
  config_path=$1
  seconds=$2
  if grep -q '^\[display\]' "$config_path" 2>/dev/null; then
    if grep -q '^blank_timeout *=' "$config_path" 2>/dev/null; then
      sudo_if_needed sed -i "s/^blank_timeout *=.*/blank_timeout = $seconds/" "$config_path"
    else
      sudo_if_needed sed -i "/^\[display\]/a blank_timeout = $seconds" "$config_path"
    fi
  else
    printf '\n[display]\nblank_timeout = %s\n' "$seconds" | sudo_if_needed tee -a "$config_path" >/dev/null
  fi
}

configure_cmdline_consoleblank() {
  cmdline_path=$1
  blank_seconds=$2
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

configure_cmdline_remove_serial_console() {
  cmdline_path=$1
  current_cmdline=$(cat "$cmdline_path")
  updated_cmdline=""

  for arg in $current_cmdline; do
    case "$arg" in
      console=serial0,*|console=ttyAMA0,*|console=ttyS0,*) ;;
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

configure_cmdline_splash() {
  cmdline_path=$1
  current_cmdline=$(cat "$cmdline_path")
  updated_cmdline=""

  for arg in $current_cmdline; do
    case "$arg" in
      quiet|splash|vt.global_cursor_default=*) ;;
      *) updated_cmdline="${updated_cmdline}${updated_cmdline:+ }$arg" ;;
    esac
  done

  updated_cmdline="${updated_cmdline}${updated_cmdline:+ }quiet splash vt.global_cursor_default=0"

  if [ "$updated_cmdline" = "$current_cmdline" ]; then
    return 1
  fi

  rendered_cmdline=$(mktemp)
  printf '%s\n' "$updated_cmdline" > "$rendered_cmdline"
  sudo_if_needed install -m 0644 "$rendered_cmdline" "$cmdline_path"
  rm -f "$rendered_cmdline"
  return 0
}

install_plymouth_splash() {
  PLYMOUTH_THEME_SRC="$REPO_DIR/assets/plymouth/writerdeck"
  PLYMOUTH_THEME_DEST="/usr/share/plymouth/themes/writerdeck"

  LOCAL_CONFIG_TXT=""
  if [ -f /boot/firmware/config.txt ]; then
    LOCAL_CONFIG_TXT=/boot/firmware/config.txt
  elif [ -f /boot/config.txt ]; then
    LOCAL_CONFIG_TXT=/boot/config.txt
  fi

  LOCAL_CMDLINE_TXT=""
  if [ -f /boot/firmware/cmdline.txt ]; then
    LOCAL_CMDLINE_TXT=/boot/firmware/cmdline.txt
  elif [ -f /boot/cmdline.txt ]; then
    LOCAL_CMDLINE_TXT=/boot/cmdline.txt
  fi

  sudo_if_needed install -d -m 0755 "$PLYMOUTH_THEME_DEST"
  sudo_if_needed install -m 0644 "$PLYMOUTH_THEME_SRC/writerdeck.plymouth" "$PLYMOUTH_THEME_DEST/writerdeck.plymouth"
  sudo_if_needed install -m 0644 "$PLYMOUTH_THEME_SRC/writerdeck.script" "$PLYMOUTH_THEME_DEST/writerdeck.script"
  log "Installed Plymouth theme at $PLYMOUTH_THEME_DEST"

  HOOK_SRC="$REPO_DIR/assets/initramfs-hooks/writerdeck-plymouth"
  HOOK_DEST="/etc/initramfs-tools/hooks/writerdeck-plymouth"
  if [ -f "$HOOK_SRC" ]; then
    sudo_if_needed install -m 0755 "$HOOK_SRC" "$HOOK_DEST"
    log "Installed initramfs hook at $HOOK_DEST"
  fi

  if [ -n "$LOCAL_CONFIG_TXT" ]; then
    backup_file_if_missing "$LOCAL_CONFIG_TXT" "${LOCAL_CONFIG_TXT#/}"
    set_config_key "$LOCAL_CONFIG_TXT" "disable_splash" "1"
    log "Set disable_splash=1 in $LOCAL_CONFIG_TXT"
    set_config_key "$LOCAL_CONFIG_TXT" "framebuffer_width" "1024"
    set_config_key "$LOCAL_CONFIG_TXT" "framebuffer_height" "600"
    log "Set framebuffer_width=1024 framebuffer_height=600 in $LOCAL_CONFIG_TXT"
  fi

  if [ -n "$LOCAL_CMDLINE_TXT" ]; then
    backup_file_if_missing "$LOCAL_CMDLINE_TXT" "${LOCAL_CMDLINE_TXT#/}"
    if configure_cmdline_remove_serial_console "$LOCAL_CMDLINE_TXT"; then
      log "Removed serial console from $LOCAL_CMDLINE_TXT"
    fi
    if configure_cmdline_splash "$LOCAL_CMDLINE_TXT"; then
      log "Added quiet splash vt.global_cursor_default=0 to $LOCAL_CMDLINE_TXT"
    fi
  fi

  sudo_if_needed /usr/sbin/plymouth-set-default-theme writerdeck
  PLYMOUTH_CONF=/etc/plymouth/plymouthd.conf
  if [ -f "$PLYMOUTH_CONF" ]; then
    if ! grep -q "^DeviceTimeout=" "$PLYMOUTH_CONF"; then
      sudo_if_needed sed -i "/^\[Daemon\]/a DeviceTimeout=2" "$PLYMOUTH_CONF"
      log "Set DeviceTimeout=2 in $PLYMOUTH_CONF"
    fi
    if ! grep -q "^ShowDelay=" "$PLYMOUTH_CONF"; then
      sudo_if_needed sed -i "/^\[Daemon\]/a ShowDelay=0" "$PLYMOUTH_CONF"
      log "Set ShowDelay=0 in $PLYMOUTH_CONF"
    fi
  fi

  INITRAMFS_CONF=/etc/initramfs-tools/initramfs.conf
  if [ -f "$INITRAMFS_CONF" ] && grep -q "^MODULES=dep" "$INITRAMFS_CONF"; then
    sudo_if_needed sed -i "s/^MODULES=dep/MODULES=most/" "$INITRAMFS_CONF"
    log "Set MODULES=most in $INITRAMFS_CONF (required for early Plymouth display)"
  fi
  log "Rebuilding initramfs to apply Plymouth theme — this takes a few minutes."
  log "(Note: apt already rebuilt it once per installed kernel above; this final rebuild applies the theme.)"
  sudo_if_needed update-initramfs -u
  log "Plymouth splash screen configured."
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
prompt_writing_folder

echo ""
echo "Configuration:"
echo "  Resolution: $CONSOLE_RESOLUTION"
echo "  Screen orientation: $CONSOLE_ROTATE"
echo "  Screen blanking: $CONSOLE_BLANK_SECONDS seconds"
echo "  Writing folder: $WRITING_ROOT"
echo ""
printf "Proceed with these settings? [Y/n]: "
read -r confirm
case "$confirm" in
  n|N|no|No) exit 0 ;;
  *) ;;
esac

# -----------------------------------------------------------------------------
# Privileged operations (via sudo)
# -----------------------------------------------------------------------------

install_required_packages() {
  required_packages="wordgrinder-ncurses cage foot labwc wlopm swayidle python3 plymouth plymouth-label"
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

setup_writing_folder() {
  if [ -d "$WRITING_ROOT" ]; then
    log "Writing folder already exists at $WRITING_ROOT"
  else
    log "Created writing folder at $WRITING_ROOT"
  fi

  sudo_if_needed install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$WRITING_ROOT"
  sudo_if_needed install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$WRITING_ROOT/inbox"

  # Test writability as TARGET_USER, not as the installer process (which may be root)
  if ! sudo -u "$TARGET_USER" test -w "$WRITING_ROOT" 2>/dev/null; then
    echo "error: $TARGET_USER cannot write to $WRITING_ROOT" >&2
    echo "Check ownership and permissions: ls -ld $WRITING_ROOT" >&2
    exit 1
  fi
}

render_default_config() {
  destination=$1
  sed "s|^root = \"~/Writing\"$|root = \"$WRITING_ROOT\"|" \
    "$DEFAULT_CONFIG_PATH" > "$destination"
}

install_config() {
  rendered_default=$(mktemp)
  render_default_config "$rendered_default"
  
  if [ ! -f "$CONFIG_PATH" ]; then
    sudo_if_needed install -m 0644 -o "$TARGET_USER" "$rendered_default" "$CONFIG_PATH"
    rm -f "$rendered_default"
    log "Installed default config at $CONFIG_PATH"
    return
  fi

  if cmp -s "$DEFAULT_CONFIG_PATH" "$CONFIG_PATH"; then
    sudo_if_needed install -m 0644 -o "$TARGET_USER" "$CONFIG_PATH" "${CONFIG_PATH}.bak"
    sudo_if_needed install -m 0644 -o "$TARGET_USER" "$rendered_default" "$CONFIG_PATH"
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
  
  sudo_if_needed install -m 0644 -o "$TARGET_USER" "$rendered_default" "${CONFIG_PATH}.dist"
  rm -f "$rendered_default"
  log "Kept existing config: $CONFIG_PATH"
  log "Wrote updated defaults to: ${CONFIG_PATH}.dist"
}

install_user_foot_config() {
  foot_config_dir="$TARGET_HOME/.config/foot"
  foot_config_path="$foot_config_dir/foot.ini"
  foot_dist_path="$foot_config_dir/foot.ini.dist"

  sudo_if_needed install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$foot_config_dir"

  if [ ! -f "$foot_config_path" ]; then
    sudo_if_needed install -m 0644 -o "$TARGET_USER" -g "$TARGET_GROUP" "$DEFAULT_FOOT_CONFIG_PATH" "$foot_config_path"
    log "Installed foot config at $foot_config_path"
    return
  fi

  if cmp -s "$DEFAULT_FOOT_CONFIG_PATH" "$foot_config_path"; then
    log "Foot config already matches defaults: $foot_config_path"
    return
  fi

  sudo_if_needed install -m 0644 -o "$TARGET_USER" -g "$TARGET_GROUP" "$DEFAULT_FOOT_CONFIG_PATH" "$foot_dist_path"
  log "Kept existing foot config: $foot_config_path"
  log "Wrote updated foot defaults to: $foot_dist_path"
}

setup_console() {
  log "Configuring console: resolution=$CONSOLE_RESOLUTION, rotation=$CONSOLE_ROTATE"
  
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
    backup_file_if_missing "$CONFIG_TXT" "${CONFIG_TXT#/}"
    remove_config_key "$CONFIG_TXT" "display_rotate"

    if [ -z "$CMDLINE_TXT" ]; then
      if [ "$CONSOLE_RESOLUTION" != "0" ]; then
        set_config_key "$CONFIG_TXT" "hdmi_group" "2"
        set_config_key "$CONFIG_TXT" "hdmi_mode" "$CONSOLE_RESOLUTION"
      else
        remove_config_key "$CONFIG_TXT" "hdmi_group"
        remove_config_key "$CONFIG_TXT" "hdmi_mode"
      fi
    else
      remove_config_key "$CONFIG_TXT" "hdmi_group"
      remove_config_key "$CONFIG_TXT" "hdmi_mode"
    fi
    log "Display config updated in $CONFIG_TXT"
  fi
  
  if [ "$CONSOLE_ROTATE" != "0" ]; then
    case "$CONSOLE_ROTATE" in
      1) log "Screen rotated 90° clockwise" ;;
      2) log "Screen rotated 180°" ;;
      3) log "Screen rotated 270° clockwise" ;;
    esac
  fi

  if [ -n "$CMDLINE_TXT" ]; then
    backup_file_if_missing "$CMDLINE_TXT" "${CMDLINE_TXT#/}"
    video_resolution=""
    if [ "$CONSOLE_RESOLUTION" != "0" ]; then
      video_resolution=$(hdmi_mode_to_resolution "$CONSOLE_RESOLUTION")
    elif [ "$CONSOLE_ROTATE" != "0" ] && [ -n "${DETECTED_RESOLUTION:-}" ]; then
      video_resolution=$(hdmi_mode_to_resolution "$DETECTED_RESOLUTION")
    fi

    video_param=""
    if [ -n "$video_resolution" ]; then
      video_param="video=HDMI-A-1:${video_resolution}M@60"
      if [ "$CONSOLE_ROTATE" != "0" ]; then
        rot_degrees=$(rotation_to_degrees "$CONSOLE_ROTATE")
        if [ -n "$rot_degrees" ]; then
          video_param="${video_param},rotate=${rot_degrees}"
        fi
      fi
    elif [ "$CONSOLE_ROTATE" != "0" ]; then
      log "warning: could not determine current HDMI mode; skipping rotation override"
    fi

    if configure_cmdline_video "$CMDLINE_TXT" "$video_param"; then
      if [ -n "$video_param" ]; then
        log "Updated kernel video mode in $CMDLINE_TXT"
      else
        log "Removed kernel video override from $CMDLINE_TXT"
      fi
    fi

    if configure_cmdline_consoleblank "$CMDLINE_TXT" "$CONSOLE_BLANK_SECONDS"; then
      if [ "$CONSOLE_BLANK_SECONDS" = "0" ]; then
        log "Disabled console blanking in $CMDLINE_TXT"
      else
        log "Set console blanking to $CONSOLE_BLANK_SECONDS seconds in $CMDLINE_TXT"
      fi
    fi
    configure_config_blank_timeout "$CONFIG_PATH" "$CONSOLE_BLANK_SECONDS"
    log "Set display blank_timeout to $CONSOLE_BLANK_SECONDS seconds in $CONFIG_PATH"
  fi
}

# Run privileged installation steps
install_required_packages

sudo_if_needed install -d -m 0755 /etc/writerdeck
sudo_if_needed install -d -m 0755 "$STATE_DIR"
backup_file_if_missing "$CONFIG_PATH" etc/writerdeck/config.toml
setup_writing_folder
install_config
install_user_foot_config
setup_console
install_plymouth_splash
# Ensure TARGET_USER can edit the config (settings menu writes it directly).
# Must run after all install steps that write to CONFIG_PATH.
sudo_if_needed chown "$TARGET_USER" "$CONFIG_PATH"

sudo_if_needed install -d -m 0755 /usr/local/bin
sudo_if_needed install -d -m 0755 /usr/local/scripts
backup_file_if_missing /usr/local/bin/wd usr/local/bin/wd
backup_file_if_missing /usr/local/bin/wd-menu usr/local/bin/wd-menu
backup_file_if_missing /usr/local/bin/wd-session usr/local/bin/wd-session
backup_file_if_missing /usr/local/bin/wd-labwc-session usr/local/bin/wd-labwc-session
backup_file_if_missing /usr/local/scripts/wd-export.lua usr/local/scripts/wd-export.lua
sudo_if_needed install -m 0755 "$REPO_DIR/bin/wd" /usr/local/bin/wd
sudo_if_needed install -m 0755 "$REPO_DIR/bin/wd-menu" /usr/local/bin/wd-menu
sudo_if_needed install -m 0755 "$REPO_DIR/bin/wd-session" /usr/local/bin/wd-session
sudo_if_needed install -m 0755 "$REPO_DIR/deploy/wd-labwc-session.sh" /usr/local/bin/wd-labwc-session
sudo_if_needed install -m 0755 "$REPO_DIR/scripts/wd-export.lua" /usr/local/scripts/wd-export.lua

sudo_if_needed install -d -m 0755 /etc/systemd/system/getty@tty1.service.d
backup_file_if_missing /etc/systemd/system/getty@tty1.service.d/override.conf etc/systemd/system/getty@tty1.service.d/override.conf
sudo_if_needed tee /etc/systemd/system/getty@tty1.service.d/override.conf >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $TARGET_USER --noclear %I \$TERM
Type=idle
EOF

backup_file_if_missing /etc/profile.d/wd-session.sh etc/profile.d/wd-session.sh
sudo_if_needed install -m 0644 "$REPO_DIR/deploy/profile-wd-session.sh" /etc/profile.d/wd-session.sh

# Enable services
sudo_if_needed systemctl daemon-reload
sudo_if_needed systemctl enable getty@tty1.service

echo ""
echo "========================================"
echo "  Installation Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1) Adjust /etc/writerdeck/config.toml if needed"
echo "2) Reboot for display/console changes to take effect"
echo ""
echo "After reboot, tty1 will launch directly into the editor."
echo "Press Ctrl+Q in the editor to return to the menu."
