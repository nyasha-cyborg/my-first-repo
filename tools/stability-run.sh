#!/bin/sh
# Drive the tablet through a list of boot images and measure how long each
# one survives with a working serial shell.
#
# For each image: wait for Android, fastboot boot, wait for the gadget, then
# poll the shell every 15 s for up to 10 minutes. If the shell answers, the
# image is stable; if it stops answering, note the elapsed time, wait for the
# tablet to come back (watchdog or a human power cycle), and move on.
#
# Usage: tools/stability-run.sh <image> [<image> ...]
# Images must be wrapper-stripped (tail -c +257).

PY=/tmp/ser/bin/python
SH=/tmp/n9sh.py
LOG=/tmp/stability.log

say() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG"; }

alive() {
    lsusb | grep -qi "0525:a4a7"
}

shell_ok() {
    timeout 12 $PY $SH 'echo PROBE_OK' 2>/dev/null | grep -q PROBE_OK
}

wait_android() {
    i=0
    while [ $i -lt 60 ]; do
        timeout 4 adb devices 2>/dev/null | grep -q "HT4C3WV00112" && return 0
        sleep 5; i=$((i+1))
    done
    return 1
}

for img in "$@"; do
    say "=== $img"
    wait_android || { say "no android; waiting"; sleep 60; wait_android || { say "giving up on $img"; continue; }; }

    adb reboot bootloader >/dev/null 2>&1
    i=0
    while [ $i -lt 30 ]; do
        fastboot devices 2>/dev/null | grep -q fastboot && break
        sleep 1; i=$((i+1))
    done
    fastboot boot "$img" >/dev/null 2>&1
    say "booted, waiting for gadget"

    i=0; up=0
    while [ $i -lt 30 ]; do
        alive && { up=1; break; }
        sleep 2; i=$((i+1))
    done
    [ $up -eq 1 ] || { say "no gadget (bootloader ignored it?)"; sleep 30; continue; }

    t=0
    while [ $t -lt 600 ]; do
        if ! alive; then say "USB dropped after ${t}s"; break; fi
        if ! shell_ok; then say "shell unresponsive after ${t}s"; break; fi
        sleep 15; t=$((t+15))
    done
    [ $t -ge 600 ] && say "STABLE for 10 min: $img"
done
say "done"
