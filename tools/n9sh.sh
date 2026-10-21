#!/bin/bash
# Run one command on the tablet's USB-serial shell (mainline gadget, ttyACM0)
# and print its output.  usage: tools/n9sh.sh '<command>' [seconds-to-wait]
# BusyBox applets must exist first: tools/n9sh.sh '/bin/busybox --install -s /bin'
DEV=${N9TTY:-/dev/ttyACM0}
T=${2:-3}
stty -F "$DEV" 115200 raw -echo
{ printf '\n%s\necho __N9END__\n' "$1"; sleep "$T"; } \
	| timeout $((T + 2)) socat - "$DEV,ispeed=115200,ospeed=115200,raw,echo=0,crnl" 2>/dev/null \
	| tr -d '\r' | sed -n '/__N9END__/q;p' | sed '1,/^\/ #.*'"$(printf '%s' "$1" | head -c 20 | sed 's/[][\.*^$/]/\\&/g')"'/d' 
