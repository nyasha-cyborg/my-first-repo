#!/bin/bash
# Reboot the tablet into the pmOS boot image (fastboot boot, nothing flashed) and wait until it answers.
#   usage: tools/pmos/pmboot.sh [image] [ip]
# Works from pmOS (SSH, or the USB serial console when WiFi is down), Android (adb) or fastboot. hboot
# ignores about half of the "fastboot boot" requests and starts Android instead: then it retries.
# pmOS counts as up when SSH or the serial console (g_serial 0525:a4a7, tools/n9sh.sh) answers.
HERE=$(cd "$(dirname "$0")" && pwd)
IMG=${1:-}; IMG=${IMG:-$HOME/Downloads/nexus9/bootimg-build/n9-mainline/n9pmos-boot-stripped.img}
IP=${2:-192.168.1.109}
SSH="ssh -o ConnectTimeout=5 -o BatchMode=yes root@$IP"
say() { echo "pmboot $(date +%T): $*"; }
serial() { lsusb | grep -q 0525:a4a7 && timeout 20 "$HERE/../n9sh.sh" "$1" "${2:-8}" 2>/dev/null; }

to_bootloader() {
	fastboot devices | grep -q . && return 0
	# pmOS: skip the driver shutdown path (it has hung the tablet for minutes): set the PMC reboot-mode
	# "bootloader" bit (SCRATCH0 bit 30, as reboot-mode does) and reset at once via SysRq
	if ! timeout 15 $SSH 'sync; python3 -c "
import mmap,os,struct
f=os.open(\"/dev/mem\",os.O_RDWR|os.O_SYNC); m=mmap.mmap(f,0x1000,mmap.MAP_SHARED,mmap.PROT_READ|mmap.PROT_WRITE,offset=0x7000e000)
v=struct.unpack(\"<I\",m[0x450:0x454])[0]; m[0x450:0x454]=struct.pack(\"<I\",v|(1<<30))
" && echo b > /proc/sysrq-trigger' >/dev/null 2>&1; then
		serial 'reboot bootloader' 3 >/dev/null || adb reboot bootloader >/dev/null 2>&1
	fi
	# a hung shutdown is reset by the watchdog (heartbeat 180 s), so wait up to ~5 min
	for i in $(seq 1 150); do
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
		timeout 10 $SSH 'uname -r' 2>/dev/null && { say "pmOS up (ssh)"; exit 0; }
		serial 'uname -r' 6 | grep -q htc-flounder && { say "pmOS up (serial, no ssh)"; exit 0; }
		adb devices 2>/dev/null | grep -q 'device$' && { say "Android came up instead"; break; }
		sleep 3
	done
done
say "pmOS did not come up"
exit 1
