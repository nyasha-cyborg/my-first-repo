#!/bin/bash
# Reboot into pmOS until a boot shows "gr: init failed", record that boot's PMIC state, then load a test
# nouveau.ko on the same boot and check whether GR comes up (a plain reload never recovered such a boot).
#   usage: tools/pmos/gr-hunt.sh <test-nouveau.ko> [max-boots] [ip]
# Needs /root/i2cread on the tablet (tools/miniroot/i2cread.c).
HERE=$(dirname "$0")
KO=$1
MAX=${2:-8}
IP=${3:-192.168.1.109}
SSH="ssh -o ConnectTimeout=5 -o BatchMode=yes root@$IP"
state='n121=$(dmesg | grep -c -- "-121"); t121=$(dmesg | grep -m1 -- "-121" | cut -d] -f1 | tr -d "[ ")
	echo "gr=$(dmesg | grep -q "gr: init failed" && echo FAIL || echo ok) privring=$(dmesg | grep -c PRIVRING) -121=$n121@${t121}s eremoteio=$(dmesg | grep -c EREMOTEIO) smps45: $(/root/i2cread 4 58 28 4 | tr "\n" " ")"'
for b in $(seq 1 "$MAX"); do
	"$HERE/pmboot.sh" "" "$IP" >/dev/null || { echo "boot $b: pmOS did not come up"; continue; }
	sleep 75
	s=$($SSH "$state" 2>&1)
	echo "boot $b $(date +%T): $s"
	case "$s" in *gr=FAIL*) ;; *) continue;; esac
	scp -q "$KO" root@"$IP":/root/test-nouveau.ko || exit 1
	$SSH 'rc-service greetd stop >/dev/null 2>&1; sleep 2; dmesg > /root/gr-fail-dmesg.txt; rmmod nouveau || exit 1; dmesg -C
		insmod /root/test-nouveau.ko config=NvGk20aDvfs=0 || exit 1; sleep 2
		D=/sys/class/devfreq/57000000.gpu; echo 612000000 > $D/max_freq; echo 612000000 > $D/min_freq
		LD_LIBRARY_PATH=/opt/mesa-n9/lib timeout 10 kmscube -D /dev/dri/card0 -c 200 >/tmp/kc.log 2>&1
		echo "test module: kmscube rc=$? gr=$(dmesg | grep -q "gr: init failed" && echo FAIL || echo ok) privring=$(dmesg | grep -c PRIVRING)"
		dmesg | grep -E "nouveau|gr:" | tail -5' 2>&1
	exit 0
done
echo "no failing boot in $MAX boots"
