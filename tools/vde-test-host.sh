#!/bin/bash
# Like vde-test.sh, but the reference (avdec_h264) decode runs on the HOST with ffmpeg; the tablet only
# does the hardware decode. Much faster for >=720p.
#   usage: [MASK2=n] tools/vde-test-host.sh MASK clip[:frames]...
# Clips live in the tablet's /tmp and are cached in /tmp/vde-src on the host.
HERE=$(cd "$(dirname "$0")" && pwd)
IP=${IP:-192.168.1.109}; SSH="ssh -o ConnectTimeout=5 root@$IP"
MASK=$1; shift; CLIPS=${*:-m_wp m_b m_cabac}
MASK2=${MASK2:-0}
SRC=${SRC:-/tmp/vde-src}; OUT=${OUT:-/tmp/vde}; mkdir -p "$SRC" "$OUT"

$SSH "rmmod tegra_vde 2>/dev/null; insmod /root/tegra-vde.ko t124_mask=$MASK t124_mask2=$MASK2 || exit 1; cd /tmp; dmesg -C
for c in $CLIPS; do
  n=\${c%%:*}; f=\${c#*:}; [ \$f = \$c ] && f=100000
  if [ \$f = 100000 ]; then e=identity; else e=\"identity eos-after=\$f\"; fi
  timeout 300 gst-launch-1.0 -q filesrc location=\${c%%:*}.mp4 ! qtdemux ! h264parse ! v4l2slh264dec ! video/x-raw ! \$e ! filesink location=\$n.hw >/dev/null 2>&1
done
echo faults=\$(dmesg | grep -c 'Page fault') errs=\$(dmesg | grep -ciE 'fail|timeout')" || exit 1

for c in $CLIPS; do
	n=${c%%:*}; m=$n; f=100000
	[ "$n" != "$c" ] && { f=${c#*:}; n=${n}_${f}; }
	[ -s "$SRC/$m.mp4" ] || scp -q root@$IP:/tmp/$m.mp4 "$SRC/" || continue
	if [ "$f" = 100000 ]; then
		ffmpeg -y -v error -i "$SRC/$m.mp4" -f rawvideo -pix_fmt yuv420p "$OUT/$n.sw"
	else
		# identity eos-after=N emits N+1 buffers in this pipeline
		ffmpeg -y -v error -i "$SRC/$m.mp4" -frames:v $((f + 1)) -f rawvideo -pix_fmt yuv420p "$OUT/$n.sw"
	fi
	scp -q root@$IP:/tmp/$n.hw "$OUT/" || continue
	read W H < <(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0 "$SRC/$m.mp4" | tr ',' ' ')
	python3 -I "$HERE/vde-score.py" "$OUT/$n" $W $H
done
