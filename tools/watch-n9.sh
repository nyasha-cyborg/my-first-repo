#!/bin/sh
# Watch the Nexus 9's USB state and serial gadget, and log every transition
# with a timestamp. Meant to run in the background while the tablet is being
# rebooted unattended, so a wedge or a silent boot fallback is visible after
# the fact.
#
# Usage: tools/watch-n9.sh [/tmp/n9-watch.log]
#
# States logged:
#   fastboot   18d1:4ee0  hboot
#   android    18d1:4ee7  stock Android
#   gadget     0525:a4a7  our kernel, g_serial
#   none                  no USB at all (likely a hard hang)
#
# Whenever the gadget appears, 5 seconds of serial output are captured to
# <log>.serial so kernel messages can be read without holding the port.

LOG=${1:-/tmp/n9-watch.log}
SER="$LOG.serial"
last=""

logline() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

logline "watcher started"

while :; do
    state="none"
    if lsusb | grep -q "0525:a4a7"; then
        state="gadget"
    elif lsusb | grep -q "18d1:4ee0"; then
        state="fastboot"
    elif lsusb | grep -q "18d1:4ee7"; then
        state="android"
    fi

    if [ "$state" != "$last" ]; then
        dev=$(lsusb | grep -E "0525:a4a7|18d1:4ee" | sed 's/.*ID //' | head -1)
        logline "$state ${dev:-}"
        if [ "$state" = "gadget" ] && [ -r /dev/ttyACM0 ]; then
            timeout 5 cat /dev/ttyACM0 >> "$SER" 2>/dev/null
        fi
        last="$state"
    fi
    sleep 2
done
