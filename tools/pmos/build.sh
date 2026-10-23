#!/bin/bash
# Host side of the pmOS install (no root needed):
#   1. n9pmos-inst  : installer test image = n9 test ramdisk + current kernel/modules + apk.static + apk keys +
#                     install-rootfs.sh / finish-rootfs.sh (build the rootfs on the tablet, natively)
#   2. n9pmos-boot  : the pmOS boot image = current kernel + tiny busybox ramdisk (tools/pmos/init) that
#                     loop-mounts /data/pmos/rootfs.img; cmdline without the test images' watchdog arming
#   3. overlay.tgz  : kernel modules, firmware overrides, LTE modem service + firmware, ssh key
# Output: images in ~/Downloads/nexus9/bootimg-build/n9-mainline/, overlay in /tmp/n9build/pmos/
# Usage: tools/pmos/build.sh <base-ramdisk-dir> <base-stripped.img>
#   e.g. tools/pmos/build.sh /tmp/n9build/gpuA/rd ~/Downloads/nexus9/bootimg-build/n9-mainline/n9hsicI2-stripped.img
set -eu
BASE=$1 BIMG=$2
HERE=$(cd "$(dirname "$0")" && pwd)
T=$(cd "$HERE/.." && pwd)
KDIR=${KDIR:-$HOME/code/linux-flounder}
KOUT=${KOUT:-$HOME/code/linux-flounder-out}
PMOS=${PMOS:-v26.06} ALP=${ALP:-v3.24}
O=/tmp/n9build/pmos
D=$HOME/Downloads/nexus9/bootimg-build/n9-mainline
VF=$HOME/Downloads/nexus9/google-volantisg-n4f27p/vendor-files/mdm/image
CLANG="clang --target=aarch64-linux-gnu -nostdlib -static -O2 -fuse-ld=lld -fno-stack-protector -fno-builtin"
mk() { make -s -C "$KDIR" O="$KOUT" ARCH=arm64 LLVM=1 "$@"; }
setcmd() {	# image cmdline: the v0 header's 512-byte field at offset 64
	python3 -I -c 'import sys
p, c = sys.argv[1], sys.argv[2].encode()
b = bytearray(open(p, "rb").read()); b[64:576] = c + bytes(512 - len(c)); open(p, "wb").write(b)
print("cmdline", p.rsplit("/", 1)[-1] + ":", c.decode())' "$1" "$2"
}

REL=$(mk kernelrelease)
case $REL in *-dirty) echo "kernel tree is dirty ($REL): commit first" >&2; exit 1;; esac
# the binaries must really be this release (a stale build once carried an older release string)
strings "$KOUT/arch/arm64/boot/Image" | grep -q "Linux version $REL " || { echo "Image is not $REL: rebuild" >&2; exit 1; }
rm -rf "$O"; mkdir -p "$O/keys" "$O/ov"

# apk signing keys (https from the official mirrors), so apk verifies every index and package
fetch_keys() {	# repo-url package
	local idx ver
	idx=$(curl -fsSL "$1/aarch64/APKINDEX.tar.gz" | tar -xzO APKINDEX)
	ver=$(echo "$idx" | awk -v p="$2" '$0=="P:"p{f=1} f&&/^V:/{print substr($0,3); exit}')
	# only the real files in etc/apk/keys (usr/share/apk/keys holds symlinks and other arches)
	curl -fsSL "$1/aarch64/$2-$ver.apk" | tar -xzf - -C "$O/keys" --strip-components=3 --wildcards 'etc/apk/keys/*' 2>/dev/null || true
}
fetch_keys "https://dl-cdn.alpinelinux.org/alpine/$ALP/main" alpine-keys
fetch_keys "https://mirror.postmarketos.org/postmarketos/$PMOS" postmarketos-keys
echo "apk keys: $(ls "$O/keys" | tr '\n' ' ')"
[ "$(ls "$O/keys" | wc -l)" -ge 2 ] || { echo "apk keys missing" >&2; exit 1; }

