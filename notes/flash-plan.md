# Flash plan for the LTE Nexus 9

A rehearsal, written before touching the device, so the sequence is followed
rather than improvised. **Nothing here has been run.**

## Artifacts

| File | Size | SHA-256 |
|---|---|---|
| `boot-lte-6.19.img` | 10,885,376 | `118343377bd233102be4f6340a47a8f74046501c924b9f5d64a569c3776e5bb3` |
| `boot-lte-6.19-gfx.img` | 11,327,744 | `f4d0d7e8bdf482415b76ccab43cdbc59711a5bfd11feee042c9dc5638921a850` |
| `boot-stock-lte-N4F27P.img` | 8,829,440 | `eb20376b9748de1ac52b0bdd49f5f1d96e97418e5e02c314b2d644b624b871f9` |

All in `~/Downloads/nexus9/bootimg-build/`. All three carry the stock ramdisk
unchanged (`8c7e5b8a11f447999f884cb5a4e59be4b40f28b7eafd3c4649cf4ab628142a6b`).

## Before starting

- **Battery.** The tablet was deeply discharged — the two-blink LED is that
  signal. It must be able to run its USB peripheral.
- **A data cable**, not a charge-only one. A charge-only cable gives *zero* USB
  bus activity: no enumeration, no error, nothing in `dmesg`.
- **A laptop port, not a hub.** Through the monitor's hub the device failed with
  `device descriptor read/64, error -32` and `device not accepting address`,
  which is what underpowering looks like.

## Step 0 — back up the boot partition

**Do not skip, and this has now been done.** The tablet runs LineageOS, and
flashing replaces its boot partition. `boot-stock-lte-N4F27P.img` is *not* a true
restore — it is Google's stock kernel *and* ramdisk.

Corrected 2026-10-17 against the actual device, because the paths below differ
from what this plan originally said:

- The ROM is **LineageOS 16.0** (`16.0-20241220-UNOFFICIAL-flounder`), not 14.1.
- There is **no `/dev/block/bootdevice/by-name/`**. This device uses HTC-style
  partition names under `/dev/block/platform/sdhci-tegra.3/by-name/`, and the
  boot partition is **`LNX`** = `/dev/block/mmcblk0p16`, 32 MiB.
- `adb root` needs **Developer options → Root access** enabled first. Without it
  the daemon says "root access is disabled by system setting".
- The tablet's `dd` is toybox: use `bs=1048576`, not `bs=1M`.

```sh
adb devices            # confirm the tablet is listed
adb root               # restarts adbd as root; dd needs it for a block device
adb shell 'dd if=/dev/block/mmcblk0p16 of=/sdcard/boot-backup.img bs=1048576'
adb pull /sdcard/boot-backup.img
```

That produced `boot-backup-lineage16.img`, sha256
`b26351cb47efbad150a046a3a9bb2a1d677547723c76a155a084e3ad729fbc7e`. It has been
restored once and read back over `adb` to confirm the partition matches it
exactly, so the restore path is proven rather than assumed.

## Step 1 — reach fastboot

Hold **Power + Volume Down** for about 10 s. The bootloader screen appears.
Confirm the laptop sees it:

```sh
fastboot devices
```

## Step 2 — check it fits, before writing anything

```sh
fastboot getvar partition-size:boot
```

Expect a value comfortably above 11,327,744. If it is smaller, the graphics image
will not fit and we stop.

## Step 3 — flash the minimal image **first**

This is the deliberate order. It changes the least: it proves the bootloader
accepts our device tree without also risking the display bring-up.

```sh
fastboot flash boot boot-lte-6.19.img
fastboot reboot
```

**What to look for.** The command line carries `console=tty0`, so a kernel that
starts prints its log onto the screen. Visible kernel text is success. The
bootloader's own complaint, or a screen that never changes, is failure — and in
that case consult `notes/evidence.md`: `hboot` prints `Can not find a compatible
dtb image` when it rejects the tree.

## Step 4 — only then the graphics image

```sh
fastboot flash boot boot-lte-6.19-gfx.img
fastboot reboot
```

