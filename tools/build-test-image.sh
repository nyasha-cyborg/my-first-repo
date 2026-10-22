#!/bin/bash
# Rebuild kernel + modules + ramdisk and wrap them into a flounder test image.
# The kernel tree must be committed first (release string = module paths).
#   usage: tools/build-test-image.sh <base-ramdisk-dir> <base-stripped.img> <out-name> [init.c]
# - base-ramdisk-dir: an extracted ramdisk (e.g. /tmp/n9build/rdW); copied, not modified
# - base image: any stripped image of the same layout (used as the container)
# - init.c: init source with a literal release string, default /tmp/n9build/init-w.c
# Output: ~/Downloads/nexus9/bootimg-build/n9-mainline/<out-name>-stripped.img
set -eu
BASE=$1 BIMG=$2 OUT=$3 INIT=${4:-/tmp/n9build/init-w.c}
KDIR=${KDIR:-$HOME/code/linux-flounder}
KOUT=${KOUT:-$HOME/code/linux-flounder-out}
HERE=$(cd "$(dirname "$0")" && pwd)
W=/tmp/n9build/img-$OUT
rm -rf "$W"; mkdir -p "$W"
make -s -C "$KDIR" O="$KOUT" ARCH=arm64 LLVM=1 -j"$(nproc)" Image modules nvidia/tegra132-flounder.dtb
REL=$(make -s -C "$KDIR" O="$KOUT" ARCH=arm64 LLVM=1 kernelrelease)
case $REL in *-dirty) echo "kernel tree is dirty ($REL): commit first" >&2; exit 1;; esac
cp -a "$BASE" "$W/rd"
mods=$(ls "$BASE"/lib/modules/*/*.ko | xargs -n1 basename | sed 's/\.ko$//' | grep -vE '^(regdump|padsample|bitbang|sfio)$')
"$HERE/stage-modules.sh" "$KOUT" "$W/rd" $mods
make -s -C "$KDIR" O="$KOUT" ARCH=arm64 LLVM=1 M="$HERE/miniroot/regdump" modules 2>&1 | grep -v DESCR || true
cp "$HERE"/miniroot/regdump/*.ko "$W/rd/lib/modules/$REL/"
OLD=$(grep -o '/lib/modules/[^/]*/rfkill.ko' "$INIT" | head -1 | cut -d/ -f4)
sed "s|$OLD|$REL|g" "$INIT" > "$W/init.c"
clang --target=aarch64-linux-gnu -nostdlib -static -O2 -fuse-ld=lld -fno-stack-protector -fno-builtin \
	-DN9BUILD="${N9BUILD:-399}" -o "$W/rd/init" "$W/init.c"
(cd "$W/rd" && find . | cpio -o -H newc --quiet 2>/dev/null | gzip -9 > "$W/rd.gz")
python3 -I - "$KOUT" "$W/kernel" <<'PY'
import gzip, sys
o = sys.argv[1]
img = open(o + '/arch/arm64/boot/Image', 'rb').read()
dtb = open(o + '/arch/arm64/boot/dts/nvidia/tegra132-flounder.dtb', 'rb').read()
open(sys.argv[2], 'wb').write(gzip.compress(img, 9) + dtb)
PY
D=$HOME/Downloads/nexus9/bootimg-build/n9-mainline
python3 "$HERE/bootimg-swap-ramdisk.py" "$BIMG" "$W/rd.gz" "$D/$OUT-stripped.img" "$W/kernel" | tail -1
echo "release $REL -> $D/$OUT-stripped.img"
