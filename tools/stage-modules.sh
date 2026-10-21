#!/bin/bash
# Stage a minimal, depmod-consistent module tree for a test ramdisk.
#
# usage: tools/stage-modules.sh <kernel-build-dir> <ramdisk-root> <module>...
#   e.g. tools/stage-modules.sh ~/code/linux-flounder-out /tmp/n9build/rdX \
#          hci_uart brcmfmac snd-soc-tfa989x
#
# Installs the whole module set into a scratch tree with `make modules_install`,
# follows `modprobe --show-depends` for each requested module, copies only
# that closure to <ramdisk-root>/lib/modules/<release>/, and runs depmod there.
# Any old /lib/modules/* in the ramdisk root is removed first (module paths
# must equal `make kernelrelease`, see HANDOFF trap 3).
set -eu
OUT=$1
ROOT=$2
shift 2
KDIR=${KDIR:-$HOME/code/linux-flounder}
REL=$(make -s -C "$KDIR" O="$OUT" ARCH=arm64 LLVM=1 kernelrelease)
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

make -s -C "$KDIR" O="$OUT" ARCH=arm64 LLVM=1 INSTALL_MOD_PATH="$SCRATCH" \
	INSTALL_MOD_STRIP=1 modules_install >/dev/null
SRC=$SCRATCH/lib/modules/$REL
DST=$ROOT/lib/modules/$REL
rm -rf "$ROOT"/lib/modules/*
mkdir -p "$DST"

for m in "$@"; do
	modprobe -d "$SCRATCH" -S "$REL" --show-depends "$m" 2>/dev/null \
		| awk '$1 == "insmod" { print $2 }'
done | sort -u | while read -r f; do
	case $f in
	*.zst) zstd -dqf "$f" -o "$DST/$(basename "${f%.zst}")" ;;
	*) cp "$f" "$DST/" ;;
	esac
done
for f in modules.order modules.builtin modules.builtin.modinfo; do
	[ -e "$SRC/$f" ] && cp "$SRC/$f" "$DST/"
done
depmod -b "$ROOT" "$REL"
echo "release $REL: $(ls "$DST"/*.ko | wc -l) modules, $(du -sh "$DST" | cut -f1)"
