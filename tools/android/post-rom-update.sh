#!/bin/bash
# Re-apply all Nexus 9 changes after a newer LineageOS 16 (retiredtab flounder) build was installed with TWRP.
# Idempotent: each step checks the tablet first and skips what is already in place. Stops on the first error.
#
# usage: tools/android/post-rom-update.sh [options]   (all inputs default to ~/Downloads/nexus9/android-addons/)
#   --boot <img>       kernel boot image        (default ~/n9kernel/out/boot-secD.img)
#   --stage <dir>      stock vendor LTE stage   (default /tmp/n9ltetx/stage, see lte/install-lte-lineage16.sh)
#   --oemcrypto <so>   stock /vendor/lib/liboemcrypto.so (default /tmp/n9ltetx/out/lib/liboemcrypto.so, 42660 B)
#   --rild <bin>       rild built per lte/install-lte-lineage16.sh header
#   --overlay <apk>    built+signed overlay from lte/overlay (keystore is not in git)
#   --skip-kernel      do not touch LNX
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); LTE=$HERE/lte; KICK=$HERE/../usb-kick.sh
ADD=~/Downloads/nexus9/android-addons
BOOT=$ADD/boot-secD.img; STAGE=$ADD/lte-stage; OEMC=$ADD/liboemcrypto.so
RILD=$ADD/rild; OVL=$ADD/N9MobileOverlay.apk; SKIPK=0; BK=~/Downloads/nexus9/boot-backups
while [ $# -gt 0 ]; do case $1 in
	--boot) BOOT=$2; shift;; --stage) STAGE=$2; shift;; --oemcrypto) OEMC=$2; shift;;
	--rild) RILD=$2; shift;; --overlay) OVL=$2; shift;; --skip-kernel) SKIPK=1;;
	*) echo "unknown arg $1"; exit 2;; esac; shift; done
SUMMARY=()
note() { echo "== $*"; }
done_() { SUMMARY+=("$1: $2"); echo "   -> $2"; }
die() { echo "ERROR: $*" >&2; exit 1; }
for f in "$BOOT" "$OEMC" "$RILD" "$OVL" "$LTE/rild.rc" "$LTE/vintf-manifest-radio.diff" "$LTE/apn-skinny.sql"; do
	[ -n "$f" ] && [ -f "$f" ] || die "missing file: '${f}' (need --rild and --overlay; check defaults)"; done
[ -d "$STAGE" ] || die "missing stage dir $STAGE"

# Wait for adb; after 3 min without it run usb-kick once, then give up after another 5 min.
wait_adb() {
	local t=0 kicked=0
	until adb get-state 2>/dev/null | grep -q device; do
		sleep 5; t=$((t+5))
		if [ $t -ge 180 ] && [ $kicked = 0 ]; then echo "   adb gone 3 min, usb-kick"; "$KICK" || true; kicked=1; fi
		[ $t -ge 480 ] && die "adb did not come back (power-cycle the tablet)"
	done
	adb wait-for-device; until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 3; done
}
root_rw() { adb root >/dev/null; sleep 2; wait_adb; adb remount >/dev/null || die "adb remount failed"; }
sh_() { adb shell "$@" | tr -d '\r'; }
rsha() { sh_ "sha256sum $1 2>/dev/null" | cut -d' ' -f1; }
lsha() { sha256sum "$1" | cut -d' ' -f1; }
# push a file only if the on-device copy differs; returns 0 if pushed
push_if() { # local remote mode
	if [ "$(rsha "$2")" = "$(lsha "$1")" ]; then return 1; fi
	adb push "$1" "$2" >/dev/null; sh_ "chmod $3 $2; restorecon $2"; return 0; }
NEED_REBOOT=0
reboot_now() { note "reboot"; adb reboot; sleep 20; wait_adb; root_rw; NEED_REBOOT=0; }

wait_adb; root_rw

# ---- 1. kernel
note "1. kernel"
LNX=/dev/block/platform/sdhci-tegra.3/by-name/LNX
if [ $SKIPK = 1 ]; then done_ kernel "skipped (--skip-kernel)"; else
	SZ=$(stat -c %s "$BOOT"); WANT=$(lsha "$BOOT")
	HAVE=$(sh_ "head -c $SZ $LNX | sha256sum" | cut -d' ' -f1)
	if [ "$HAVE" = "$WANT" ]; then done_ kernel "LNX already = $(basename "$BOOT")"; else
		mkdir -p "$BK"; B=$BK/lnx-lineage16-$(date +%Y%m%d-%H%M)-$(sh_ uname -r).img
		adb exec-out "dd if=$LNX bs=1M 2>/dev/null" > "$B"
		[ "$(sh_ "sha256sum $LNX" | cut -d' ' -f1)" = "$(lsha "$B")" ] || die "LNX backup checksum mismatch ($B)"
		echo "   backup $B"
		adb reboot bootloader; until fastboot devices | grep -q .; do sleep 3; done
		fastboot flash boot "$BOOT"; fastboot reboot; sleep 20; wait_adb; root_rw
		HAVE=$(sh_ "head -c $SZ $LNX | sha256sum" | cut -d' ' -f1)
		[ "$HAVE" = "$WANT" ] || die "LNX readback mismatch after flash"
		done_ kernel "flashed $(basename "$BOOT"), verified; backup $(basename "$B")"
	fi
fi