# 3. overlay
mk INSTALL_MOD_PATH="$O/ov" INSTALL_MOD_STRIP=1 modules_install >/dev/null
rm -f "$O/ov/lib/modules/$REL/build" "$O/ov/lib/modules/$REL/source"
mkdir -p "$O/ov/lib/firmware" "$O/ov/usr/lib/n9-modem" "$O/ov/etc/init.d" "$O/ov/lib/firmware/n9-modem"
cp -a "$BASE/lib/firmware/." "$O/ov/lib/firmware/"				# tested brcm (WiFi nvram, BT hcd) + gk20a
cp -a "$BASE/fw/." "$O/ov/lib/firmware/n9-modem/"				# modem images + stubs + rcdata
cp "$VF/dsp1.mbn" "$O/ov/lib/firmware/n9-modem/"
cp "$BASE/bin/modem-gpio-min" "$BASE/bin/sahara" "$O/ov/usr/lib/n9-modem/"
$CLANG -o "$O/ov/usr/lib/n9-modem/qmi-connect" "$T/miniroot/qmi-connect.c"
cp "$T/mdm-boot.sh" "$T/mdm-data.sh" "$T/mdm-net.sh" "$O/ov/usr/lib/n9-modem/"
install -m755 "$T/rootfs/n9-modem.initd" "$O/ov/etc/init.d/n9-modem"
install -m755 "$HERE/n9-kmsg.initd" "$O/ov/etc/init.d/n9-kmsg"
install -m755 "$HERE/n9-health.initd" "$O/ov/etc/init.d/n9-health"
install -m755 "$HERE/n9-health.sh" "$O/ov/usr/lib/n9-modem/n9-health.sh"
K=$(ls "$HOME"/.ssh/id_*.pub 2>/dev/null | head -1 || true)
if [ -n "$K" ]; then mkdir -p "$O/ov/home/user/.ssh"; cp "$K" "$O/ov/home/user/.ssh/authorized_keys"; fi
# patched Mesa (GPU), built by tools/pmos/mesa/build-mesa.sh
[ -d /tmp/n9build/xbuild/dest/opt/mesa-n9 ] && cp -a /tmp/n9build/xbuild/dest/opt "$O/ov/" || echo "warning: no patched Mesa (run tools/pmos/mesa/build-mesa.sh)"
tar -C "$O/ov" --owner=0 --group=0 -czf "$O/overlay.tgz" .
echo "overlay: $(du -m "$O/overlay.tgz" | cut -f1) MiB"

# kernel region: gzip(Image) || dtb
python3 -I - "$KOUT" "$O/kernel" <<'PY'
import gzip, sys
o = sys.argv[1]
img = open(o + '/arch/arm64/boot/Image', 'rb').read()
dtb = open(o + '/arch/arm64/boot/dts/nvidia/tegra132-flounder.dtb', 'rb').read()
open(sys.argv[2], 'wb').write(gzip.compress(img, 9) + dtb)
PY

