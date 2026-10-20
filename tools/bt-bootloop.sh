#!/bin/bash
# Boot a BT test image until it leaves a fresh record, then print the
# interesting lines.  Fresh = the record names this build, or (when a trace
# flood pushed the stamp out) its text hash differs from the record that
# was there before we started.
#
# usage: tools/bt-bootloop.sh <N> [attempts]
#   boots ~/Downloads/nexus9/bootimg-build/n9-mainline/n9bt<N>-stripped.img
set -u
N=$1
TRIES=${2:-7}
B=~/Downloads/nexus9/bootimg-build/n9-mainline
HERE=$(dirname "$0")
REC=/tmp/n9build/rec$N.bin

pull() {
	adb root >/dev/null 2>&1
	sleep 3
	timeout 30 adb wait-for-device
	for t in 1 2 3; do
		timeout 25 adb exec-out "dd if=/dev/block/mmcblk0 bs=512 skip=79872 count=256 2>/dev/null" > "$REC"
		[ "$(stat -c %s "$REC")" -ge 32768 ] && return 0
		sleep 3
	done
	return 1
}

# identity of whatever record is on the tablet before this run
if fastboot devices | grep -q .; then
	before="unknown"
else
	timeout 60 adb wait-for-device && pull && before=$(python3 -I "$HERE/record-id.py" "$REC") || before="unknown"
fi
echo "before: $before"

for attempt in $(seq 1 "$TRIES"); do
	if ! fastboot devices | grep -q .; then
		timeout 60 adb wait-for-device || { echo "attempt $attempt: no adb before boot"; exit 1; }
		adb reboot bootloader
		for i in $(seq 1 30); do fastboot devices | grep -q . && break; sleep 1; done
	fi
	fastboot boot "$B/n9bt$N-stripped.img" 2>&1 | tail -1
	sleep 40
	back=0
	for i in $(seq 1 200); do
		adb devices 2>/dev/null | grep -q 'device$' && { back=1; break; }
		sleep 1
	done
	[ $back = 1 ] || { echo "attempt $attempt: tablet did not return (needs power cycle) at $(date +%T)"; exit 2; }
	pull || { echo "attempt $attempt: record read failed"; continue; }
	now=$(python3 -I "$HERE/record-id.py" "$REC")
	build=${now%% *}
	if [ "$build" = "$N" ] || { [ "$build" = "none" ] && [ "$now" != "$before" ]; }; then
		echo "attempt $attempt: fresh record ($now) at $(date +%T)"
		python3 -I "$HERE/read-record.py" "$REC" 5000 2>/dev/null \
			| grep -vE "01 4c fc|04 0e 04 01 4c fc 00" \
			| grep -iE 'record:|n9bt|n9dbg|Bluetooth|BCM' | tail -80
		exit 0
	fi
	echo "attempt $attempt: stale ($now) at $(date +%T)"
	before=$now
done
echo "no fresh record after $TRIES attempts"
exit 3
