#!/bin/bash
# Boot a debug image and wait until its serial shell answers.
#   usage: tools/n9boot.sh <image> [load-audio]
# With "load-audio" it also installs busybox applets and loads the audio stack.
HERE=$(dirname "$0")
IMG=$1
for i in $(seq 1 120); do adb devices | grep -q 'device$' && break; sleep 3; done
adb reboot bootloader 2>/dev/null
for i in $(seq 1 30); do fastboot devices | grep -q . && break; sleep 1; done
fastboot boot "$IMG" >/dev/null 2>&1
for i in $(seq 1 60); do [ -e /dev/ttyACM0 ] && lsusb | grep -q 0525:a4a7 && break; sleep 1; done
sleep 12
ok=0
for t in $(seq 1 10); do
	"$HERE/n9sh.sh" 'echo ready' 4 | grep -q ready && { ok=1; break; }
done
[ $ok = 1 ] || { echo "shell not ready"; exit 1; }
"$HERE/n9sh.sh" '/bin/busybox --install -s /bin' 8 >/dev/null
if [ "$2" = load-audio ]; then
	"$HERE/n9sh.sh" 'for m in snd-soc-tegra30-i2s snd-soc-rt5677 snd-soc-rt5677-spi snd-soc-tfa989x snd-soc-tegra-machine; do modprobe $m 2>&1; done' 30 >/dev/null
	for t in 1 2 3 4 5 6; do "$HERE/n9sh.sh" 'cat /proc/asound/cards' 4 | grep -q speakers && break; sleep 3; done
fi
"$HERE/n9sh.sh" 'echo flush' 3 >/dev/null
echo "shell ready, $(date +%T)"
