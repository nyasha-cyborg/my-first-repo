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
# a single 44 MB push hangs the tablet at ~30 MB (2026-10-23): push 8 MB parts and join them on the tablet
echo "== push dsp1.mbn (8 MB parts)"; mkdir -p /tmp/n9build/dsp1parts; rm -f /tmp/n9build/dsp1parts/*
split -b 8388608 -d "$HOME/Downloads/nexus9/google-volantisg-n4f27p/vendor-files/mdm/image/dsp1.mbn" /tmp/n9build/dsp1parts/p
# each part: up to 3 tries (a checksum mismatch or missing ACK happens now and then), short pause between parts
for f in /tmp/n9build/dsp1parts/p*; do
	ok=
	for try in 1 2 3; do
		python3 -I "$HERE/n9push.py" "$f" /tmp/$(basename "$f") > /tmp/n9build/push.out 2>&1; rc=$?
		tail -1 /tmp/n9build/push.out
		[ $rc = 0 ] && { ok=1; break; }
		echo "retry $(basename "$f") ($try)"; sleep 5
		"$HERE/n9sh.sh" 'echo alive' 10 | grep -q alive || sleep 20
	done
	[ -n "$ok" ] || { echo "push of $(basename "$f") failed 3 times, giving up"; exit 1; }
	sleep 2
done
"$HERE/n9sh.sh" 'cat /tmp/p?? > /tmp/dsp1.mbn; rm /tmp/p??; sha256sum /tmp/dsp1.mbn | cut -c1-16' 30
sha256sum "$HOME/Downloads/nexus9/google-volantisg-n4f27p/vendor-files/mdm/image/dsp1.mbn" | cut -c1-16
clang --target=aarch64-linux-gnu -nostdlib -static -O2 -fuse-ld=lld -fno-stack-protector -fno-builtin -o /tmp/n9build/qmiraw "$HERE/miniroot/qmiraw.c"
python3 -I "$HERE/n9push.py" /tmp/n9build/qmiraw /tmp/qmiraw | tail -1; "$HERE/n9sh.sh" 'chmod +x /tmp/qmiraw' 5
echo "== start /bin/mdm-boot.sh (background)"
"$HERE/n9sh.sh" '(FW=/fw DSP1=/tmp/dsp1.mbn /bin/mdm-boot.sh > /tmp/mdm-boot.log 2>&1 &); sleep 1; echo started' 10
for i in $(seq 1 40); do
	sleep 5
	L=$("$HERE/n9sh.sh" 'cat /tmp/mdm-boot.log; tail -1 /tmp/mdm.log | cut -c1-80' 8 2>&1 | tr '\n' '|')
	echo "[$((i*5))s] $L"
	case "$L" in *"05c6:9048"*|*"never"*|*"cannot"*) break;; esac
done
echo "== final"; "$HERE/n9sh.sh" 'cat /tmp/mdm-boot.log; ls /dev/cdc-wdm* 2>&1; tail -1 /tmp/mdm.log' 12
# APN=<apn>: also test the data call (the image's /bin/mdm-boot.sh predates mdm-net.sh, so run it from /tmp)
if [ -n "$APN" ]; then
	echo "== data call (APN $APN)"
	clang --target=aarch64-linux-gnu -nostdlib -static -O2 -fuse-ld=lld -fno-stack-protector -fno-builtin \
		-o /tmp/n9build/qmi-connect "$HERE/miniroot/qmi-connect.c"
	python3 -I "$HERE/n9push.py" /tmp/n9build/qmi-connect /tmp/qmi-connect | tail -1
	python3 -I "$HERE/n9push.py" "$HERE/mdm-net.sh" /tmp/mdm-net.sh | tail -1
	"$HERE/n9sh.sh" "chmod +x /tmp/qmi-connect /tmp/mdm-net.sh; (APN=$APN /tmp/mdm-net.sh > /tmp/mdm-net.log 2>&1 &); sleep 1; echo started" 10
	for i in $(seq 1 40); do
		sleep 5
		L=$("$HERE/n9sh.sh" 'cat /tmp/mdm-net.log' 8 2>&1 | tr '\n' '|')
		echo "[$((i*5))s] $L"
		case "$L" in *"mdm-net: "*) break;; esac
	done
	"$HERE/n9sh.sh" 'ip route | grep wwan0; ping -c 4 -W 3 -I wwan0 1.1.1.1 | tail -2; nslookup example.com $(sed -n "s/QMI_DNS1=//p" /tmp/mdm-net.env) 2>&1 | tail -2' 40
fi
echo flush
} 2>&1 | tee "$OUT"
