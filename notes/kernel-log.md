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

## The DSI reset, which moved the failure

The bootloader draws its logo through this same DSI controller and leaves it
programmed for its own stream. `tegra_dsi_prepare()` only *deasserts* the module
reset in `runtime_resume()`; it never toggles it, so the controller keeps the
bootloader's state and refuses to act as a command host.

Asserting and deasserting the reset at the top of `tegra_dsi_prepare()` moved the
failure from the panel's **first** command to a much later one:

    before:  sending generic data b0 04 failed: -110
    after:   sending dcs data 51 e0 failed: -110

Everything up to brightness now gets through, so panel init genuinely runs. The
remaining timeout is on DCS 0x51, and only on the write that the backlight device
issues *after* video streaming has started -- a command cannot be injected into a
running stream. Two follow-ups were tried and did **not** fix it, and are not in
the patches: keeping `MIPI_DSI_MODE_LPM` set permanently, and sending a brightness
value from `prepare()` before the stream starts.

The next thing to try is the approach the downstream driver takes: stop the DC
stream at a frame boundary before any command, then resume it
(`tegra_dsi_stop_dc_stream_at_frame_end` in `dsi-downstream.c`).

## The panel now initialises cleanly

With the module reset in place, the last remaining `-110` was the backlight
write. REA found the reason: `tegra_dsi_set_to_lp_mode()` in the shipped kernel
switches to HS host mode, **stops the DC stream at a frame end**, waits frames,
and only then goes to LP. Mainline never stops the stream, so a command issued
while streaming is accepted and then never transmitted.

Rather than rework mainline's streaming path, the panel driver now latches the
requested brightness and writes DCS 0x51 from `prepare()`, while the link is
still idle, and skips writes once streaming has begun.

Result: **no display errors at all** in the boot log. The panel init sequence,
including display-on and brightness, completes. `tegradrmfb` registers.

The screen is still black, so what remains is the video path itself -- the
framebuffer is registered but the panel is not being fed pixels. Note that the
same panel *does* light up and paint fbcon when `DRM_TEGRA=n`, so the hardware
and the backlight are proven; this is specific to the DRM video stream.

## Video stream: what has been ruled out

With the command path fixed the panel initialises cleanly, but no image appears.
Things tried and **ruled out** (reverted, so they are not in the patches):

- **Sync-pulse video mode.** Adding `MIPI_DSI_MODE_VIDEO_SYNC_PULSE` changes the
  packet sequence from sync events to sync pulses. Boot log stayed clean; still
  no image.
- **Mode flags in general.** The panel does declare `MIPI_DSI_MODE_VIDEO` and
  `MIPI_DSI_CLOCK_NON_CONTINUOUS` at attach, so `tegra_dsi_configure()` is not
  falling back to command mode.

Also learned, and worth not repeating: **reading DSI registers inline from
`encoder_enable` deadlocks the DSI block.** It hangs before userspace ever runs,
which looks exactly like "the kernel did not boot". Any further register
inspection has to be deferred to a workqueue.

REA's limits hit here too: `search_strings` works against the shipped kernel for
messages and names, but `xrefs` on the DSI strings resolve to nothing, so the
video path cannot be followed from the image. `dsi-downstream.c` is the only way
to read those functions.

## The video stream: nailed down to the display controller

A deferred (workqueue) register dump, one second after streaming starts, settles
where the pixels stop:

    DSI:  status=00000400 power=00000001 control=00103032 host=00000020
          ganged=00000001 start=00000000 size=03000300
    DC:   winopt=20000000 displaycmd=00000020

Read as: `status` is `DSI_STATUS_IDLE` (bit 10) with **no** underflow or
overflow; `control=0x103032` is video mode enabled, 4 lanes (`LANES(3)`),
RGB888, with `SOURCE(pipe)`; `ganged=1` with `size=0x03000300` (768 per link,
i.e. the 1536-wide panel split across two links); `winopt=0x20000000` is
`DSI_ENABLE`; `displaycmd=0x20` is `DISP_CTRL_MODE_C_DISPLAY`.

So the panel is initialised, the link is configured and ganged correctly, and
the display controller says it is in continuous-display mode -- but the DSI is
**idle**, meaning no pixel data is arriving from the DC. The remaining fault is
in the DC's window/plane programming, not in DSI, the PHY or the panel.

Also ruled out along the way: full backlight (brightness 255) and painting the
DRM framebuffer solid white through `/dev/fb0`. Neither produced any light, which
is consistent with the DC never sending frames -- and it rules out the
"backlight is off" explanation.

The framebuffer-painting diagnostic is still in `tools/miniroot/init.c` because
it is cheap and will be the quickest confirmation once the DC is fixed.

## Probing the window registers hangs, which is itself the clue

Reading the DC-wide registers from the deferred work is safe
(`DC_DISP_DISP_WIN_OPTIONS`, `DC_CMD_DISPLAY_COMMAND` both returned values), but
adding the **window A** registers -- `DC_WIN_WIN_OPTIONS`,
`DC_WINBUF_START_ADDR`, `DC_WIN_LINE_STRIDE` -- hangs the kernel before
userspace starts. The log then simply does not update, which reads like "the
kernel did not boot" and is easy to misdiagnose a second time.

A window block that cannot be read behaves like one that was never powered or
clocked, which matches the DSI being idle: `tegra_plane_setup()` writes
`WIN_ENABLE` into `DC_WIN_WIN_OPTIONS` (dc.c, around the `value = WIN_ENABLE`
line), and if that never ran for the fbdev plane the DSI would have nothing to
transmit.

So the next thing to check is the plane path rather than the DSI: whether
`tegra_plane_setup()`/`tegra_plane_atomic_update()` runs for the fbdev
framebuffer, and what `tegra_dc_commit()` is being asked to latch.

Diagnostic technique that works and does not hang: dump DC-wide registers from a
delayed work; read window registers **only** if a follow-up probe shows the
window block is alive (e.g. by writing and reading back a scratch register),
because a hung read costs a full boot cycle and looks exactly like a boot failure.
