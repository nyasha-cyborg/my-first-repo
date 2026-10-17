#!/usr/bin/env bash
#
# setup.sh — reproduce the flounder kernel tree from this repository alone.
#
# Clones the upstream kernel this port is built against, pins it to the exact
# commit the patches here were made against, and applies them. The kernel is a
# build input, not part of this repository, so it is never vendored in.
#
# Usage:
#   ./setup.sh                 # prepare the tree only
#   ./setup.sh --build         # prepare, then build dtbs and Image
#   ./setup.sh DEST OUT        # choose where the tree and build output go
#
set -euo pipefail

# --- pinned upstream -------------------------------------------------------
KERNEL_UPSTREAM="https://cyberchaos.dev/yuka/linux.git"
KERNEL_BRANCH="flounder"
KERNEL_COMMIT="38ff68627120b204b30d030e5f4dd7d1ee33acc3"

# Directory this script lives in, so it works from anywhere.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BUILD=0
if [ "${1:-}" = "--build" ]; then
    BUILD=1
    shift
fi

DEST="${1:-$PWD/linux-flounder}"
OUT="${2:-$PWD/linux-flounder-out}"

# --- never clobber existing work -------------------------------------------
for path in "$DEST" "$OUT"; do
    if [ -e "$path" ]; then
        echo "error: $path already exists; refusing to touch it" >&2
        exit 1
    fi
done

# --- clone, shallow, pinned to the exact commit ----------------------------
echo "==> cloning $KERNEL_UPSTREAM (branch $KERNEL_BRANCH)"
git clone --branch "$KERNEL_BRANCH" --single-branch --depth 1 \
    "$KERNEL_UPSTREAM" "$DEST"

# Upstream moves on. If the branch tip is no longer the pinned commit, ask for
# that commit explicitly and detach onto it. If the server refuses to serve an
# arbitrary commit, run `git -C "$DEST" fetch --unshallow` first and retry.
if [ "$(git -C "$DEST" rev-parse HEAD)" != "$KERNEL_COMMIT" ]; then
    echo "==> branch tip has moved; fetching pinned commit"
    git -C "$DEST" fetch --depth 1 origin "$KERNEL_COMMIT"
    git -C "$DEST" checkout --detach "$KERNEL_COMMIT"
fi

# --- apply this repository's changes ---------------------------------------
# flounder-lte-and-display.patch is the cumulative patch. It already carries the
# DTS `compatible` fix, so dts-compatible-flounder64-lte.patch is kept only as a
# record of that one-line change and is deliberately not applied here.
echo "==> applying patches/flounder-lte-and-display.patch"
git -C "$DEST" apply --verbose \
    "$REPO_ROOT/patches/flounder-lte-and-display.patch"

# Stacks on top of the cumulative patch above; it is the rt5677 sound node,
# not a replacement for anything in it.
echo "==> applying patches/flounder-audio.patch"
git -C "$DEST" apply --verbose \
    "$REPO_ROOT/patches/flounder-audio.patch"

# Independent of the two above. Three compatibles in the SoC dtsi that the
# bindings document as two-element lists but the file supplies as one-element
# ones; see notes/schema-check.md.
echo "==> applying patches/tegra132-compatible-fallbacks.patch"
git -C "$DEST" apply --verbose \
    "$REPO_ROOT/patches/tegra132-compatible-fallbacks.patch"

# The PMC node had no "scratch" aperture, so tegra-pmc never registered its
# reboot notifier and `reboot bootloader` was silently a plain reboot. Without
# this a diagnostic kernel can only loop, never hand control back to fastboot.
echo "==> applying patches/tegra132-pmc-scratch.patch"
git -C "$DEST" apply --verbose \
    "$REPO_ROOT/patches/tegra132-pmc-scratch.patch"

# Applies on top of the audio patch, since both touch the same file.
echo "==> applying patches/flounder-bluetooth.patch"
git -C "$DEST" apply --verbose \
    "$REPO_ROOT/patches/flounder-bluetooth.patch"

# --- install the kernel config ---------------------------------------------
echo "==> installing configs/flounder_defconfig"
cp "$REPO_ROOT/configs/flounder_defconfig" \
    "$DEST/arch/arm64/configs/flounder_defconfig"

# --- done ------------------------------------------------------------------
JOBS="$(nproc)"
echo
echo "Tree ready at: $DEST"
echo
echo "Build with:"
echo "  make -C $DEST O=$OUT ARCH=arm64 LLVM=1 -j$JOBS dtbs"
echo "  make -C $DEST O=$OUT ARCH=arm64 LLVM=1 -j$JOBS Image"
echo
echo "Build only 'dtbs' after a device-tree change: it takes seconds, whereas"
echo "'Image' rebuilds the kernel."

if [ "$BUILD" = 1 ]; then
    echo
    echo "==> building"
    make -C "$DEST" O="$OUT" ARCH=arm64 LLVM=1 -j"$JOBS" dtbs Image
fi
