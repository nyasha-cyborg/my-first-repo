# Reading a kernel log off the Nexus 9

Written 2026-10-17, after the first successful capture. Until this existed every
bring-up question was guesswork: the panel never lights, so there is no console,
and the kernel cannot be asked anything directly. This is the channel that
finally worked.

## Why the obvious approaches all failed

- **Serial.** The debug UART is on test pads; nothing is attached.
- **Framebuffer console.** `simple-framebuffer` was not registering (see below),
  and once DRM probes it evicts the bootloader framebuffer anyway.
- **USB.** The Tegra xUDC driver is a module (`CONFIG_USB_TEGRA_XUDC=m`) and no
  `usb@70090000` node exists in the flounder tree, so there is no gadget.
- **An eMMC partition.** This looked like it failed — three attempts wrote
  nothing — but the write was not the problem. See the device-tree bug below.

## The channel

A freestanding aarch64 `init` in the initramfs (`tools/miniroot/init.c`):

1. mounts devtmpfs and proc,
2. waits 15 s for host1x, DSI and the panel to probe or fail,
3. reads `/dev/kmsg` into a buffer,
4. writes a record to the start of the **DTB partition** (`mmcblk0p5`,
   sector 79872), `fsync`s it, and reboots.

The record is little-endian:

    "N9LOG2\n"  u64 length  u64 flags  log bytes

`flags` reports how far it got, which is what makes a failed run diagnosable at
all: `0x001` kmsg opened, `0x002` block device opened, `0x004` node had to be
`mknod`ed, `0x008` written to the raw disk at the DTB offset instead of to a
partition, `0x100` started, `0x200` mounted, `0x400` slept, `0x800` read.

Reading it back: boot Android, then

```sh
adb root
adb shell 'dd if=/dev/block/mmcblk0p5 of=/data/local/tmp/n9log.bin bs=1048576 count=1'
adb pull /data/local/tmp/n9log.bin
```

Deliberate details, each of which cost a round trip:

- **`fsync` before `reboot`.** Writes to a block device are buffered and
  `RB_AUTOBOOT` does not flush them. The first attempts wrote the record and
  then discarded it.
- **`mknod` the node instead of trusting devtmpfs.** Cheap insurance; devtmpfs
  turned out to be fine once the device tree was valid.
- **The raw-disk fallback.** Writing to `/dev/mmcblk0` at the DTB partition's
  byte offset needs neither devtmpfs nor a parsed partition table.

The DTB partition is a safe target: it was 4 MiB of zeros, hboot falls back to
the DTB appended to the kernel, and flashing `boot` never touches it.

## The bug that made every earlier image lie

`tools/bootimg-repack.py --ramdisk` patched the new `ramdisk_size` into the
header **after** the image had been assembled, using `len(out) - len(header)` as
the offset. By then that offset pointed at the last 2048 bytes of the appended
DTB, not at the header — so every image built with a custom ramdisk had its
device tree's **string table overwritten by the boot header**.

