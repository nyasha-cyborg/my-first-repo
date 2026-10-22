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
- 11:47 first install attempt cut by a watchdog reset at package ~670 (installer image armed the 90 s watchdog;
  most likely the test init's busybox feeder died under load). Installer now: no watchdog cmdline, e2fsck before
  remount, kmsg + memory logs on userdata. Second run: 872 packages, 1.59 GB; only error = postmarketos-mkinitfs
  trigger (no pmOS kernel package; we use our own boot image) — harmless.
- 12:03 **pmOS v26.06 boots** (`fastboot boot n9pmos-boot`): OpenRC up, NetworkManager joined WiFi (192.168.1.109),
  sshd (key only), elogind, bluetooth, zram, root autologin on ttyGS0.
- greetd crashed, two causes, both fixed (baked into finish-rootfs.sh):
  1. `libseat: No backend was able to open a seat` -> `apk add seatd seatd-openrc`, enable seatd, greetd + user in `seat`.
  2. phoc segfaults in the GPU path (Mesa 26.1.6 `tegra` renderer, GLES 3.2, crashes on the first draw; `kmscube -D
     /dev/dri/card0` too; plain `kmscube` picks card1 = nouveau without connectors). Workaround: software rendering via
     `/etc/environment` (greetd gives the greeter a clean PAM env, conf.d exports don't reach it):
     `GBM_ALWAYS_SOFTWARE=1 LIBGL_ALWAYS_SOFTWARE=1 WLR_RENDERER=pixman` (phoc's GLES renderer fails on software GBM
     and falls back to Vulkan -> pixman for the compositor, llvmpipe for apps; kmscube on llvmpipe renders fine).
- 12:13 greetd started, phoc + phrog running -> Phosh lock screen expected on the panel.
- Access: `ssh user@<ip>` and `ssh root@<ip>` with the laptop key only (PermitRootLogin prohibit-password).
- `openssh` in PKGS pulled the non-PAM sshd (pmOS's `UsePAM` policy line then errors, sshd still works): removed from PKGS.
- `n9-modem` service: stopped at boot — not looked at yet.
- 12:25 first boot hung ~2 min after greetd started (mode B: gadget enumerated, no shell, no WiFi); no watchdog in that
  boot -> power cycle. Now: watchdog armed + fed, kernel log in /var/log/kmsg.log (5 s sync), greetd opt-in.
- 12:50 second boot stable. User saw the text console (fbcon works). kmscube (llvmpipe) on card0: **cube visible** —
  KMS scanout works (it quit after <1 s only because its stdin was closed: run it as `sleep 40 | kmscube ...`).
- 12:56 greetd started by hand: phoc + gnome-session (non-systemd fallback) + phosh-osk-stevia + phrog. **The user saw
  the PIN screen, typed 147147 with the touch keyboard and logged in** (slow, software rendering). Phosh session
  c16 on seat0/tty7: phoc, gnome-session --session=phosh, phosh. Touch works. greetd autostart re-enabled.
- The 12:25 hang is unexplained (no log); kmsg.log now keeps evidence if it recurs.
