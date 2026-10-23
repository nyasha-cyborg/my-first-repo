#!/bin/bash
# Decode test clips on the tablet with tegra-vde at a given t124_mask and score the hardware output
# against avdec_h264 (per plane, bit-exact share per frame).
#   usage: tools/vde-test.sh MASK [clip[:frames]...]   clips live in the tablet's /tmp
#          (default: m_wp m_b m_cabac); clip:N decodes only the first N frames
# References (<clip>.sw) are produced once on the tablet; /root/tegra-vde.ko is the module under test.
HERE=$(cd "$(dirname "$0")" && pwd)
IP=${IP:-192.168.1.109}; SSH="ssh -o ConnectTimeout=5 root@$IP"
MASK=$1; shift; CLIPS=${*:-m_wp m_b m_cabac}
OUT=/tmp/vde; mkdir -p $OUT
$SSH "rmmod tegra_vde 2>/dev/null; insmod /root/tegra-vde.ko t124_mask=$MASK || exit 1; cd /tmp; dmesg -C
for c in $CLIPS; do
  n=\${c%%:*}; f=\${c#*:}; [ \$f = \$c ] && f=100000; n=\$n\$([ \$f = 100000 ] || echo _\$f)
  e=\"identity eos-after=\$f\"; [ \$f = 100000 ] && e=identity
  [ -s \$n.sw ] || timeout 300 gst-launch-1.0 -q filesrc location=\${c%%:*}.mp4 ! qtdemux ! h264parse ! avdec_h264 ! video/x-raw,format=I420 ! \$e ! filesink location=\$n.sw >/dev/null 2>&1
  timeout 120 gst-launch-1.0 -q filesrc location=\${c%%:*}.mp4 ! qtdemux ! h264parse ! v4l2slh264dec ! video/x-raw ! \$e ! filesink location=\$n.hw >/dev/null 2>&1
done
echo faults=\$(dmesg | grep -c 'Page fault') errs=\$(dmesg | grep -ciE 'fail|timeout')" || exit 1
for c in $CLIPS; do
	n=${c%%:*}; m=$n; [ "$n" != "$c" ] && n=${n}_${c#*:}
	scp -q root@$IP:/tmp/$n.hw root@$IP:/tmp/$n.sw $OUT/ || continue
	W=$($SSH "gst-discoverer-1.0 /tmp/$m.mp4 2>/dev/null | grep -m1 Width: | tr -dc 0-9")
	H=$($SSH "gst-discoverer-1.0 /tmp/$m.mp4 2>/dev/null | grep -m1 Height: | tr -dc 0-9")
	python3 -I "$HERE/vde-score.py" $OUT/$n $W $H
done