The damage did not look like corruption. The kernel reported:

    Duplicate name in mmc@700b0000, renamed to "#1"      (and #2, #3)
    Duplicate name in framebuffer@ac001000, renamed to ...
    simple-framebuffer ac001000.framebuffer: Can't parse width property
    tegra-dsi 54400000.dsi: could not get #nvidia,mipi-calibrate-cells
    gpio-keys gpio-keys: probe with driver gpio-keys failed with error -22
    tegra-xusb-padctl 7009f000.padctl: ... failed with error -22

All of it was missing property *names*, not missing properties. The fix keeps
the header final before appending and the tool now checks that each input DTB
survives byte-for-byte (`src in out`), because counting FDT magics passed the
corrupted images happily.

## What the first honest log says

Captured 2026-10-17 from `boot-lte-6.19-logd6.img` (DRM kernel, correct DTB):

- **eMMC works.** `mmc0: new HS200 MMC card`, `mmcblk0: mmc0:0001 BWBC3R 29.1
  GiB`, all 33 partitions. `Primary GPT is invalid, using alternate GPT.` The
  earlier theory that mainline lacks an HTC partition parser was wrong; the
  partitions were only missing because the DTB was corrupt.
- **Framebuffer works.** `simple-framebuffer: fb0: simplefb registered!`,
  1536×2048×32 at `0xac001000`, line length 6144. It is correct in the tree;
  DRM then evicts it (`aperture_remove_conflicting_devices`), which is expected
  and also produces a cosmetic `regulator_put` warning.
- **DRM and the panel bind**, but the physical layer fails:
  `tegra-dsi 54400000.dsi: MIPI calibration failed: -110` (ETIMEDOUT), and
  consequently `panel-jdi-lpm089a128a 54300000.dsi.0: sending dcs data 51 e0
  failed: -110`.

`-110` is the next problem to solve: calibration is polling
`MIPI_CAL_STATUS_DONE` for 250 ms and never seeing it.

Still failing, lower priority: `tegra124-dfll` (-22, so cpufreq is deferred),
`tegra-phy`/`tegra-xusb-padctl` (-22 and -517, so USB is dead),
`gpio-keys` (-22). The USB one matters for a second reason: a working gadget
would be a far better console than this partition dance.

## Display, round two: the DSI-B pad mask

With the device tree intact, MIPI calibration still failed with `-110`, but on
`54400000.dsi` rather than on the panel. `tegra_mipi_start_calibration()` walks
`tegra124_mipi_pads[]` and selects a pad only when `device->pads & BIT(i)`. That
table has seven entries -- CSIA, CSIB, CSIC, CSID, CSIE, DSIA, DSIB -- so
`dsib`'s `nvidia,mipi-calibrate = <&mipi 0x180>` asked for bits 7 and 8, **which
do not exist**. No pad was selected, so calibration could never complete. The
board's DSI-B is the second link of a ganged pair on the same DSIA/DSIB pads, so
it now uses `0x060` like DSI-A. Calibration completes immediately afterwards.

The shipped kernel's `tegra_dsi_mipi_calibration_13x()` also sets
`MIPI_CAL_CLKEN_OVR`, while upstream's `tegra132_mipi_soc` says
`clock_enable_override = false`. That was changed to true; whether it is
strictly required is not yet isolated.

## Where it stands

After both fixes the log contains exactly one error:

    panel-jdi-lpm089a128a 54300000.dsi.0: sending generic data b0 04 failed: -110

The panel is powered (`avdd-supply`, `iovdd-supply`, `dcdc-en-gpios`,
`reset-gpios` and `link2` are all present in the device tree), the PHY
calibrates, and DRM registers `tegradrmfb`. What still fails is the panel's very
first generic command, which means command traffic is not getting an answer from
the panel.

## Two things that make iteration cheap now

- **`fastboot boot <image>`** loads the kernel into RAM without writing flash.
  After the diagnostic init reboots, hboot boots the untouched LineageOS image,
  Android comes back on its own, and the log can be pulled -- no flashing, no
  restore, no button presses. A full experiment is about 90 seconds.
- The `-110` investigations above were resolved by reading the *shipped* kernel
  with REA rather than by guessing: `tegra_dsi_mipi_calibration_13x()` and the
  `clk72mhz` dependency were both found that way.

## The last error: the DSI host never transmits

Everything else probes. What remains is that the panel's first command never
leaves the controller:

    panel-jdi-lpm089a128a 54300000.dsi.0: sending generic data b0 04 failed: -110

`tegra_dsi_transmit()` sets `DSI_TRIGGER_HOST` and polls until the bit clears.
It never clears. Instrumenting the timeout path gave, on this board:

    pad0=00000000 pad1=00000000 pad2=00077110 pad3=00003333 pad4=00000000
    hostctl=00002003
    power=00000001 ctrl=00000001 status=00000000 trigger=00000002 int=00000000

Read: the host is enabled and powered, the PHY pad control is programmed the way
`tegra_dsi_pad_calibrate()` programs it, there are no status errors -- and the
trigger simply never completes.

Two things were tried and both changed nothing, which is worth recording:

- **Enabling `MIPI_CAL_CLKEN_OVR`** (done, kept -- it matches the shipped
  kernel) did fix calibration, but not this.
- **Moving `drm_panel_prepare()` after `tegra_dsi_configure()`**, on the theory
  that the controller had to be programmed before commands could be sent. The
  shipped kernel does `tegra_dsi_init_hw()` before sending panel commands, so
  this looked right. It moved the failure earlier (8.9 s instead of 14.7 s) and
  did not fix it. The change was reverted.

The published register values are the starting point for the next attempt:
compare them against what the shipped `tegra_dsi_init_hw()` leaves in the same
registers. That function is in `~/Downloads/nexus9/kernel-analysis/`
(`dsi-downstream.c`), and the shipped kernel can be searched with REA
(`kernel-lte.elf`, `search_strings` for `tegra_dsi_init_hw`).

## A visible console, today

Dropping `CONFIG_DRM_TEGRA` is enough to get an actual picture on the panel. The
bootloader leaves a live framebuffer at `0xac001000` and `simple-framebuffer`
registers against it; the only reason the screen is black otherwise is that
`tegra-drm` evicts that framebuffer (`aperture_remove_conflicting_devices`) and
then fails to programme the DSI, leaving nothing on screen.

With `DRM_TEGRA=n` and `console=tty0`, the kernel log appears on the panel at its
native 1536x2048 -- small text, but real output. That proves the panel, the
bootloader handover and fbcon all work; what does not work is the DRM/DSI path
that would replace them.

Reproduce with:

```sh
scripts/config --file "$OUT/.config" -d DRM_TEGRA
make O="$OUT" ARCH=arm64 LLVM=1 olddefconfig Image
python3 tools/bootimg-repack.py --stock <stock> --image "$OUT/arch/arm64/boot/Image" \
    --dtb "$OUT/arch/arm64/boot/dts/nvidia/tegra132-flounder.dtb" \
    --ramdisk <logdump-initramfs> -o boot-fbcon.img
fastboot boot boot-fbcon.img
```

This is a diagnostic configuration, not the target: it gives a console, not a
display driver.
