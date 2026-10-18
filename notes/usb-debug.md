# USB device mode — working state

Last updated: 2026-10-18 22:30 · branch `usb-bringup` · **solved, uncommitted**

## Status: solved

`g_serial` enumerates on the host:
```
usb 3-1: New USB device found, idVendor=0525, idProduct=a4a7
usb 3-1: Product: Gadget Serial v2.4
usb 3-1: Manufacturer: Linux 6.19.0-htc-flounder ... with tegra-usb
cdc_acm 3-1:2.0: ttyACM0: USB ACM device
```

## Root cause

The Nexus 9 reports VBUS through the PMIC (palmas/extcon), **not** through the
controller's OTGSC or the UTMIP VBUS comparators. The ChipIdea core therefore
never saw A-valid / A-session-valid and refused to drive the D+ pull-up: the
host saw no attach at all, and nothing else we configured mattered.

The vendor kernel solves this in its own UDC driver (`drivers/usb/gadget/
tegra_udc.c`, not chipidea's `udc.c`): when `support_pmu_vbus` is set
(board-flounder.c does), `dr_controller_run()` writes the VBUS sensor
register 0x404 with a software override before setting USBCMD.RS:

```c
v |= A_VLD_SW_VALUE | A_VLD_SW_EN | ASESSION_VLD_SW_VALUE | ASESSION_VLD_SW_EN;
```

That is bits 28/27/20/19. Mainline never did this.

## Fix (in tree)

- `ci_hdrc_tegra.c`: new `pmu_vbus` flag on the SoC info, set for the
  tegra124 UDC; `tegra_usb_notify_event()` writes the same override on
  `CI_HDRC_CONTROLLER_RESET_EVENT` (before RS is set).
- `ci_udc_pullup()` keeps SLOM clear (hboot does the same in device mode).

## Evidence

Working run at pullup, versus hboot's handoff state (same boot, full dump):

| reg | ours before fix | ours after fix | hboot |
|-----|-----------------|----------------|-------|
| 0x404 VBUS sensors | `0x00000006` | `0x18180004` | `0x00001804` |
| PORTSC | `0x4` (no CCS) | `0x5` (CCS) | `0x5` |
| DEVLC | `0x06000000` | `0x04000000` | `0x04000000` |

Other differences were all tuning/status and were proven irrelevant by cloning
them (hypothesis 6).

## Test harness (still useful)

- `n9.trigger`: glue probe returns -ENODEV at boot; userspace init mounts sysfs
  and binds `7d000000.usb` from a grandchild while a sibling rewrites the
  DTB-partition record every 2 s.
- `n9.reader`: prints PMC scratch breadcrumbs from the previous boot.
- `n9.dump`: early register dump (USB block + padctl + PMC).
- Record lives at sector 79872 of `mmcblk0` (start of the DTB partition);
  read it from Android with `adb exec-out dd if=/dev/block/mmcblk0 bs=512
  skip=79872 count=64` after `adb root`.
- Images built with `tools/bootimg-repack.py --append-cmdline ...`, strip the
  HTC wrapper (`tail -c +257`), `fastboot boot`. hboot ignores the image
  roughly half the time and boots Android instead: detect that by 18d1:4ee7
  appearing within ~35 s, and retry.
- A failed run often leaves the tablet hard-wedged (no USB, black or white
  screen). Only a power cycle recovers it.

## Dead ends — do not retry

- Padctl PORT_CAP / pad power-down writes (hboot leaves them set/default).
- DEVLC.STS, FUSE_ATERM_SEL, FS_PREABMLE_J.
- Cloning hboot's XCVR_CFG0/MISC_CFG0/XCVR_CFG1/USBMODE values.
- PMC AO/sleep/master: identical to hboot (`000ffff3 / c0c0c0c0 / 38000800`).
- Removing extcon, or relying on its notifier (the path is is_otg-gated).
- Reading the host's brief full-speed `-71` device as ours: it is Android's
  own boot gadget and appears on boots where hboot ignored our image.

## Serial console (working, use this instead of the record hack)

`tools/miniroot/init-shell.c` mounts devtmpfs/proc/sys, waits for
`/dev/ttyGS0`, and execs a busybox shell on it. Ramdisk build:

```sh
# static aarch64 busybox (Alpine)
curl -O https://dl-cdn.alpinelinux.org/alpine/latest-stable/main/aarch64/busybox-static-1.37.0-r31.apk
tar -xzf busybox-static-1.37.0-r31.apk       # -> bin/busybox.static

clang --target=aarch64-linux-gnu -fuse-ld=lld -nostdlib -static -O2 \
      -ffreestanding -fno-builtin -fno-stack-protector \
      -o init tools/miniroot/init-shell.c

mkdir -p rd/bin rd/dev rd/proc rd/sys rd/tmp
cp init rd/init; cp bin/busybox.static rd/bin/busybox
ln -s busybox rd/bin/sh
(cd rd && find . | cpio -o -H newc | gzip -9 > ../shell-ramdisk.gz)
```

Boot it with `--ramdisk shell-ramdisk.gz` and **no** `n9.trigger`, so the
controller probes normally. On the host:

```sh
sudo chmod 666 /dev/ttyACM0
(printf '\n'; sleep 0.5; printf 'uname -a\n'; sleep 2) | \
    socat - /dev/ttyACM0,raw,echo=0,crnl
```

First shell session: run `/bin/busybox --install -s /bin` once so applet
symlinks exist (the ramdisk only ships `bin/sh`).

Verified: `uname -a` reports 6.19.0-htc-flounder aarch64, uid=0, the tablet
stays up (no wedge) with the gadget connected.

## Next actions

1. Commit the console harness; it replaces the record hack for day-to-day work.
2. Next feature: WiFi, then touch, then audio — check whether the drivers are
   modules that need to be in the ramdisk/rootfs.
3. Optional: wire the VBUS override to a DT property instead of a SoC flag and
   send the patch upstream.