# 1. installer image
cp -a "$BASE" "$O/inst"
mods=$(ls "$BASE"/lib/modules/*/*.ko | xargs -n1 basename | sed 's/\.ko$//' | grep -vE '^(regdump|padsample|bitbang|sfio)$')
"$T/stage-modules.sh" "$KOUT" "$O/inst" $mods nouveau >/dev/null
OLD=$(strings "$BASE/init" | grep -o '/lib/modules/[^/]*/rfkill.ko' | head -1 | cut -d/ -f4)
[ ${#OLD} = ${#REL} ] || { echo "release length differs ($OLD vs $REL): rebuild the init from source" >&2; exit 1; }
LC_ALL=C sed -i "s/$OLD/$REL/g" "$O/inst/init"
cp /tmp/n9build/apk/x/sbin/apk.static "$O/inst/bin/apk.static"
mkdir -p "$O/inst/etc/n9-apk-keys" "$O/inst/etc/ssl/certs"; cp "$O/keys"/*.pub "$O/inst/etc/n9-apk-keys/"
cp /etc/ssl/certs/ca-certificates.crt "$O/inst/etc/ssl/cert.pem"	# apk.static (OpenSSL) CA file for the https mirrors
install -m755 "$HERE/install-rootfs.sh" "$HERE/finish-rootfs.sh" "$O/inst/bin/"
(cd "$O/inst" && find . | cpio -o -H newc --quiet | gzip -9 > "$O/inst.gz")
python3 -I "$T/bootimg-swap-ramdisk.py" "$BIMG" "$O/inst.gz" "$D/n9pmos-inst-stripped.img" "$O/kernel" | tail -1
setcmd "$D/n9pmos-inst-stripped.img" "androidboot.hardware=flounder buildvariant=user console=tty0"	# no watchdog arming:
	# a long apk run got the test init's busybox feeder killed and the 90 s watchdog reset the tablet mid-install

# 2. pmOS boot image
mkdir -p "$O/boot"/{bin,dev,proc,sys,root,data}
cp "$BASE/bin/busybox" "$O/boot/bin/busybox"
# e2fsck for the rootfs image (dynamic, Alpine v3.24) + its libraries and the musl loader
E=/tmp/n9build/e2s
if [ ! -x "$E/sbin/e2fsck" ]; then
	mkdir -p "$E/etc/apk/keys" "$E/etc/ssl"; cp "$O/keys"/*.pub "$E/etc/apk/keys/"
	cp /etc/ssl/certs/ca-certificates.crt "$E/etc/ssl/cert.pem"
	unshare -r /tmp/n9build/xbuild/apkx/sbin/apk.static --root "$E" --arch aarch64 --initdb --scripts=no -U \
		-X "https://dl-cdn.alpinelinux.org/alpine/$ALP/main" add e2fsprogs >/dev/null 2>&1 || true
fi
mkdir -p "$O/boot/sbin" "$O/boot/lib" "$O/boot/usr/lib"
cp -L "$E/sbin/e2fsck" "$O/boot/sbin/e2fsck"
cp -L "$E/lib/ld-musl-aarch64.so.1" "$O/boot/lib/"; ln -sf ld-musl-aarch64.so.1 "$O/boot/lib/libc.musl-aarch64.so.1"
# all shared libraries e2fsck needs, recursively (a hand-written list missed libeconf: e2fsck exited 127)
need() { readelf -d "$1" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'; }
todo=$(need "$E/sbin/e2fsck"); done_libs=" libc.musl-aarch64.so.1 "
while [ -n "$todo" ]; do
	next=
	for l in $todo; do
		case "$done_libs" in *" $l "*) continue;; esac
		done_libs="$done_libs$l "
		f=$(ls "$E"/usr/lib/$l "$E"/lib/$l 2>/dev/null | head -1)
		[ -n "$f" ] || { echo "e2fsck: missing $l" >&2; continue; }
		cp -L "$f" "$O/boot/usr/lib/$l"; next="$next $(need "$f")"
	done
	todo=$next
done
install -m755 "$HERE/init" "$O/boot/init"
(cd "$O/boot" && find . | cpio -o -H newc --quiet | gzip -9 > "$O/boot.gz")
python3 -I "$T/bootimg-swap-ramdisk.py" "$BIMG" "$O/boot.gz" "$D/n9pmos-boot-stripped.img" "$O/kernel" | tail -1
setcmd "$D/n9pmos-boot-stripped.img" "androidboot.hardware=flounder console=tty0 loglevel=6 tegra_wdt.early_start=1 tegra_wdt.heartbeat=60 nouveau.config=NvGk20aDvfs=0,NvGk20aPstate=7 cma=256M"	# fed by busybox watchdog (boot runlevel)
echo "release $REL: $D/n9pmos-inst-stripped.img, $D/n9pmos-boot-stripped.img, $O/overlay.tgz"