**The risk, stated plainly.** `DRM_TEGRA` evicts the bootloader's framebuffer as
soon as any CRTC registers
(`drivers/gpu/drm/tegra/drm.c:1260`), and CRTCs come from display controllers
that probe from plain device tree nodes. So the framebuffer console is taken away
**whether or not the panel driver binds**. If the panel misbehaves, the screen
goes black with no console at all — which is why Step 3 exists and why the
minimal image is kept.

## Recovery

```sh
fastboot flash boot boot-stock-lte-N4F27P.img    # Google's LTE kernel
fastboot flash boot boot-backup.img              # your own dump, if Step 0 ran
fastboot reboot
```

## If the tablet never appears on the bus

Check in this order, and note what each rules out:

```sh
lsusb | grep -iE '0bb4|18d1'    # HTC / Google vendor IDs; empty = not enumerating
dmesg | tail -30                # any "new USB device" line?
```

- Nothing at all in `dmesg` → the cable is charge-only, or the device is not
  powered enough to run its peripheral.
- `error -32` / `error -71` lines → a power or signal-integrity problem; move off
  the hub, use a different cable or port.
- A device appears but `fastboot devices` is empty → it is enumerating as
  something other than a fastboot device; check the screen state.

## Observed state, 2026-10-16

The tablet has not enumerated on USB yet. What was actually seen, as opposed to
assumed:

- The tablet's LED blinks when plugged in, so the cable carries **power**.
- **No USB bus activity at all**: no HTC (`0bb4`) or Google (`18d1`) device, no
  line in `dmesg`, `fastboot devices` empty — across repeated checks and a
  90-second window in which the tablet was unplugged and replugged.
- The one enumeration failure on the same bus belonged to an unrelated LG
  monitor hub peripheral (`error -32`, `error -71`), which is what an
  underpowered hub port looks like, not what the tablet looks like.

Power without data is the signature of a **charge-only or damaged cable**. The
test that settles it: use the same cable with a different device that needs
data. If that one also only charges, the cable is proven.

## Still unproven, no matter how this goes

Nothing in this repository has ever run on this hardware. The boot gate is the
one claim with strong evidence behind it; the panel driver has never bound to a
panel. Treat Step 3 as the experiment and Step 4 as the follow-up, not as
things known to work.

## Installed-boot design (prepared 2026-10-19, not run)

Goal: boot Linux from flash so `fastboot boot` and a host are no longer
needed.

Artifacts ready on this machine:

| File | What |
|---|---|
| `/tmp/n9root.ext4` | 256 MB ext4, Alpine 3.24 aarch64 minirootfs + `/lib/modules/<release>` (21 modules) + brcm firmware |
| `/tmp/n9auto17-stripped.img` | current kernel + initramfs (wrapper stripped) |
| `~/Downloads/nexus9/boot-backup-lineage16.img` | stock boot, to restore |

Two obstacles:

1. **Mainline does not see the partitions.** The tablet's partition table is
   not at LBA1 (`gpt_sector=69631` in the bootloader cmdline) and Android has
   a bespoke parser for it. Until that is solved, `root=/dev/mmcblk0pXX`
   cannot work.
   Options
   a) teach the kernel/initramfs to find the GPT at sector 69631;
   b) keep the rootfs as a raw ext4 image at a fixed sector and loop-mount it
      from the initramfs (`losetup -o`, needs CONFIG_BLK_DEV_LOOP=y);
   c) flash the ext4 image to `cache` and still loop-mount it by offset.
2. **Android must survive.** `boot` is one-shot and restorable from the
   backup; `cache` is expendable (Android recreates it). `system`,
   `vendor`, `userdata` must not be touched.

Proposed sequence once the user approves flashing:
- `fastboot flash boot n9auto17.img` (wrapped image, *not* the stripped one)
- `fastboot flash cache n9root.ext4`
- boot, initramfs loop-mounts the cache offset and `switch_root`s.
- rollback: `fastboot flash boot boot-backup-lineage16.img`.
