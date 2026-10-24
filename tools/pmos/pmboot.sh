#!/bin/bash
# Reboot the tablet into the pmOS boot image (fastboot boot, nothing flashed) and wait until it answers.
#   usage: tools/pmos/pmboot.sh [image] [ip]
# Works from pmOS (SSH, or the USB serial console when WiFi is down), Android (adb) or fastboot. hboot
# ignores about half of the "fastboot boot" requests and starts Android instead: then it retries.
# pmOS counts as up when SSH or the serial console (g_serial 0525:a4a7, tools/n9sh.sh) answers.
#
# Every attempt is bounded and every outcome is logged to $PMBOOT_LOG (default /tmp/pmboot.log):
#   pmos-ssh / pmos-serial   success
#   ignored                  hboot stayed in fastboot or fell back to Android without ever running the image
#   watchdog-reset           the image booted (gadget appeared), hung, and tegra_wdt reset it to Android
#   hang                     the image booted (gadget appeared) but userspace stayed silent through the wait
#   no-boot                  no fastboot, no Android, no gadget: upload never ran or the board is powered off
# Environment: PMBOOT_TOTAL (default 900 s), PMBOOT_ATTEMPT (default 210 s), PMBOOT_TRIES (default 6).
# Resolve this file even when sourced: soak-boot.sh imports the helpers below and must not
# run the main flow. Set PMBOOT_SOURCE_ONLY=1 (or source it from another script) to import.
PMBOOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
IP=${PMBOOT_IP:-192.168.1.109}
SSH=${PMBOOT_SSH:-"ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no root@$IP"}
LOG=${PMBOOT_LOG:-/tmp/pmboot.log}
DEADLINE=${DEADLINE:-0}
say() { local m; m="pmboot $(date +%T): $*"; echo "$m"; echo "$m" >>"$LOG"; }
usb() { timeout 5 lsusb 2>/dev/null; }
has_fastboot() { timeout 10 fastboot devices 2>/dev/null | grep -q .; }
has_android() { usb | grep -q '18d1:4ee7' || timeout 5 adb devices 2>/dev/null | grep -q 'device$'; }
has_gadget() { usb | grep -q '0525:a4a7'; }
serial() { has_gadget && timeout 20 "$PMBOOT_DIR/../n9sh.sh" "$1" "${2:-8}" 2>/dev/null; }
ssh_up() { timeout 12 $SSH 'uname -r' 2>/dev/null | grep -q htc-flounder; }
serial_up() { serial 'uname -r' 6 | grep -q htc-flounder; }
time_left() { echo $((DEADLINE - SECONDS)); }

