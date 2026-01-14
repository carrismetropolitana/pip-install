#!/bin/bash

# Load Config
source "/etc/pip-kiosk/pip.conf"

# 1. CLEANUP
# Kill any existing instance of lxpanel (the Raspberry Pi panel/taskbar)
# This is useful when running kiosk mode to prevent UI elements from showing.
killall lxpanel 2>/dev/null

# 2. SETUP

# Tell all GUI-related commands to target the main X11 display (screen 0)
export DISPLAY=:0

# Ensure X11 authentication works for the current user
# Many GUI tools require access to .Xauthority to control the display
export XAUTHORITY="/root/.Xauthority"

# HARDWARE SYNC (Forces 4K canvas so 1080p doesn't sit in corner)
fbset -fb /dev/fb0 -g 3840 2160 3840 2160 32

# START WINDOW MANAGER (Forces Fullscreen)
openbox --config-file /etc/xdg/openbox/rc.xml &

# Disable screen blanking (prevents the screen from turning black due to inactivity)
xset s noblank

# Disable the screensaver entirely
xset s off

# Disable DPMS (Energy Star) features: no standby, suspend, or off modes for the display
xset -dpms

# Kill any existing unclutter process so we can start a fresh one
# unclutter hides the cursor after inactivity (common for kiosk mode)
killall unclutter 2>/dev/null

# Start unclutter with:
# - idle 0.1 = hide cursor after 0.1s of no input
# - root = apply to the full screen root window
unclutter -idle 0.1 -root &

# ---------------------------------------------------------
# 2. MONITORING (Active)
# ---------------------------------------------------------
monitor_heartbeat() {
    while true; do
        if [ ! -z "$MONITOR_URL" ] && [ ! -z "$PIP_ID" ]; then
            # -s: Silent
            # --max-time 5: Don't wait more than 5s if server is down
            # -o /dev/null: Throw away the response body
            curl -s --max-time 5 -o /dev/null "${MONITOR_URL}?status=up&msg=OK&pip_id=${PIP_ID}"
        fi
        sleep "$PING_INTERVAL"
    done
}

# Start the function in the background (&) and save its Process ID ($!)
monitor_heartbeat &
MONITOR_PID=$!

# ---------------------------------------------------------
# 3. BROWSER LAUNCHER
# ---------------------------------------------------------

# FORCE KILL: Ensure no previous instances are running
killall chromium-browser 2>/dev/null
killall chromium 2>/dev/null

while true; do
    # Kill navbar again to be safe
    killall lxpanel 2>/dev/null

    # Crash cleanup
    if [ -f ~/.config/chromium/Default/Preferences ]; then
        sed -i 's/"exited_cleanly":false/"exited_cleanly":true/' ~/.config/chromium/Default/Preferences
        sed -i 's/"exit_type":"Crashed"/"exit_type":"Normal"/' ~/.config/chromium/Default/Preferences
    fi

    rm -rf /root/.config/chromium/Default/Service\ Worker/Database/*

    # LAUNCHER
   chromium-browser \
      --app="$TARGET_URL" \
      --kiosk \
      --no-sandbox \
      --test-type \
      --window-position=0,0 \
      --window-size=3840,2160 \
      --force-device-scale-factor=2.0 \
      --disable-gpu \
      --disable-software-rasterizer \
      --use-gl=swiftshader \
      --incognito \
      --noerrdialogs \
      --disable-infobars

    echo "Chromium crashed. Restarting in 2s..."
    sleep 2
done

# If the script ever exits (e.g. system stop), kill the monitor background job
kill $MONITOR_PID