# ---- 2. LTE transplant (install-lte-lineage16.sh + .notes steps)
note "2. LTE transplant"
n=0
while IFS= read -r -d '' f; do rel=${f#"$STAGE"/}
	m=644; case $rel in bin/*) m=755;; esac
	if [ "$(rsha "/vendor/$rel")" != "$(lsha "$f")" ]; then
		sh_ "mkdir -p /vendor/$(dirname "$rel")"; adb push "$f" "/vendor/$rel" >/dev/null || die "push $rel"
		sh_ "chmod $m /vendor/$rel"; n=$((n+1)); fi
done < <(find "$STAGE" -type f -print0)
done_ lte-vendor "$n stock vendor files pushed"
sh_ "mkdir -p /vendor/bin/hw"
c=0
push_if "$RILD" /vendor/bin/hw/rild 755 && c=$((c+1))
push_if "$LTE/rild.rc" /vendor/etc/init/rild.rc 644 && c=$((c+1))
for x in "$LTE"/permissions/*.xml; do push_if "$x" "/vendor/etc/permissions/$(basename "$x")" 644 && c=$((c+1)); done
sh_ "mkdir -p /vendor/overlay"
push_if "$OVL" /vendor/overlay/N9MobileOverlay.apk 644 && c=$((c+1))
if sh_ "grep -q android.hardware.radio /vendor/etc/vintf/manifest.xml && echo y" | grep -q y; then
	done_ vintf "radio HAL already in manifest"
else
	T=$(mktemp -d); adb pull /vendor/etc/vintf/manifest.xml "$T/orig.xml" >/dev/null
	patch -o "$T/new.xml" "$T/orig.xml" "$LTE/vintf-manifest-radio.diff" || die "vintf diff does not apply to new ROM manifest ($T)"
	adb push "$T/new.xml" /vendor/etc/vintf/manifest.xml >/dev/null; sh_ "chmod 644 /vendor/etc/vintf/manifest.xml"
	done_ vintf "radio HAL added"; c=$((c+1))
fi
sh_ "chmod 755 /vendor/bin/* 2>/dev/null; restorecon -R /vendor" || true
done_ lte-extra "$c rild/rc/feature/overlay/manifest files changed"
[ $((n+c)) -gt 0 ] && NEED_REBOOT=1

# ---- 3. liboemcrypto (NVIDIA OMX HW decode)
note "3. liboemcrypto"
if push_if "$OEMC" /vendor/lib/liboemcrypto.so 644; then done_ oemcrypto pushed; NEED_REBOOT=1; else done_ oemcrypto present; fi

# ---- 4. /data dirs (vendor_init cannot create them on this build)
note "4. /data dirs"
sh_ 'set -e; mk() { mkdir -p $1; chown $2 $1; chmod $3 $1; restorecon $1; }
mk /data/nvcam cameraserver:camera 0700; mk /data/qcks system:system 0770; mk /data/qcks/mdm system:system 0770
mk /data/gps gps:system 0770; mk /data/efs system:system 0771'
done_ data-dirs "nvcam qcks qcks/mdm gps efs ok"

# reboot so rild/overlay/vintf/codec list load (needed before telephony.db exists for the APN step)
[ $NEED_REBOOT = 1 ] && reboot_now

# ---- 2b. APN + preferred network
note "2b. APN / network mode"
DB=/data/user_de/0/com.android.providers.telephony/databases/telephony.db
if ! sh_ "command -v sqlite3" | grep -q .; then die "no sqlite3 on device"; fi
CNT=$(sh_ "sqlite3 $DB 'select count(*) from carriers;'" || echo err)
case $CNT in
	0) adb push "$LTE/apn-skinny.sql" /data/local/tmp/apn.sql >/dev/null
	   sh_ "sqlite3 $DB < /data/local/tmp/apn.sql; rm /data/local/tmp/apn.sql"; done_ apn "Skinny APNs inserted";;
	''|err) die "cannot read carriers table ($DB)";;
	*) done_ apn "carriers has $CNT rows, left alone";;
esac
for k in preferred_network_mode preferred_network_mode1; do
	[ "$(sh_ "settings get global $k")" = 9 ] || sh_ "settings put global $k 9"; done
done_ netmode "preferred_network_mode(1)=9"

# ---- 5. checks
note "5. checks"
FAIL=0
chk() { if [ "$2" = ok ]; then done_ "check $1" "OK $3"; else done_ "check $1" "FAIL $3"; FAIL=1; fi; }
U=$(sh_ uname -r); chk uname ok "$U"
sh_ "logcat -d -b all | grep -q 'OMXMaster.*plugin failed'" && chk omx bad "OMXMaster 'plugin failed' in logcat" || chk omx ok "no 'plugin failed'"
F=$(sh_ "pm list features | grep -c telephony"); [ "${F:-0}" -ge 2 ] && chk telephony ok "$F features" || chk telephony bad "$F features"
S=$(sh_ "getprop gsm.sim.state"); [ -n "$S" ] && chk sim ok "gsm.sim.state=$S" || chk sim bad "gsm.sim.state empty"
sh_ "pidof cameraserver" | grep -q . && chk camera ok "cameraserver running" || chk camera bad "cameraserver not running"

echo; echo "===== summary"; printf '  %s\n' "${SUMMARY[@]}"
[ $FAIL = 0 ] && echo "ALL DONE" || { echo "SOME CHECKS FAILED"; exit 1; }