to_bootloader() {
	has_fastboot && return 0
	# pmOS: skip the driver shutdown path (it has hung the tablet for minutes): set the PMC reboot-mode
	# "bootloader" bit (SCRATCH0 bit 30, as reboot-mode does) and reset at once via SysRq
	if timeout 15 $SSH 'sync; python3 -c "
import mmap,os,struct
f=os.open(\"/dev/mem\",os.O_RDWR|os.O_SYNC); m=mmap.mmap(f,0x1000,mmap.MAP_SHARED,mmap.PROT_READ|mmap.PROT_WRITE,offset=0x7000e000)
v=struct.unpack(\"<I\",m[0x450:0x454])[0]; m[0x450:0x454]=struct.pack(\"<I\",v|(1<<30))
" && echo b > /proc/sysrq-trigger' >/dev/null 2>&1; then
		say "pmOS reachable: rebooted to bootloader via PMC/SysRq"
	else
		serial 'reboot bootloader' 3 >/dev/null || adb reboot bootloader >/dev/null 2>&1
	fi
	# a hung shutdown is reset by the watchdog (heartbeat 180 s), so allow it to expire, bounded by DEADLINE
	while [ $SECONDS -lt $DEADLINE ]; do
		has_fastboot && { say "fastboot up"; return 0; }
		has_android && adb reboot bootloader >/dev/null 2>&1
		sleep 2
	done
	return 1
}

# One fastboot boot + bounded wait. Echoes the outcome; returns 0 for success, 10 for serial-only success,
# 2 ignored/no-upload, 3 watchdog reset after a hang, 4 hang, 5 no-boot.
boot_try() {
	local n=$1 start seen=0 last="" state serial_at=0
	say "try $n: fastboot boot $(basename "$IMG")"
	local out
	out=$(timeout 120 fastboot boot "$IMG" 2>&1); local rc=$?
	printf '%s\n' "$out" | tail -4 >>"$LOG"
	if [ $rc -ne 0 ] || ! printf '%s' "$out" | grep -qiE 'Booting|OKAY'; then
		say "try $n: fastboot boot failed (rc=$rc): $(printf '%s' "$out" | tail -1)"
		return 2
	fi
	start=$SECONDS
	while [ $((SECONDS - start)) -lt $ATTEMPT ] && [ $SECONDS -lt $DEADLINE ]; do
		if has_gadget; then state=gadget
		elif has_fastboot; then state=fastboot
		elif has_android; then state=android
		else state=none; fi
		[ "$state" != "$last" ] && { say "try $n: usb $state ($((SECONDS-start))s)"; last=$state; }
		case $state in
		gadget)
			[ $seen = 0 ] && seen=$SECONDS
			ssh_up && { say "pmOS up (ssh)"; return 0; }
			# WiFi is the flaky path; once boot is past ~35 s try the serial shell too
			if [ $((SECONDS - seen)) -ge 25 ] && [ $((SECONDS - serial_at)) -ge 20 ]; then
				serial_at=$SECONDS
				serial_up && { say "pmOS up (serial, no ssh)"; return 10; }
			fi
			;;
		fastboot)
			# still in fastboot 20 s after "Booting OKAY": the upload was accepted but never run
			[ $((SECONDS - start)) -ge 20 ] && { say "try $n: still in fastboot, image ignored"; return 2; }
			;;
		android)
			if [ $seen = 0 ]; then say "try $n: Android came up instead (hboot ignored image)"; return 2; fi
			say "try $n: Android after gadget -> watchdog reset a hung boot"
			return 3
			;;
		none)
			# no USB at all for a while after the upload: hard hang or power loss
			[ $((SECONDS - start)) -ge 45 ] && { say "try $n: no USB 45 s after upload"; return 5; }
			;;
		esac
		sleep 2
	done
	[ $seen != 0 ] && { say "try $n: gadget enumerated but userspace silent for ${ATTEMPT}s (hang)"; return 4; }
	say "try $n: no pmOS/Android/fastboot within ${ATTEMPT}s (no boot)"
	return 5
}

pmboot_main() {
	IMG=${1:-}; IMG=${IMG:-$HOME/Downloads/nexus9/bootimg-build/n9-mainline/n9pmos-boot-stripped.img}
	IP=${2:-$IP}
	SSH="ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no root@$IP"
	TOTAL=${PMBOOT_TOTAL:-900}
	ATTEMPT=${PMBOOT_ATTEMPT:-210}	# > the 180 s tegra_wdt heartbeat, so a hang is seen as a watchdog reset
	MAXTRIES=${PMBOOT_TRIES:-6}
	DEADLINE=$((SECONDS + TOTAL))

	say "image $(basename "$IMG"), total budget ${TOTAL}s"
	[ -f "$IMG" ] || { say "FAILED: no such image: $IMG"; return 2; }
	if [ "$(head -c 8 "$IMG")" != "ANDROID!" ]; then
		# hboot accepts a wrapper-wrapped upload and silently does nothing (notes/usb-debug.md).
		say "WARNING: $IMG is not wrapper-stripped; hboot will ignore it (fix: tail -c +257 IMG > out.img)"
	fi

	local tries=0 rc
	while [ $tries -lt $MAXTRIES ] && [ $SECONDS -lt $DEADLINE ]; do
		tries=$((tries + 1))
		if ! to_bootloader; then
			say "try $tries: no fastboot device and tablet unreachable (power/battery or hard hang); $(time_left)s left"
			sleep 15
			continue
		fi
		boot_try $tries; rc=$?
		case $rc in
		0)  say "OUTCOME=pmos-ssh (kernel $(timeout 10 $SSH 'uname -r' 2>/dev/null))"; return 0;;
		10) say "OUTCOME=pmos-serial (ssh down: check wlan0/SDIO)"; return 0;;
		2)  say "attempt $tries: image ignored or upload failed; retrying";;
		3)  say "attempt $tries: boot hung, watchdog reset it; retrying";;
		4)  say "attempt $tries: boot hang; waiting for the watchdog"; sleep 10;;
		5)  say "attempt $tries: no boot/no USB (power problem?); retrying"; sleep 15;;
		*)  say "attempt $tries: unexpected rc=$rc";;
		esac
	done
	say "OUTCOME=failed: pmOS did not come up in ${TOTAL}s ($tries attempts, see $LOG)"
	return 1
}

# Only execute when run directly; sourcing imports the helpers for soak-boot.sh.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	pmboot_main "$@"
fi
