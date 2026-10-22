#!/bin/bash
# Stream the pmOS overlay tarball into the rootfs mounted at /mnt/pmos on the tablet, over WiFi.
# The tablet listens (busybox nc -l) and the host connects out, so the host firewall does not matter.
# Usage: tools/pmos/push-overlay.sh [overlay.tgz]   (installer image running, install-rootfs.sh done)
set -eu
T=$(cd "$(dirname "$0")/.." && pwd)
F=${1:-/tmp/n9build/pmos/overlay.tgz}
IP=$("$T/n9sh.sh" 'ip -o -4 addr show wlan0' 10 | grep -o 'inet [0-9.]*' | cut -d' ' -f2 | head -1)
[ -n "$IP" ] || { echo "tablet has no WiFi address" >&2; exit 1; }
"$T/n9sh.sh" 'rm -f /tmp/overlay.done; (nc -l -p 5000 | tar -xzf - -C /mnt/pmos; echo "rc=$?" > /tmp/overlay.done) </dev/null >/dev/null 2>&1 & sleep 1; echo listening' 10 | tail -1
socat -u "FILE:$F" "TCP:$IP:5000"
for i in $(seq 1 30); do
	R=$("$T/n9sh.sh" 'cat /tmp/overlay.done 2>/dev/null' 8 | grep -o 'rc=[0-9]*' || true)
	[ -n "$R" ] && { echo "overlay extracted on $IP: $R"; [ "$R" = rc=0 ]; exit; }
	sleep 2
done
echo "no completion marker from the tablet" >&2; exit 1
