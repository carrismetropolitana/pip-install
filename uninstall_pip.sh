#!/bin/bash

# ==============================
# PIP KIOSK UNINSTALL SCRIPT
# ==============================

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ------------------------------------------------------------------
# Helper Function: Run a command quietly, show [OK] or [FAILED]
# ------------------------------------------------------------------
execute() {
    local message="$1"
    shift
    echo -n -e "${message}..."
    if "$@" > /tmp/pip_uninstall.log 2>&1; then
        echo -e " ${GREEN}[OK]${NC}"
    else
        echo -e " ${RED}[FAILED]${NC}"
        echo "------------------------------------------------"
        echo "Error Output:"
        cat /tmp/pip_uninstall.log
        echo "------------------------------------------------"
    fi
}

# ------------------------------------------------------------------
# Check for Root
# ------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Please run as root (sudo ./uninstall_pip.sh)${NC}"
  exit 1
fi

# ------------------------------------------------------------------
# Step 1: Stop the Service
# ------------------------------------------------------------------
execute "Stopping PIP kiosk service" bash -c "systemctl stop pip-kiosk.service 2>/dev/null || true"

# ------------------------------------------------------------------
# Step 2: Disable and Remove the Service
# ------------------------------------------------------------------
execute "Disabling PIP kiosk service" bash -c "systemctl disable pip-kiosk.service 2>/dev/null || true"
execute "Removing systemd service file" rm -f /etc/systemd/system/pip-kiosk.service

# ------------------------------------------------------------------
# Step 3: Remove Installed Scripts
# ------------------------------------------------------------------
execute "Removing kiosk manager script" rm -f /usr/local/bin/kiosk-manager.sh

# ------------------------------------------------------------------
# Step 4: Remove Installed Config Folder
# ------------------------------------------------------------------
execute "Removing /etc/pip-kiosk folder" rm -rf /etc/pip-kiosk

# ------------------------------------------------------------------
# Step 5: Remove Cron Jobs
# ------------------------------------------------------------------
execute "Removing PIP-related cron jobs" bash -c "
    crontab -l 2>/dev/null | grep -v 'pip-kiosk' | grep -v 'xdotool search' | crontab -
"

# ------------------------------------------------------------------
# Step 6: Kill Running Processes (Chromium / lxpanel / unclutter)
# ------------------------------------------------------------------
execute "Killing Chromium browser" bash -c "killall chromium-browser 2>/dev/null || true"
execute "Killing Chromium (legacy)" bash -c "killall chromium 2>/dev/null || true"
execute "Killing lxpanel" bash -c "killall lxpanel 2>/dev/null || true"
execute "Killing unclutter" bash -c "killall unclutter 2>/dev/null || true"

# ------------------------------------------------------------------
# Step 7: Remove Temporary Logs
# ------------------------------------------------------------------
execute "Removing temporary uninstall logs" rm -f /tmp/pip_uninstall.log

# ------------------------------------------------------------------
# Step 8: Remove pip-install Folder
# ------------------------------------------------------------------
execute "Removing pip-install folder" rm -rf "$(dirname "$(realpath "$0")")"

# ------------------------------------------------------------------
# Final Message
# ------------------------------------------------------------------
echo -e "\n=========================================="
echo -e "   ${GREEN}PIP KIOSK UNINSTALL COMPLETE${NC}"
echo "   All files, service, and cron jobs have been removed."
echo "=========================================="
