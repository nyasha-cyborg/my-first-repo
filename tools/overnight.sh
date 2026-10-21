#!/bin/bash
# Job queue for the tablet, meant to be STARTED BY THE OPERATOR (it reboots
# the tablet and pulls files over adb).  Waits for the tablet, then:
#   1. pulls Wi-Fi calibration files from Android (read-only)
#   2. reads the PMIC interrupt registers in Android (reference values)
#   3. amp probe: vendor TFA9895 register recipe step by step (image n9ampA)
#   4. PMIC RTC-alarm / interrupt delivery check (image n9soak5)
#   5. 20-cycle boot soak (image n9soak5)
# usage: tools/overnight.sh        results in /tmp/n9build/overnight/
HERE=$(dirname "$0")
B=$HOME/Downloads/nexus9/bootimg-build/n9-mainline
OUT=/tmp/n9build/overnight
mkdir -p "$OUT"
log() { echo "$(date +%T) $*" | tee -a "$OUT/log.txt"; }
wait_tablet() { while ! lsusb | grep -qiE '18d1|0525|0955'; do sleep 20; done; }

log "waiting for the tablet"
wait_tablet
log "tablet is back"
for i in $(seq 1 60); do adb devices | grep -q 'device$' && break; sleep 5; done

log "job 1: pull Wi-Fi calibration files from Android"
adb root >/dev/null 2>&1; sleep 3; adb wait-for-device
mkdir -p "$OUT/wifi"
for f in /vendor/firmware/bcmdhd.cal /system/etc/wifi /vendor/etc/wifi /vendor/firmware/nvram.txt /vendor/firmware/bcmdhd_nvram.txt; do
	adb pull "$f" "$OUT/wifi/" >/dev/null 2>&1 && log "  pulled $f"
done
adb shell 'ls -R /vendor/firmware 2>/dev/null | grep -iE "bcm|nvram|cal"' > "$OUT/wifi/vendor-firmware-list.txt" 2>&1

log "job 2: PMIC interrupt registers in Android (reference)"
adb push /tmp/n9build/i2cget-min /data/local/tmp/ >/dev/null 2>&1
adb shell 'chmod 755 /data/local/tmp/i2cget-min; for r in 10 11 12 13 14 15 16 17 18 19 1a 1b 1c; do printf "p2[%s]=" $r; /data/local/tmp/i2cget-min 4 5a $r; done' > "$OUT/android-pmic-int-regs.txt" 2>&1

log "job 3: amp probe (n9ampA)"
"$HERE/n9boot.sh" "$B/n9ampA-stripped.img" load-audio >> "$OUT/log.txt" 2>&1
"$HERE/amp-probe.sh" > "$OUT/amp-probe.txt" 2>&1
log "  amp-probe done ($(wc -l < "$OUT/amp-probe.txt") lines)"
"$HERE/n9sh.sh" 'reboot -f' 3 >/dev/null 2>&1

log "job 4: PMIC RTC-alarm / interrupt delivery check (n9soak5)"
"$HERE/n9boot.sh" "$B/n9soak5-stripped.img" >> "$OUT/log.txt" 2>&1
"$HERE/n9sh.sh" '/bin/busybox --install -s /bin; mount -t debugfs none /sys/kernel/debug 2>/dev/null; echo ok' 9 >/dev/null
{
echo "before:"; "$HERE/n9sh.sh" "grep -E 'palmas|rtc' /proc/interrupts | cut -c1-70" 6
"$HERE/n9sh.sh" 'echo 0 > /sys/class/rtc/rtc0/wakealarm; echo $(( $(date +%s)+5 )) > /sys/class/rtc/rtc0/wakealarm; cat /sys/class/rtc/rtc0/wakealarm' 4
sleep 12
echo "after alarm:"; "$HERE/n9sh.sh" "grep -E 'palmas|rtc' /proc/interrupts | cut -c1-70" 6
echo "wakealarm now: $("$HERE/n9sh.sh" 'cat /sys/class/rtc/rtc0/wakealarm; date +%s' 4 | tr '\n' ' ')"
echo "dmesg tail:"; "$HERE/n9sh.sh" 'dmesg | tail -6 | cut -c1-120' 5
} > "$OUT/pmic-alarm.txt" 2>&1
"$HERE/n9sh.sh" 'reboot -f' 3 >/dev/null 2>&1

log "job 5: boot soak (20 cycles, n9soak5)"
rm -f /tmp/n9build/soak.log
"$HERE/soak-dbg.sh" "$B/n9soak5-stripped.img" 20 > "$OUT/soak.out" 2>&1
cp /tmp/n9build/soak.log "$OUT/soak.log" 2>/dev/null
log "all jobs done"
