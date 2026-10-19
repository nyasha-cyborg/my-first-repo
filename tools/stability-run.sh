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
PROBE_LOG=/tmp/n9-probe.log
: > "$PROBE_LOG"

say() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG"; }

alive() {
    lsusb | grep -qi "0525:a4a7"
}

shell_ok() {
    # The gadget keeps stale line settings across reboots; without raw mode the
    # probe turns into an echo/"Permission denied" loop and reads as a stall.
    [ -c /dev/ttyACM0 ] && stty -F /dev/ttyACM0 115200 raw -echo 2>/dev/null
    out=$(timeout 12 $PY $SH 'echo PROBE_OK' 2>/dev/null)
    [ -n "$out" ] && printf '%s\n' "$out" >> "$PROBE_LOG"
    printf '%s' "$out" | grep -q PROBE_OK
}

# Leave a booted test image and come back to stock Android. The serial shell of
# our ramdisk has reboot -f; adb is not running in it.
reboot_android() {
    if timeout 4 adb devices 2>/dev/null | grep -q "HT4C3WV00112"; then
        adb reboot >/dev/null 2>&1
    elif [ -c /dev/ttyACM0 ]; then
        stty -F /dev/ttyACM0 115200 raw -echo 2>/dev/null
        # The test ramdisks may not have applet symlinks; call busybox itself.
        timeout 8 $PY $SH '/bin/busybox reboot -f; reboot -f' >/dev/null 2>&1
    fi
}

# Refuse to run at low charge: a flat pack both confounds stall results and
# makes repeated boot cycles risky. Override with N9_MIN_CAP=<percent>.
MIN_CAP=${N9_MIN_CAP:-40}

battery_ok() {
    cap=$(timeout 8 adb shell cat /sys/class/power_supply/battery/capacity 2>/dev/null | tr -d '\r')
    [ -n "$cap" ] && [ "$cap" -ge "$MIN_CAP" ] 2>/dev/null
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
    if ! wait_android; then
        say "not in android; rebooting to it"
        reboot_android
        sleep 10
        wait_android || { say "no android; giving up on $img"; continue; }
    fi

    if ! battery_ok; then
        say "battery below ${MIN_CAP}% (or unreadable) - charge first, stopping"
        exit 1
    fi

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
        alive && { up=1; say "gadget after $((i*2))s"; break; }
        sleep 2; i=$((i+1))
    done
    [ $up -eq 1 ] || { say "no gadget (bootloader ignored it?)"; sleep 30; continue; }

    sleep 5                     # let init reach the shell / settle the tty
    t=0; fails=0
    while [ $t -lt 600 ]; do
        if ! alive; then say "USB dropped after ${t}s"; break; fi
        if shell_ok; then
            fails=0
        else
            # one lost probe is not a stall: the gadget drops bytes while a
            # module loads; require two consecutive failures.
            fails=$((fails+1))
            if [ $fails -ge 2 ]; then
                say "shell unresponsive after ${t}s"
                say "serial capture (last lines):"
                sed 's/^/  | /' "$PROBE_LOG" | tail -40 | tee -a "$LOG"
                break
            fi
        fi
        sleep 15; t=$((t+15))
    done
    [ $t -ge 600 ] && say "STABLE for 10 min: $img"
done
say "done"
