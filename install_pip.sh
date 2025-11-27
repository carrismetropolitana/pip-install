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

# Header
clear
echo "=========================================="
echo "          PIP KIOSK INSTALLER             "
echo "=========================================="
echo ""

# 1. Update and Install Dependencies
execute "Updating package lists" apt-get update
execute "Installing Chromium & Tools" apt-get install -y chromium-browser unclutter curl x11-xserver-utils sed xdotool

# 2. Directory Structure
execute "Creating /etc/pip-kiosk directory" mkdir -p /etc/pip-kiosk
execute "Setting permissions" chmod 755 /etc/pip-kiosk

# 3. Prompt for PIP ID (Interactive Step)
echo ""
echo -n "Enter the PIP ID for this machine (e.g., 101): "
read PIP_ID_INPUT
echo ""

# 4. Config File Setup
if [ -f "pip.conf" ]; then
    execute "Copying configuration template" cp pip.conf /etc/pip-kiosk/pip.conf
    execute "Setting PIP ID to $PIP_ID_INPUT" sed -i "s/^PIP_ID *=.*/PIP_ID=$PIP_ID_INPUT/" /etc/pip-kiosk/pip.conf
else
    echo -e "${RED}[ERROR] pip.conf not found in current directory!${NC}"
    exit 1
fi

# 5. Script Installation
execute "Installing main logic script" cp kiosk-manager.sh /usr/local/bin/kiosk-manager.sh
execute "Making script executable" chmod +x /usr/local/bin/kiosk-manager.sh

# 6. Service Installation
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd $REAL_USER | cut -d: -f6)

execute "Copying Systemd service file" cp pip-kiosk.service /etc/systemd/system/pip-kiosk.service
execute "Configuring Service User ($REAL_USER)" sed -i "s/User=ubuntu/User=$REAL_USER/" /etc/systemd/system/pip-kiosk.service
execute "Configuring User Home Path" sed -i "s|/home/ubuntu|$USER_HOME|" /etc/systemd/system/pip-kiosk.service

# 7. Cron Jobs (Auto-Reboot Every 6 Hours and Browser Forced Refresh Every 20 Minutes)
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


# 8. Start Service
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