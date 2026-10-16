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

**Do not skip.** The tablet runs LineageOS. Flashing replaces the boot partition,
and `boot-stock-lte-N4F27P.img` is *not* a true restore — it is Google's stock
kernel *and* ramdisk, which is not what LineageOS is running.

If Android boots:

```sh
adb devices        # confirm the tablet is listed
adb root           # LineageOS 14.1 userdebug permits this
adb shell dd if=/dev/block/bootdevice/by-name/boot of=/sdcard/boot-backup.img
adb pull /sdcard/boot-backup.img
```

Reading these: `adb devices` lists attached devices · `adb root` restarts the
adbd daemon as root, which `dd` needs to read a block device · `adb shell dd …`
copies the `boot` partition to a file on the tablet's storage · `adb pull` copies
that file to the laptop.

If Android will not boot, proceed without a backup and accept that restoring
LineageOS may mean a full reinstall.

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
