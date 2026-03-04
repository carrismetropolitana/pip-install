#!/bin/bash

# Visual Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ------------------------------------------------------------------
# Helper Function: Run a command quietly, show [OK] or [FAILED]
# Usage: execute "Description of task" command_to_run arguments
# ------------------------------------------------------------------
execute() {
    local message="$1"
    shift
    
    # Print the task description without a newline
    echo -n -e "${message}..."
    
    # Run the command, sending ALL output (logs/errors) to a temp file
    # If the command succeeds (exit code 0), print OK
    if "$@" > /tmp/pip_install.log 2>&1; then
        echo -e " ${GREEN}[OK]${NC}"
    else
        # If it fails, print FAILED and show the log so you know why
        echo -e " ${RED}[FAILED]${NC}"
        echo "------------------------------------------------"
        echo "Error Output:"
        cat /tmp/pip_install.log
        echo "------------------------------------------------"
        exit 1
    fi
}

# ------------------------------------------------------------------
# MAIN SCRIPT
# ------------------------------------------------------------------

# Check for Root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Please run as root (sudo ./install_pip.sh)${NC}"
  exit 1
fi

# 1. Disable Manufacturer Service
if systemctl is-active --quiet displayML_tft; then
    execute "Stopping manufacturer service" systemctl stop displayML_tft
    execute "Disabling manufacturer service" systemctl disable displayML_tft
fi

# Header
clear
echo "=========================================="
echo "          PIP KIOSK INSTALLER             "
echo "=========================================="
echo ""

# 1. Update and Install Dependencies
execute "Updating package lists" apt-get update
execute "Installing Kiosk Engine" apt-get install -y chromium-browser unclutter curl x11-xserver-utils sed xdotool fbset openbox xserver-xorg-video-fbdev

# 2. Directory Structure
execute "Creating /etc/pip-kiosk directory" mkdir -p /etc/pip-kiosk
execute "Setting permissions" chmod 755 /etc/pip-kiosk

# 3. X11 Configuration
execute "Configuring FBDEV Driver" bash -c 'cat > /usr/share/X11/xorg.conf.d/99-fbdev.conf <<EOF
Section "Device"
  Identifier "GenericFB"
  Driver "fbdev"
  Option "fbdev" "/dev/fb0"
EndSection
EOF'

execute "Configuring Virtual 4K Canvas" bash -c 'cat > /usr/share/X11/xorg.conf.d/90-virtual-canvas.conf <<EOF
Section "Screen"
  Identifier "Default Screen"
  SubSection "Display"
    Virtual 3840 2160
  EndSubSection
EndSection
EOF'

# 4. Openbox Config (The "Always Fullscreen" Fix)
execute "Configuring Window Manager" bash -c 'mkdir -p /etc/xdg/openbox && cat > /etc/xdg/openbox/rc.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config>
  <applications>
    <application class="*">
      <fullscreen>yes</fullscreen>
    </application>
  </applications>
</openbox_config>
EOF'

# 5. Prompt for PIP ID (Interactive Step)
echo ""
echo -n "Enter the PIP ID for this machine (e.g., 101): "
read PIP_ID_INPUT
PIP_ID_INPUT=$(printf '%s' "$PIP_ID_INPUT" | tr -d '[:space:]')

if [ -z "$PIP_ID_INPUT" ]; then
  echo -e "${RED}[ERROR] PIP ID cannot be empty.${NC}"
  exit 1
fi
echo ""

# 5b. Prompt for stop_ids and scale, then build TARGET_URL
trim_spaces() {
  # Remove all whitespace characters
  printf '%s' "$1" | tr -d '[:space:]'
}

echo -n "Enter stop id(s) (comma-separated, example: 090141,090142): "
read STOP_IDS_INPUT
STOP_IDS_INPUT=$(trim_spaces "$STOP_IDS_INPUT")

if [ -z "$STOP_IDS_INPUT" ]; then
  echo -e "${RED}[ERROR] stop_ids cannot be empty.${NC}"
  exit 1
fi

if ! echo "$STOP_IDS_INPUT" | grep -Eq '^[0-9]+(,[0-9]+)*$'; then
  echo -e "${RED}[ERROR] stop_ids must be digits separated by commas (example: 090141,090142).${NC}"
  exit 1
fi

echo -n "Enter scale factor (range: 0.1 to 3, example: 1.2). Press Enter for 1: "
read SCALE_INPUT
SCALE_INPUT=$(trim_spaces "$SCALE_INPUT")

if [ -z "$SCALE_INPUT" ]; then
  SCALE_INPUT="1"
fi

if ! echo "$SCALE_INPUT" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
  echo -e "${RED}[ERROR] scale must be a number like 1 or 1.2.${NC}"
  exit 1
fi

if ! awk -v v="$SCALE_INPUT" 'BEGIN { exit !(v >= 0.1 && v <= 3) }'; then
  echo -e "${RED}[ERROR] scale must be between 0.1 and 3.${NC}"
  exit 1
fi

