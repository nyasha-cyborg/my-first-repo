#!/bin/sh
# Build the modem's per-unit Sahara files (EFS + HTC NV) from THIS tablet's own partitions, read-only
# (dd/cat only, same recipe as the stock qcks, see notes/lte.md) into $OUT and print the sahara
# "id:path@offset" arguments on stdout.  Needs: $FW (stub headers htc*.mbn + rcdata_*.img from the stock
# vendor/firmware/mdm/image), readable mmcblk0 partitions named EF1/EF2/RCA/CDR.  Nothing is written
# to any partition.  The output contains the unit's IMEI/calibration: keep it in RAM (/tmp), never
# on persistent storage.
FW=${FW:-/fw}
OUT=${OUT:-/tmp/mdata.bin}
T=${TMPDIR:-/tmp}/mdmdata.$$

part() {
	for p in /sys/class/block/mmcblk*p*; do
		if grep -qx "PARTNAME=$1" "$p/uevent" 2>/dev/null; then
			echo "/dev/$(basename "$p")"
			return 0
		fi
	done
	return 1
}

EF1=$(part EF1) && EF2=$(part EF2) && RCA=$(part RCA) && CDR=$(part CDR) || {
	echo "mdm-data: cannot find EF1/EF2/RCA/CDR partitions" >&2
	exit 1
}
mkdir -p "$T" || exit 1
: > "$OUT"
off=0
ARGS=""

add() {		# id file
	sz=$(wc -c < "$2")
	ARGS="$ARGS $1:$OUT@$off"
	cat "$2" >> "$OUT"
	off=$((off + sz))
}

kib() {		# dev skipKiB countKiB > stdout
	dd if="$1" bs=1024 skip="$2" count="$3" 2>/dev/null
}

kib "$EF1" 0 3072 > "$T/p"; add 16 "$T/p"
kib "$EF2" 0 3072 > "$T/p"; add 17 "$T/p"
htc() {		# id stub dev skipKiB
	cat "$FW/$2" > "$T/p"
	kib "$3" "$4" 1024 >> "$T/p"
	add "$1" "$T/p"
}
htc 40 htcssmem.mbn "$RCA" 0
htc 42 htcnvmfg.mbn "$RCA" 1024
htc 43 htcrfnv.mbn "$RCA" 3072
htc 45 htcuserd.mbn "$RCA" 2048
htc 46 htccdma.mbn "$CDR" 0
cnv() {		# id stub rcdata   (carrier NV: rcdata overlaid onto RCA@7168K, in memory only)
	kib "$RCA" 7168 1024 > "$T/c"
	[ -n "$3" ] && [ -f "$FW/$3" ] && dd if="$FW/$3" of="$T/c" conv=notrunc 2>/dev/null
	cat "$FW/$2" "$T/c" > "$T/p"
	add "$1" "$T/p"
}
cnv 44 htccnv_a.mbn rcdata_att.img
cnv 47 htccnv_t.mbn rcdata_tmo.img
cnv 48 htccnv_v.mbn rcdata_vzw.img
cnv 49 htccnv_s.mbn ""
cnv 55 htccnv_u.mbn rcdata_ul.img
cnv 56 htccnv_o.mbn rcdata_o2.img
rm -rf "$T"
chmod 600 "$OUT"
echo "$ARGS" | sed 's/^ //'
