#!/bin/bash
# Cross-build the patched Mesa (tegra + nouveau GPU on the Nexus 9) on the host, no root needed:
#   aarch64 Alpine v3.24 sysroot via x86_64 apk.static in a user namespace (--no-scripts),
#   Mesa 26.1.6 (sha512 checked against Alpine's APKBUILD) + patches/mesa/*.patch, clang/lld cross,
#   installed to /opt/mesa-n9 (staging: $W/dest). Deploy: tar -C $W/dest -czf mesa-n9.tgz opt; extract on the tablet at /.
# Needs: clang, lld, llvm-ar, bison, flex, curl, unshare; meson/ninja/mako from a venv (created here).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$HERE/../../.." && pwd)
W=${W:-/tmp/n9build/xbuild}; V=26.1.6; ALP=v3.24; A=https://dl-cdn.alpinelinux.org/alpine/$ALP
SHA512=6746b73f5b87e8ff3723eee586b4b5f033dbe6d13cd0309d743b7fa484c350268859ec8ff21aadcbca7a04070cdaa7828146dd28dde4b1935bb879891d687f0b
mkdir -p "$W" && cd "$W"
[ -x venv/bin/meson ] || { python3 -m venv venv && venv/bin/pip install -q meson ninja mako pyyaml packaging; }
if [ ! -x apkx/sbin/apk.static ]; then
	mkdir -p apkx; ver=$(curl -fsSL $A/main/x86_64/APKINDEX.tar.gz | tar -xzO APKINDEX | awk '$0=="P:apk-tools-static"{f=1} f&&/^V:/{print substr($0,3); exit}')
	curl -fsSL $A/main/x86_64/apk-tools-static-$ver.apk | tar -xzf - -C apkx 2>/dev/null || true
fi
if [ ! -d sysroot/usr/lib/pkgconfig ]; then
	mkdir -p sysroot/etc/apk/keys sysroot/etc/ssl
	cp /tmp/n9build/pmos/keys/*.pub sysroot/etc/apk/keys/	# from tools/pmos/build.sh
	cp /etc/ssl/certs/ca-certificates.crt sysroot/etc/ssl/cert.pem
	unshare -r apkx/sbin/apk.static --root "$W/sysroot" --arch aarch64 --initdb --no-scripts -U -X $A/main -X $A/community \
		add musl-dev linux-headers libdrm-dev wayland-dev wayland-protocols expat-dev zlib-dev zstd-dev libgcc libstdc++-dev gcc
fi
[ -f mesa-$V.tar.xz ] || curl -fsSLO https://archive.mesa3d.org/mesa-$V.tar.xz
echo "$SHA512  mesa-$V.tar.xz" | sha512sum -c -
rm -rf mesa-$V build dest; tar -xJf mesa-$V.tar.xz
for p in "$REPO"/patches/mesa/*.patch; do patch -d mesa-$V -p1 < "$p"; done
sed "s|@SYSROOT@|$W/sysroot|g" "$HERE/aarch64-alpine.cross.in" > aarch64-alpine.cross
install -m755 "$HERE/wayland-scanner-1.25" wayland-scanner-1.25
mkdir -p buildpc; printf 'wayland_scanner=%s\nName: Wayland Scanner\nDescription: host scanner as 1.25.0\nVersion: 1.25.0\n' "$W/wayland-scanner-1.25" > buildpc/wayland-scanner.pc
printf "[binaries]\nwayland-scanner = '%s'\n\n[built-in options]\npkg_config_path = ['%s']\n" "$W/wayland-scanner-1.25" "$W/buildpc" > native.ini
export PATH=$W/venv/bin:$PATH
(cd mesa-$V && meson setup "$W/build" --cross-file "$W/aarch64-alpine.cross" --native-file "$W/native.ini" --prefix=/opt/mesa-n9 \
	--buildtype=release -Dgallium-drivers=tegra,nouveau,softpipe -Dvulkan-drivers= -Dglx=disabled -Dplatforms=wayland \
	-Degl=enabled -Dgbm=enabled -Dgles1=disabled -Dgles2=enabled -Dopengl=true -Dllvm=disabled -Dvideo-codecs= \
	-Dgallium-va=disabled -Dteflon=false -Dtools= -Dlibunwind=disabled -Dvalgrind=disabled -Dzstd=enabled -Dexpat=enabled \
	-Dbuild-tests=false >/dev/null)
ninja -C build -j"$(nproc)" >/dev/null
DESTDIR=$W/dest ninja -C build install >/dev/null
tar -C dest -czf mesa-n9.tgz opt && echo "$W/mesa-n9.tgz"