echo -n "Enter orientation (landscape/vertical). Press Enter for landscape: "
read ORIENTATION_INPUT
ORIENTATION_INPUT=$(trim_spaces "$ORIENTATION_INPUT" | tr '[:upper:]' '[:lower:]')

if [ -z "$ORIENTATION_INPUT" ]; then
  ORIENTATION_INPUT="landscape"
fi

if ! echo "$ORIENTATION_INPUT" | grep -Eq '^(landscape|vertical)$'; then
  echo -e "${RED}[ERROR] orientation must be landscape or vertical.${NC}"
  exit 1
fi

ROTATION_INPUT=""
if [ "$ORIENTATION_INPUT" = "vertical" ]; then
  echo -n "Enter rotation (cw/ccw). Press Enter for cw: "
  read ROTATION_INPUT
  ROTATION_INPUT=$(trim_spaces "$ROTATION_INPUT" | tr '[:upper:]' '[:lower:]')

  if [ -z "$ROTATION_INPUT" ]; then
    ROTATION_INPUT="cw"
  fi

  if ! echo "$ROTATION_INPUT" | grep -Eq '^(cw|ccw)$'; then
    echo -e "${RED}[ERROR] rotation must be cw or ccw.${NC}"
    exit 1
  fi
fi

# URL-encode commas in stop_ids (optional, but keeps the URL consistent)
STOP_IDS_ENCODED=$(printf '%s' "$STOP_IDS_INPUT" | sed -e 's/,/%2C/g')
QUERY="stop_ids=${STOP_IDS_ENCODED}&pip_id=${PIP_ID_INPUT}&scale=${SCALE_INPUT}"

# Default landscape is omitted from the URL
if [ "$ORIENTATION_INPUT" = "vertical" ]; then
  QUERY="${QUERY}&orientation=vertical&rotation=${ROTATION_INPUT}"
fi

TARGET_URL_INPUT="https://carrismetropolitana.pt/pips?${QUERY}"

escape_sed_replacement() {
  # Escape characters that are special in sed replacement strings
  # Delimiter used below is '|', so we escape that too.
  # IMPORTANT: This must turn '&' into '\&' (literal '&'), otherwise sed expands it to the whole match.
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

SAFE_TARGET_URL=$(escape_sed_replacement "$TARGET_URL_INPUT")

# 6. Config File Setup
if [ -f "pip.conf" ]; then
    execute "Copying configuration template" cp pip.conf /etc/pip-kiosk/pip.conf
    execute "Setting PIP ID to $PIP_ID_INPUT" sed -i "s/^PIP_ID *=.*/PIP_ID=$PIP_ID_INPUT/" /etc/pip-kiosk/pip.conf
  execute "Setting TARGET_URL" sed -i "s|^TARGET_URL *=.*|TARGET_URL=\"$SAFE_TARGET_URL\"|" /etc/pip-kiosk/pip.conf
else
    echo -e "${RED}[ERROR] pip.conf not found in current directory!${NC}"
    exit 1
fi

# 7. Script Installation
execute "Installing main logic script" cp kiosk-manager.sh /usr/local/bin/kiosk-manager.sh
execute "Making script executable" chmod +x /usr/local/bin/kiosk-manager.sh

# 8. Service Installation
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd $REAL_USER | cut -d: -f6)

execute "Copying Systemd service file" cp pip-kiosk.service /etc/systemd/system/pip-kiosk.service
execute "Configuring Service for Root" sed -i "s/User=ubuntu/User=root/" /etc/systemd/system/pip-kiosk.service
execute "Configuring Root Home Path" sed -i "s|/home/ubuntu|/root|" /etc/systemd/system/pip-kiosk.service

# 9. Cron Jobs (Auto-Reboot Every 6 Hours and Browser Forced Refresh Every 20 Minutes)
setup_cron() {
    CRON_JOB="0 */6 * * * /usr/sbin/reboot"
    (crontab -l 2>/dev/null | grep -v "reboot"; echo "$CRON_JOB") | crontab -
}
execute "Scheduling 6-hour auto-reboot" setup_cron

# Refresh the browser every 20 minutes to avoid stale content
add_refresh_cron() {
    REFRESH_JOB="*/20 * * * * DISPLAY=:0 xdotool search --onlyvisible --class chromium key F5"
    (crontab -l 2>/dev/null | grep -v "xdotool search" ; echo "$REFRESH_JOB") | crontab -
}
execute "Scheduling 20-minute forced refresh" add_refresh_cron


# 10. Start Service
execute "Reloading Systemd Daemon" systemctl daemon-reload
execute "Enabling PIP Service" systemctl enable pip-kiosk.service
execute "Starting Kiosk" systemctl restart pip-kiosk.service

echo ""
echo "=========================================="
echo -e "   ${GREEN}INSTALLATION COMPLETE${NC}"
echo "=========================================="
echo "   ID Set To: $PIP_ID_INPUT"
echo "   Status:    Service is running."
echo "   Logs:      If setup failed, check /tmp/pip_install.log"
echo ""