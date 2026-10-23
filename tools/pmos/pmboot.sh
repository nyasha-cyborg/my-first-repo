#!/bin/bash
# Reboot the tablet into the pmOS boot image (fastboot boot, nothing flashed) and wait for SSH.
#   usage: tools/pmos/pmboot.sh [image] [ip]
# Works from pmOS (ssh "reboot bootloader"), Android (adb) or fastboot. hboot ignores about half of the
# "fastboot boot" requests and starts Android instead: then it goes back to the bootloader and retries.
IMG=${1:-}; IMG=${IMG:-$HOME/Downloads/nexus9/bootimg-build/n9-mainline/n9pmos-boot-stripped.img}
IP=${2:-192.168.1.109}
SSH="ssh -o ConnectTimeout=5 -o BatchMode=yes root@$IP"
say() { echo "pmboot $(date +%T): $*"; }

to_bootloader() {
	fastboot devices | grep -q . && return 0
	$SSH 'reboot bootloader' >/dev/null 2>&1 || adb reboot bootloader >/dev/null 2>&1
	for i in $(seq 1 90); do
		fastboot devices | grep -q . && return 0
		adb devices | grep -q 'device$' && adb reboot bootloader >/dev/null 2>&1
		sleep 2
	done
	return 1
}

for try in 1 2 3 4 5 6; do
	to_bootloader || { say "no fastboot device"; exit 1; }
	say "try $try: fastboot boot $(basename "$IMG")"
	fastboot boot "$IMG" >/dev/null 2>&1
	for i in $(seq 1 60); do
		$SSH 'uname -r' 2>/dev/null && { say "pmOS up"; exit 0; }
		adb devices 2>/dev/null | grep -q 'device$' && { say "Android came up instead"; break; }
		sleep 3
	done
done
say "pmOS did not come up"
exit 1
