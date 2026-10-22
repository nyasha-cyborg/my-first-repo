#!/bin/bash
# Cold-boot test of the device-side LTE bring-up service (tools/mdm-boot.sh baked into the test image):
# reboot into the image, push only dsp1.mbn (too big for the image), run /bin/mdm-boot.sh in the
# background on the tablet and poll its log from here.  Log: /tmp/n9build/lte-service-test.txt
HERE=$(dirname "$0")
IMG=${1:-$HOME/Downloads/nexus9/bootimg-build/n9-mainline/n9hsicI2-stripped.img}
OUT=/tmp/n9build/lte-service-test.txt
{
if [ -z "$SKIP_BOOT" ]; then
echo "== back to Android"; "$HERE/n9sh.sh" 'reboot -f' 3 >/dev/null 2>&1; sleep 5
for i in $(seq 1 60); do adb devices | grep -q 'device$' && break; sleep 3; done
echo "== boot $IMG"; timeout 500 "$HERE/n9boot.sh" "$IMG" 2>&1 | tail -1
fi
echo "== push dsp1.mbn"; python3 -I "$HERE/n9push.py" "$HOME/Downloads/nexus9/google-volantisg-n4f27p/vendor-files/mdm/image/dsp1.mbn" /tmp/dsp1.mbn | tail -2
echo "== start /bin/mdm-boot.sh (background)"
"$HERE/n9sh.sh" '(FW=/fw DSP1=/tmp/dsp1.mbn /bin/mdm-boot.sh > /tmp/mdm-boot.log 2>&1 &); sleep 1; echo started' 10
for i in $(seq 1 40); do
	sleep 5
	L=$("$HERE/n9sh.sh" 'cat /tmp/mdm-boot.log; tail -1 /tmp/mdm.log | cut -c1-80' 8 2>&1 | tr '\n' '|')
	echo "[$((i*5))s] $L"
	case "$L" in *"05c6:9048"*|*"never"*|*"cannot"*) break;; esac
done
echo "== final"; "$HERE/n9sh.sh" 'cat /tmp/mdm-boot.log; ls /dev/cdc-wdm* 2>&1; tail -1 /tmp/mdm.log' 12
echo flush
} 2>&1 | tee "$OUT"
