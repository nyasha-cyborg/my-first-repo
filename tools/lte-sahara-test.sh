#!/bin/bash
# Full LTE bring-up test cycle (user-run: the classifier blocks the modem power-on / boot from
# the assistant's tools).  Boots a test image that contains /bin/sahara and /fw/*.mbn,
# powers the modem (vendor GPIO sequence), runs the Sahara loader and logs everything.
#   usage: tools/lte-sahara-test.sh [image]       default: n9hsicC2
# SKIP_BOOT=1 reuses an already booted test image.  Log: /tmp/n9build/lte-sahara-test.txt     Nothing is flashed; no EFS partition is touched.
HERE=$(dirname "$0")
IMG=${1:-$HOME/Downloads/nexus9/bootimg-build/n9-mainline/n9hsicC2-stripped.img}
OUT=/tmp/n9build/lte-sahara-test.txt
{
if [ -z "$SKIP_BOOT" ]; then
echo "== back to Android"; "$HERE/n9sh.sh" 'reboot -f' 3 >/dev/null 2>&1; sleep 5
for i in $(seq 1 60); do adb devices | grep -q 'device$' && break; sleep 3; done
echo "== boot $IMG"; timeout 500 "$HERE/n9boot.sh" "$IMG" 2>&1 | tail -1
fi
echo "== power on the modem"; "$HERE/n9sh.sh" 'dmesg -c >/dev/null; (/bin/modem-gpio-min hold > /tmp/mdm.log 2>&1 &); sleep 9; tail -1 /tmp/mdm.log' 20
echo "== usb"; "$HERE/n9sh.sh" 'mount -t debugfs none /sys/kernel/debug 2>/dev/null; dmesg | grep -E "usb 1-|descriptor" | cut -c1-120 | tail -5; cat /sys/bus/usb/devices/1-1/idVendor /sys/bus/usb/devices/1-1/idProduct /sys/bus/usb/devices/1-1/busnum /sys/bus/usb/devices/1-1/devnum 2>&1' 12
echo "== push dsp1.mbn over the USB serial console (raw, checksummed)"
python3 -I "$HERE/n9push.py" "$HOME/Downloads/nexus9/google-volantisg-n4f27p/vendor-files/mdm/image/dsp1.mbn" /tmp/dsp1.mbn
echo "== sahara"
"$HERE/n9sh.sh" 'B=$(cat /sys/bus/usb/devices/1-1/busnum); D=$(cat /sys/bus/usb/devices/1-1/devnum); N=$(printf "/dev/bus/usb/%03d/%03d" $B $D); echo node $N; (/bin/sahara $N 21:/fw/sbl1.mbn 23:/fw/rpm.mbn 25:/fw/tz.mbn 31:/fw/mba.mbn 8:/tmp/dsp1.mbn 6:/fw/apps.mbn 30:/fw/sdi.mbn 16:=zero 17:=zero 40:+/fw/htcssmem.mbn 42:+/fw/htcnvmfg.mbn 43:+/fw/htcrfnv.mbn 45:+/fw/htcuserd.mbn 46:+/fw/htccdma.mbn 44:+/fw/htccnv_a.mbn 47:+/fw/htccnv_t.mbn 48:+/fw/htccnv_v.mbn 49:+/fw/htccnv_s.mbn 55:+/fw/htccnv_u.mbn 56:+/fw/htccnv_o.mbn > /tmp/sahara.log 2>&1 &); sleep 75; cat /tmp/sahara.log | grep -vE "^rx cmd=3" | tail -40; echo "reads: $(grep -c "^rx cmd=3" /tmp/sahara.log)"; grep "^rx cmd=3" /tmp/sahara.log | tail -3' 100
echo "== second enumeration: power-cycle the HSIC port and watch for new devices"
"$HERE/n9sh.sh" 'dmesg -c >/dev/null; P=/sys/kernel/debug/tegra-hsic-poke; echo "174 0 1000" > $P; sleep 1; echo "174 1000 0" > $P; for i in $(seq 1 30); do echo "t$i $(for d in /sys/bus/usb/devices/1-1*; do [ -f $d/idProduct ] && echo -n "$(basename $d)=$(cat $d/idVendor):$(cat $d/idProduct) "; done) | $(tail -1 /tmp/mdm.log | cut -c1-70) | portsc $(grep ^174 /sys/kernel/debug/tegra-hsic-regs | cut -d" " -f2)"; sleep 1; done; dmesg | grep -E "usb 1-" | cut -c1-130 | tail -15' 60
echo "== after"; "$HERE/n9sh.sh" 'dmesg | cut -c1-140 | tail -15; cat /sys/kernel/debug/usb/devices | grep -E "^(T|P|S):"; /bin/modem-gpio-min read 2>&1 | tail -1' 15
echo flush
} 2>&1 | tee "$OUT"
