# postmarketOS install (rootfs image in Android's /data)

Decisions (user, 2026-10-23): keep LineageOS; pmOS root filesystem = ext4 image file `/data/pmos/rootfs.img` inside
userdata (`UDA` = mmcblk0p31, 25.6 GB, **not encrypted**: plain names, mountable from mainline); only `LNX`
(boot, mmcblk0p16) gets flashed at the very end, after asking. Boot backup `b26351cb…`, restore proven.
Until then everything is tested with `fastboot boot`.

## Layout

| Piece | What |
|---|---|
| `tools/pmos/build.sh` | host: installer image `n9pmos-inst`, pmOS boot image `n9pmos-boot`, `overlay.tgz` |
| `tools/pmos/install-rootfs.sh` | tablet (installer ramdisk): mke2fs via apk-staged e2fsprogs, `apk.static` pmOS v26.06 + Alpine v3.24 |
| `tools/pmos/push-overlay.sh` | host -> tablet over WiFi: modules, firmware, LTE modem service + firmware, ssh key |
| `tools/pmos/finish-rootfs.sh` | tablet: user `user` (screen PIN 147147, pmbootstrap default — change it), SSH key-only (no password, no root), services, ttyGS0 root autologin (USB only), WiFi |
| `tools/pmos/init` | pmOS boot ramdisk: busybox, mounts UDA, loop-mounts the image, `switch_root` to OpenRC; rescue shell on ttyGS0 |

- No pmbootstrap: it needs sudo (password on this host). The rootfs is built on the tablet with `apk.static` (native
  aarch64, scripts run for real). Package signatures verified with alpine-keys + postmarketos-keys fetched by build.sh.
- `device-htc-flounder` (v5, still in v26.06) gives the deviceinfo/firmware deps; its kernel dependency
  `linux-htc-flounder` (yuka/linux) is satisfied by an empty virtual package — our kernel/modules come from the overlay.
- OpenRC (main repo); systemd is only in pmOS `extra-repos/systemd`.
- pmOS boot cmdline drops the test images' `tegra_wdt.early_start=1 heartbeat=90` (nothing would feed it).

## Gotchas hit (2026-10-23)

- The test init's DHCP hook writes `nameserver A B` on one line -> no DNS. install-rootfs.sh normalises it.
- `apk.static` (OpenSSL) reads the CA file `/etc/ssl/cert.pem` **relative to `--root`**; `-U` needed on a fresh root.
- `linux-flounder-out` was stale (kernel.release regenerated without a rebuild): build.sh now checks the Image's
  `Linux version` string equals `make kernelrelease`.
- Modules are `.ko.zst` (`MODULE_COMPRESS_ALL`); the installer ramdisk gets uncompressed ones from stage-modules.sh.

## Status

- 11:40 installer `n9pmos-inst` booted (kernel gcfc538ce0338, WiFi 192.168.1.100), rootfs.img created (12 GiB),
  package install running.
