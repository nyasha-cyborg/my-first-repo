#!/bin/bash
# Power the LTE modem (vendor GPIO sequence, modem-gpio-min hold) on a running mainline
# test image and show what the HSIC host on the USB2 controller (7d004000) sees.
# Needs the tablet booted with a test image (tools/n9boot.sh <image>).  No images are sent,
# no EFS partition is touched.  Results: /tmp/n9build/lte-power-test.txt
HERE=$(dirname "$0")
OUT=/tmp/n9build/lte-power-test.txt
{
echo "== before"; "$HERE/n9sh.sh" 'dmesg -c >/dev/null; /bin/modem-gpio-min read 2>&1 | tail -1' 8
echo "== power on"; "$HERE/n9sh.sh" '(/bin/modem-gpio-min hold > /tmp/mdm.log 2>&1 &); sleep 9; tail -1 /tmp/mdm.log' 20
echo "== dmesg"; "$HERE/n9sh.sh" 'dmesg | cut -c1-160 | tail -25' 10
echo "== usb"; "$HERE/n9sh.sh" 'ls /sys/bus/usb/devices; cat /sys/kernel/debug/usb/devices 2>/dev/null | grep -E "^(T|P|S|I):"; grep -E "^174|^134" /sys/kernel/debug/tegra-hsic-regs' 10
echo flush
} 2>&1 | tee "$OUT"
