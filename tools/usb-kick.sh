#!/bin/bash
# Software "unplug/replug" of the Nexus 9 on this laptop's USB port 3-7.
#   tools/usb-kick.sh            kick now
#   tools/usb-kick.sh --watch N  watch; kick when no adb/fastboot/gadget is seen for N seconds (default 240)
# Connected-but-stuck: usbreset on the tablet's device node (no root needed, udev ACL).
# Nothing enumerated: power the port off/on via usb3-port7/disable (needs tools/udev/99-n9-usbport.rules installed).
PORT=/sys/bus/usb/devices/3-0:1.0/usb3-port7/disable
seen() { lsusb | grep -qiE "18d1:|0955:|0525:a4a7"; }
kick() {
	local dev; dev=$(lsusb | grep -iE "18d1:|0955:|0525:a4a7" | head -1 | awk '{print $2"/"substr($4,1,3)}')
	if [ -n "$dev" ]; then echo "$(date +%T) usbreset /dev/bus/usb/$dev"; usbreset "/dev/bus/usb/$dev"; return; fi
	if [ -w "$PORT" ]; then echo "$(date +%T) port 3-7 power cycle"; echo 1 > "$PORT"; sleep 3; echo 0 > "$PORT"
	else echo "$(date +%T) cannot power-cycle port 3-7: install tools/udev/99-n9-usbport.rules (see header)"; return 1; fi
}
if [ "${1:-}" = --watch ]; then
	limit=${2:-240}; quiet=0
	while :; do if seen; then quiet=0; else quiet=$((quiet+5)); fi
		[ $quiet -ge "$limit" ] && { kick; quiet=0; }; sleep 5; done
else kick; fi
