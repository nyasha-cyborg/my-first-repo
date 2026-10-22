#!/bin/sh
# Build the postmarketOS root filesystem ON THE TABLET (native aarch64: no host root, no qemu).
# Runs in the n9 installer ramdisk (busybox, root, WiFi up). Needs /bin/apk.static and /etc/n9-apk-keys/*.pub.
# Writes only /data/pmos/rootfs.img inside Android's userdata (mmcblk0p31, mounted rw at /data).
# Re-runnable: an existing image is reused and apk just completes the install.
#   PMOS=v26.06 ALP=v3.24 SIZE_MB=12288 PKGS="..." install-rootfs.sh
# Then the host streams the overlay (kernel modules, firmware, modem service) with tools/pmos/push-overlay.sh,
# and finish-rootfs.sh does users/services/WiFi.
set -e
PMOS=${PMOS:-v26.06}
ALP=${ALP:-v3.24}
SIZE_MB=${SIZE_MB:-12288}
M=https://mirror.postmarketos.org/postmarketos/$PMOS
A=https://dl-cdn.alpinelinux.org/alpine/$ALP
PKGS=${PKGS:-"postmarketos-base device-htc-flounder device-htc-flounder-nonfree-firmware postmarketos-ui-phosh
	mesa-dri-gallium mesa-egl mesa-gles kmscube mpv yt-dlp firefox alsa-utils alsa-ucm-conf
	networkmanager-wifi wpa_supplicant e2fsprogs htop"}
APK="/bin/apk.static -U --arch aarch64 --keys-dir /etc/n9-apk-keys --no-progress --timeout 120"
R=/mnt/pmos
say() { echo "pmos-install: $*"; }

# the test init's DHCP hook writes "nameserver A B" on one line, which no resolver parses: one per line
ns=$(sed -n 's/^nameserver//p' /etc/resolv.conf 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9.]+$' | awk '!s[$0]++')
[ -n "$ns" ] || ns=1.1.1.1
for n in $ns; do echo "nameserver $n"; done > /etc/resolv.conf

mkdir -p /data /tmp/e2fs $R
grep -q " /data " /proc/mounts || mount -t ext4 -o noatime /dev/mmcblk0p31 /data
mkdir -p /data/pmos
say "userdata mounted, $(df -m /data | awk 'NR==2{print $4}') MiB free"
# evidence that survives a reset (one install was cut by a watchdog reset): kernel log + memory every 10 s
if [ ! -f /tmp/n9-installlog.pid ]; then
	(cat /proc/kmsg >> /data/pmos/install-kmsg.log) </dev/null >/dev/null 2>&1 &
	(while true; do echo "$(cat /proc/uptime) $(grep -E '^(MemFree|MemAvailable|Dirty):' /proc/meminfo | tr -s ' ' | tr '\n' ' ') load $(cut -d' ' -f1-3 /proc/loadavg)" >> /data/pmos/install-mem.log; sync; sleep 10; done) </dev/null >/dev/null 2>&1 &
	echo $! > /tmp/n9-installlog.pid
fi

# apk.static (OpenSSL) reads /etc/ssl/cert.pem relative to --root: give every target root a copy
certs() { mkdir -p "$1/etc/ssl"; cp /etc/ssl/cert.pem "$1/etc/ssl/cert.pem"; }

# 1. e2fsprogs in a throwaway staging root (busybox has no mke2fs)
if [ ! -x /tmp/e2fs/sbin/mke2fs ]; then
	certs /tmp/e2fs
	$APK --root /tmp/e2fs --initdb -X $A/main add e2fsprogs > /tmp/e2fs.log 2>&1 || { tail -5 /tmp/e2fs.log; exit 1; }
fi

# 2. the image file (sparse) + ext4
if [ ! -f /data/pmos/rootfs.img ]; then
	dd if=/dev/zero of=/data/pmos/rootfs.img bs=1M count=0 seek=$SIZE_MB 2>/dev/null
	mkdir -p /tmp/e2fs/data
	mount -o bind /data /tmp/e2fs/data
	chroot /tmp/e2fs /sbin/mke2fs -F -q -t ext4 -L pmOS_root /data/pmos/rootfs.img
	umount /tmp/e2fs/data
	say "created /data/pmos/rootfs.img (${SIZE_MB} MiB, ext4)"
fi
if ! grep -q " $R " /proc/mounts; then
	# a reset mid-install leaves the image dirty: repair before mounting
	mkdir -p /tmp/e2fs/data; grep -q " /tmp/e2fs/data " /proc/mounts || mount -o bind /data /tmp/e2fs/data
	chroot /tmp/e2fs /sbin/e2fsck -p /data/pmos/rootfs.img || chroot /tmp/e2fs /sbin/e2fsck -fy /data/pmos/rootfs.img || true
	umount /tmp/e2fs/data
	L=$(losetup -f)
	losetup $L /data/pmos/rootfs.img
	mount -t ext4 -o noatime $L $R
fi
for d in dev proc sys; do
	mkdir -p $R/$d
	grep -q " $R/$d " /proc/mounts || mount -o bind /$d $R/$d
done

# 3. packages
certs $R
mkdir -p $R/etc/apk/keys
cp /etc/n9-apk-keys/* $R/etc/apk/keys/
printf '%s\n' "$M" "$A/main" "$A/community" > $R/etc/apk/repositories
cp /etc/resolv.conf $R/etc/resolv.conf 2>/dev/null || echo "nameserver 1.1.1.1" > $R/etc/resolv.conf
[ -f $R/lib/apk/db/installed ] || $APK --root $R --initdb add alpine-baselayout > /tmp/apk.log 2>&1
# our kernel replaces linux-htc-flounder (the yuka/linux package device-htc-flounder depends on)
$APK --root $R add -t linux-htc-flounder >> /tmp/apk.log 2>&1 || true
say "installing packages (log /tmp/apk.log)"
$APK --root $R add $PKGS >> /tmp/apk.log 2>&1 && say "packages installed" || { say "apk add failed"; tail -15 /tmp/apk.log; exit 2; }
say "rootfs uses $(du -sm $R 2>/dev/null | cut -f1) MiB"
