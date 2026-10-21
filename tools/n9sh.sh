#!/bin/bash
# Run one command on the tablet's USB-serial shell (mainline gadget, ttyACM0)
# and print only its output.  usage: tools/n9sh.sh '<command>' [seconds]
# Works best with /etc/n9-plainsh in the ramdisk (non-interactive sh); needs
# BusyBox applets: tools/n9sh.sh '/bin/busybox --install -s /bin' 8
DEV=${N9TTY:-/dev/ttyACM0}
T=${2:-3}
stty -F "$DEV" 115200 raw -echo
{ printf '\necho __N9START__\n%s\necho __N9END__\n' "$1"; sleep "$T"; } \
	| timeout $((T + 2)) socat - "$DEV,ispeed=115200,ospeed=115200,raw,echo=0,crnl" 2>/dev/null \
	| tr -d '\r' | awk '/^__N9END__$/{exit} f{print} /^__N9START__$/{f=1}'
