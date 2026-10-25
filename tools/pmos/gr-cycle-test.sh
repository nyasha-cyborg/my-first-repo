#!/bin/bash
# Reboot into pmOS N times; ~60 s after each boot run kmscube on the GPU (first GR use) and record whether
# GR init / context construction worked. Tests whatever nouveau.ko is installed in the rootfs.
#   usage: tools/pmos/gr-cycle-test.sh [cycles] [ip]
HERE=$(cd "$(dirname "$0")" && pwd)
N=${1:-6}
IP=${2:-192.168.1.111}
export PMBOOT_IP=$IP
SSH="ssh -o ConnectTimeout=5 -o BatchMode=yes root@$IP"
Q='unset GBM_ALWAYS_SOFTWARE LIBGL_ALWAYS_SOFTWARE; export LD_LIBRARY_PATH=/opt/mesa-n9/lib
timeout 15 kmscube -D /dev/dri/card0 -c 200 >/tmp/kc.log 2>&1; rc=$?
echo "up=$(cut -d. -f1 /proc/uptime)s kmscube_rc=$rc renderer=$(grep -m1 "renderer:" /tmp/kc.log | cut -c1-40) gr_fail=$(dmesg | grep -c "gr: init failed\|failed to construct") privring=$(dmesg | grep -c PRIVRING) oops=$(dmesg | grep -c "Internal error\|Unable to handle")"'
for c in $(seq 1 "$N"); do
	"$HERE/pmboot.sh" "${IMG:-}" "$IP" >/dev/null || { echo "cycle $c: pmOS did not come up"; continue; }
	sleep 60
	r=$(timeout 60 $SSH "$Q" 2>&1 | tail -1)
	echo "cycle $c $(date +%T): $r"
done
