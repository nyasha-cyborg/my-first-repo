#!/bin/sh
# Charging under mainline (notes/charging.md):
# - bq24190 probe resets the charger, leaving the input limit at 500 mA even on a wall adapter; the vendor
#   stack set it per cable type. Raise it to 2.0 A and keep it there.
# - Lower the input-voltage floor (VINDPM) from 4.36 V to 4.20 V (code 4): the micro-USB cable drops ~0.6 V
#   at 1 A, so 4.36 V throttled input to ~1 A. Measured on the laptop's 3 A USB-C port: +200 -> +423 mA into
#   the battery, no VBUS/gadget drops. Do not go lower without testing VBUS detection.
# - Powered-off charging boots this image with androidboot.mode=charger: keep the load minimal so the
#   battery actually charges (no UI, no modem, lowest CPU clock, backlight off).
D=/sys/class/power_supply/bq24190-charger
C=$D/input_current_limit
LOG=/var/log/n9-charge.log
if grep -q 'androidboot.mode=charger' /proc/cmdline; then
	echo "$(date +%T) charger-mode boot: minimal load" >>$LOG
	rc-service greetd stop >/dev/null 2>&1
	rc-service n9-modem stop >/dev/null 2>&1
	for p in /sys/devices/system/cpu/cpufreq/policy*; do echo powersave >$p/scaling_governor; done
	for b in /sys/class/backlight/*; do echo 0 >$b/brightness; done
fi
(
	while :; do
		if [ -w $C ] && [ "$(cat $C)" -lt 2000000 ]; then
			echo 2000000 >$C && echo "$(date +%T) input limit -> $(cat $C)" >>$LOG
		fi
		if [ -w $D/f_vindpm ] && [ "$(cat $D/f_vindpm)" -ne 4 ]; then
			echo 4 >$D/f_vindpm && echo "$(date +%T) vindpm -> 4.20 V" >>$LOG
		fi
		sleep 10
	done
) >/dev/null 2>&1 &
