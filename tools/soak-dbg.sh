#!/bin/bash
# Boot a debug image N times and judge each boot.
#   usage: tools/soak-dbg.sh <image> [cycles]
# Per boot: gadget appears, serial shell answers, PMIC/i2c interrupt counters
# stay quiet over 4 s, an RTC alarm 5 s ahead fires (PMIC irq delivered).
# Output: one line per cycle in /tmp/n9build/soak.log.
IMG=$1
N=${2:-10}
HERE=$(dirname "$0")
LOG=/tmp/n9build/soak.log
cnt() { "$HERE/n9sh.sh" "$(cat <<'EOC'
grep -E ' palmas$| 7000d000.i2c$|rtc$' /proc/interrupts | awk '{printf "%s ", $2}'
EOC
)" 6 | tail -1; }
for k in $(seq 1 "$N"); do
	t0=$(date +%T)
	for i in $(seq 1 100); do adb devices | grep -q 'device$' && break; sleep 3; done
	adb reboot bootloader 2>/dev/null
	for i in $(seq 1 30); do fastboot devices | grep -q . && break; sleep 1; done
	fastboot boot "$IMG" >/dev/null 2>&1
	up=0
	for i in $(seq 1 60); do lsusb | grep -q 0525:a4a7 && { up=$i; break; }; sleep 1; done
	if [ $up = 0 ]; then echo "$k $t0 NO-GADGET" >> $LOG; continue; fi
	sleep 12
	"$HERE/n9sh.sh" '/bin/busybox --install -s /bin; mount -t debugfs none /sys/kernel/debug 2>/dev/null' 9 >/dev/null
	# the first command (busybox --install) can take longer than its window:
	# retry the readiness probe before declaring the shell dead
	rel=0
	for try in 1 2 3 4 5 6; do
		rel=$("$HERE/n9sh.sh" 'uname -r' 4 | grep -c htc-flounder)
		[ "$rel" != 0 ] && break
	done
	if [ "$rel" = 0 ]; then echo "$k $t0 gadget@${up}s SHELL-DEAD" >> $LOG; else
		a=$(cnt); sleep 4; b=$(cnt)
		"$HERE/n9sh.sh" 'echo 0 > /sys/class/rtc/rtc0/wakealarm; echo $(( $(date +%s)+5 )) > /sys/class/rtc/rtc0/wakealarm' 4 >/dev/null
		sleep 9; c=$(cnt)
		echo "$k $t0 gadget@${up}s shell-ok irq[a]=$a irq[b]=$b irq[after-alarm]=$c" >> $LOG
		"$HERE/n9sh.sh" 'reboot -f' 2 >/dev/null
	fi
	# wait for the board to come back (watchdog resets a dead one)
	back=0
	for i in $(seq 1 100); do adb devices | grep -q 'device$' && { back=1; break; }; sleep 3; done
	[ $back = 1 ] || echo "$k $t0 DID-NOT-RETURN (needs power cycle)" >> $LOG
done
echo "soak done" >> $LOG
