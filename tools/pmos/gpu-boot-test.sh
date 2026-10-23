#!/bin/bash
# Reboot into pmOS N times; ~150 s after each boot record whether it is still alive, GR init, kernel oopses,
# the EMC (DRAM) clock + whether actmon scales it, the GPU clock, phoc, PMIC I2C errors and the Palmas
# SMPS45 (vdd-gpu) registers. Needs /root/i2cread on the tablet. IMG= selects the boot image.
#   usage: [IMG=path] tools/pmos/gpu-boot-test.sh [cycles] [ip]
HERE=$(dirname "$0")
N=${1:-4}
IP=${2:-192.168.1.109}
SSH="ssh -o ConnectTimeout=5 -o BatchMode=yes root@$IP"
for c in $(seq 1 "$N"); do
	"$HERE/pmboot.sh" "${IMG:-}" "$IP" >/dev/null || { echo "cycle $c: pmOS did not come up"; continue; }
	sleep 150
	r=$(timeout 30 $SSH 'D=/sys/class/devfreq/57000000.gpu
		gr=ok; dmesg | grep -q "gr: init failed" && gr=FAIL
		oops=$(dmesg | grep -c "Internal error\|Unable to handle")
		emc=$(awk "\$1==\"emc\"{print \$4/1000000}" /sys/kernel/debug/clk/clk_summary | head -1)
		act=$([ -e /sys/class/devfreq/6000c800.actmon ] && echo on || echo off)
		ph=$(pgrep phoc >/dev/null && echo up || echo down)
		n121=$(dmesg | grep -c -- "-121")
		echo "up=$(cut -d. -f1 /proc/uptime)s gr=$gr oops=$oops emc=${emc}MHz actmon=$act phoc=$ph gpu=$(($(cat $D/cur_freq)/1000000))MHz -121=$n121 smps45: $(/root/i2cread 4 58 28 4 | tr "\n" " ")"' 2>&1)
	[ -n "$r" ] || r="no answer (hung?)"
	echo "cycle $c $(date +%T): $r"
done
