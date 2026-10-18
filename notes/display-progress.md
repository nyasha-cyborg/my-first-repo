# Display bring-up progress (2026-10-17 late session)

Continuation of `kernel-log.md` / `display-port.md`. The panel is still black,
but most of the chain is now measured, and several assumptions were corrected.

## Corrected: the zero IOVA is not a bug

The previous handover said the plane's `iova == 0` looked unassigned. It is not:

- This SMMU's domain aperture starts at 0 and `drm_mm` first-fits there, so the
  first DRM GEM object legitimately gets IOVA 0.
- Instrumented `iommu_iova_to_phys()` in `tegra_bo_iommu_map()` proved the
  mapping: `iova=0x0 mapped=12582912 iovaphys=0x82a80000` (or `0xac000000`).
- The DC swgroup is enabled with an ASID (`reg 0x240 = 0x80000001`).

Do not chase this again.

## Confirmed working

- DC: `dc-enable` reads `dispcmd=0x20` (C_DISPLAY), power `0x50155`, no DC
  underflow, and VBLANK interrupts observed.
- DSI: both links configured (`ctrl=0x103032`, 4 lanes, RGB888, video mode),
  ganged start/size correct (0x0/0x300 and 0x300/0x300).
- Panel: prepare's accumulated DCS error is `0` (all commands ACKed).
- Panel timings, packet lengths, packet sequences and PHY-format values match
  the vendor driver extracted in `~/Downloads/nexus9/kernel-analysis/`.

## Real finding: vendor clock-divider erratum

Downstream has a Tegra14x workaround (bug 1045373) that mainline lacks: the
shift-clock divider only takes effect if a different value is written and
latched first, then the target value 2 us later. Added to
`tegra_crtc_atomic_enable()`:

- write `SHIFT_CLK_DIVIDER(div + 2)`, `GENERAL_ACT_REQ`, `udelay(2)`, then the
  target value.
- Effect: `DSI_STATUS` went from `0x400` (IDLE) to `0x0` (streaming). This is a
  genuine fix and should be kept.

## Why the panel still shows nothing

- All panel commands succeed, but `GET_POWER_MODE` returns `0x00`
  (sleep-in / display off / booster off). This may be a dummy response — the
  vendor driver never reads, so the read is uncalibrated.
- Commands sent after streaming starts fail with `-110` and corrupt the master
  DSI (`DSI_CONTROL` becomes `0x1`). The vendor always sends its panel init
  commands **during** video, synchronised to vblank. Mainline has no mechanism
  for this; the vendor stops the DC at a frame end, commands the panel, and
  restarts.
- The bootloader's DC state at hand-over: `clkctl=0x6` (shift divider 6),
  `winopt=0`, `dispcmd=0`, `pwr=0` (already stopped). The divider 6 does not
  necessarily describe the 247.6 MHz mode — the bootloader was not scanning our
  framebuffer.

## Clock constraint discovered

`pll_d_out0` (the DSI "parent") is a fixed ÷2 of `pll_d`, and mainline's PLLD
VCO max is 1 GHz. Display clocks above 500 MHz are rejected from this parent:

- 371.5 MHz accepted; 742.5 MHz and 743 MHz rejected with `-EINVAL`.
- Vendor maths targets a 742.5 MHz DSI clock, which this kernel cannot produce
  through the current DT clock. Either PLLD's limits are conservative for
  Tegra132, or a different parent/clock path is needed.

## The clock is now correct (2026-10-18)

The `DIAG` ganged override that hardcoded `plld = 742.5 MHz` / `scdiv = 6` was
wrong twice over: 742.5 MHz is rejected on `PLL_D_OUT0` (it would need a
1485 MHz PLLD, and `plld_params.vco_max` is 1 GHz), and the stored state is
still used by `tegra_dc_atomic_enable()`, so the display ran with divider 6
instead of 1. With the mainline (and vendor) formula restored, the first run
that used the correct boot-image format reports:

    DIAG clk: mode=247600000 lanes=8 mul=3 div=1
              plld=371500000 scdiv=1 slave=1 master=0
    DIAG dc-enable: clkctl=00000001 div=1 pclk=371500000 rate=371500000

That matches the downstream driver exactly (`default_hs_clk` 371.5 MHz,
shift clock divider register 1, `pixel_scaler_mul/div` 3/1, 8 lanes).

Consequences:

- The master DSI link now reports `DSI_STATUS=0x0` (streaming) instead of
  `0x400` (idle).
- The slave link (DSI-B) still reports `0x400` (idle) after 2 s. Both are
  configured identically (`ctrl=0x103032`, ganged enabled, start 0 / 0x300,
  size 0x300 each), so the remaining question is why the second half of the
  ganged pair is not transmitting.

## Matching the bootloader's live DSI configuration (2026-10-18)

At handover hboot is driving this exact panel through the same DSI block, so
its registers are a known-good reference. Dumping them in `tegra_dsi_prepare()`
*before* the module-reset toggle gives (master):

    ctrl=00103032 host=00000023 pwr=00000001 status=00000000
    sol=0000017f phy=0b080d06 070b1805 000000b5
    pktlen=00000000 090000dc 000001ba 0f0f0000 videomode=00000009

Against mainline, this exposed four real differences, all now patched:

- `DSI_HOST_CONTROL`: bootloader `0x23` = `HS | CS | ECC`; mainline's video
  path set only `HS`.
- `DSI_SOL_DELAY`: bootloader 383, mainline 403 (the `+20` that the vendor
  adds only in command mode).
- `DSI_PKT_LEN_0_1`: bootloader 0; mainline wrote `hsw << 16`. In ganged
  non-burst mode the vendor writes 0 here.
- `DSI_VIDEO_MODE_CONTROL`: bootloader 0x9 on the master; mainline never wrote
  it, so the reset cleared it to 0.

Against the bootloader the PHY timing values differ substantially, and using
the bootloader's exact values (`0b080d06 070b1805 000000b5`) was tested too.

### Result: still black, but the link is now indistinguishable from hboot's

After the fixes, the streaming registers read back exactly as the bootloader's:

    ctrl=00103032 sol=0000017f phy=0b080d06 070b1805 000000b5
    pktlen=00000000 090000dc 000001ba 0f0f0000 vm=00000009
    ganged: master start=0 size=03000300, slave start=0300 size=03000300
    status: both links 0x0 (streaming), DC dispcmd=0x20

The panel's `GET_POWER_MODE` still returns `0x00` after the init sequence, and
its brightness commands report `accum_err=0` (all ACKed). So either the panel
ignores the commands it ACKs, or the DC is sending valid-timing black frames.

The remaining unexplored area is the DC window/plane programming: the window
register block cannot be read without hanging the kernel, and nothing yet
proves the DC is sending the fbcon/`fb0` content rather than blank frames.

### Two more ruled out on 2026-10-18

- **Framebuffer IOVA 0.** Reserving the first 64 KiB of the IOVA space so the
  GEM buffer gets IOVA `0x10000` (`gem-map: iova=0x0000000000010000`,
  `iovaphys=0x813ae000`) changes nothing; the screen stays black.
- **Panel init in the kernel.** Leaving the panel completely untouched (no
  `drm_panel_prepare()`, no stop/start, only the video stream taken over with
  hboot-identical registers) also leaves the screen black. Since hboot was
  displaying on that panel at handover, this suggests the panel *is* latching
  our stream and that the stream itself carries black frames.

That moves the open question firmly to the DC/plane: whether window A is
actually enabled and fetching the framebuffer. Note that DSI reports no
underflow, which means the DC is feeding packets at the right rate -- black
ones are still packets.

### The window is enabled and programmed correctly

Reading the window block back inside `tegra_plane_setup()` -- the one place it is
provably clocked; reads from a delayed work hang -- gives:

    winopt=40000000 start=00000000 stride=00001800
    size=08000600 prescaled=08001800 fmt=00000025

`0x40000000` is `WIN_ENABLE`, `size` is 1536x2048, `stride` is 6144, and
`0x25` is `WIN_COLOR_DEPTH_B8G8R8X8` (32-bit XRGB8888). So the plane is enabled
and correctly described. There is no underflow.

### Physical vs IOVA addressing is not it either

Pointing the window at the translated physical address
(`start=82a80000` for `iova=0`) also leaves the screen black, with no underflow
or SMMU fault.

### The panel still reports sleep/display-off

With a 100 ms delay after `DISPLAY_ON`, `GET_POWER_MODE` returns `0x00` on
**both** links. Its commands are ACKed (`accum_err=0`), so either the panel
ignores what it acknowledges (unlikely for real hardware) or this read is a
dummy (the downstream driver never reads it, so the read path was never
validated on this panel).

### Leaving hboot's DSI untouched also fails

Two tries at skipping `tegra_dsi_prepare()` entirely and only enabling the DC's
DSI output:

- with the late diagnostic read: black, then the kernel hangs (reading the DSI
  registers while the block was never resumed wedges the bus).
- without any DSI register access: still black, and it hangs again.

So the DSI block cannot simply be inherited: host1x runtime PM has already put
it into a state where the bootloader's configuration is gone, and streaming the
DC into it without a proper resume wedges the kernel.

### Error and pad registers (2026-10-18, latest run)

    int_status=00000000 int_mask=00000000 host=00000023 cd=00000000
    pad0=00000000 pad1=00000000 pad2=00077110 pad3=00003333

No latched DSI protocol errors. `host=0x23` matches the bootloader; the pad
values are the ones `tegra_dsi_pad_calibrate()` programs (the bootloader read
0x0 before our reset). This run also reported `accum_err=-110` for the panel
init and `status=0x200` (underflow) on both links at the 2 s check, unlike the
earlier clean runs -- the command path is flaky and the video FIFO starved at
some point after the stop/start. Whether the underflow is a real starvation or
a stale sticky bit set while the DC was stopped is not yet established.

### The panel reset pulse (2026-10-18, latest)

The panel driver was only driving the reset line high; it never asserted it.
Because the panel is battery-powered and keeps state across SoC reboots, a
stuck state survives a `fastboot boot`. It now pulses reset (low 10 ms, high
120 ms) before the init sequence.

That did **not** fix the timeouts. In the latest boot:

    accum_err=-110 power(1)=00 fmt(1)=00 addr(1)=00

The reads complete (`1` byte) but return 0x00 for power mode, pixel format and
address mode; at least one write still times out. So the panel acknowledges
reads with zeros and does not reach a usable state.

## It works: inject panel commands into the running video stream

The panel never executed commands sent with the stream stopped, even though
the DSI acknowledged them. The vendor does not do that: its
`DSI_CMD_VBLANK_SHORT` commands are queued while video is running and the
controller inserts them at vblank
(`tegra_dsi_start_host_cmd_v_blank_video()`), using `DSI_VIDEO_MODE_CONTROL`
(which hboot leaves at `0x9`).

Implemented in `tegra_dsi_host_transfer()`: while `dsi->video_pkt_mode` is set,
the packet is written to `DSI_WR_DATA` with `DSI_VIDEO_MODE_CONTROL` enabled,
two frames are allowed to pass, and the register is restored. No BTA is
possible on this path. `tegra_dsi_encoder_enable()` sets the flag around
`drm_panel_prepare()` and leaves the video stream running throughout -- the
stop/start + host/LP sequence is gone.

Result, confirmed twice on hardware:

- `panel prep: accum_err=0`
- **console text appears, then the init's white paint fills the panel**
- both links `status=0` (streaming), `int_status=0`, DC `dispcmd=0x20`

The strobing seen first is the freestanding init painting the framebuffer in
64 KiB chunks; it settles to solid white.

The injection stays enabled for the lifetime of the stream, so runtime
backlight writes (DCS 0x51) also go through the video path. Confirmed on
hardware: kernel console text with a cursor, then full white at full
brightness.

## First userspace attempt: stock Android ramdisk (2026-10-18)

Booting the working kernel with the stock LineageOS ramdisk gets as far as:

    Freeing unused kernel memory: 896K
    Run /init as init process
    [drm] fb0: tegradrmfb frame buffer device

The device then resets and boots the stock 3.10 kernel, with no kernel message
from Android's init at all. To see the handover, `tools/miniroot/init.c` gained
a `HYBRID` build:

- it writes the usual record to the DTB partition,
- forks a child that refreshes the record every 2 s,
- then `execve()`s `/init.android` (the stock ramdisk's real init, renamed).

The record confirms our kernel reached userspace and the display driver
registered. Android's init produced no `init:` messages before the reset, so it
either failed immediately or called `reboot()` on a mount failure.

Also visible in that log: `tegra-xusb-padctl ... failed to setup XUSB ports:
-517`, so mainline has no USB yet. That alone rules out a usable Android for
now, independent of display.

The hybrid ramdisk is built from `bootimg-build/ramdisk.gz`, with `init`
renamed to `init.android`, `tools/miniroot/init.hybrid` installed as `/init`,
and the tree repacked with `cpio -o -H newc --owner 0:0`.

## USB bring-up attempt (2026-10-18)

USB is needed before any userspace work can be driven over adb. Findings:

1. `tegra-xusb-padctl ... failed to setup XUSB ports: -517` was a missing
   supplier: the charger that creates `usb-otg-vbus` was built as a **module**
   (`CONFIG_CHARGER_BQ24190=m`) and the test image has no module loader.
   Building it in (`=y`, same for `CONFIG_USB_TEGRA_XUDC`) removed the padctl
   error.
2. The controller node `usb@7d000000` then still deferred:
   `tegra-usb: failed to add HDRC device` (`-EPROBE_DEFER` from
   `ci_hdrc_add_device` via the missing vbus regulator).
3. The charger was not probing because its DT interrupt used
   `<TEGRA_GPIO(J, 0) GPIO_ACTIVE_HIGH>`: `GPIO_ACTIVE_HIGH` is 0, not a valid
   IRQ trigger type, and the GIC warns `HW irq 118 has invalid type` while
   registering i2c clients. Changed to `IRQ_TYPE_EDGE_FALLING`; the built DTB
   now carries `<0x48 0x02>`.
4. The warning still appears in the next boot and the HDRC probe still defers,
   so the charger is still not reaching a successful probe. The next step is
   to instrument `bq24190_probe()` to see whether it runs and what it returns.

The legacy `nvidia,tegra124-udc` at `usb@7d000000` (ChipIdea) is the path
flounder's padctl uses (`usb2-0` function `"snps"`). The xusb host at
`usb@70090000` is still disabled in the flounder tree.

### Further USB work (same session)

- The charger does probe (`probe ok`, IRQ 72), and `tegra_dsi`'s diagnostics
  showed `phy_init=0` before the controller add, so the PHY is fine.
- `ci_hdrc_add_device()` still returns `-EPROBE_DEFER`; `ci_get_platdata()`
  looks up the `vbus` regulator and two extcon devices.
- Fixed two more candidate causes:
  - the charger's vbus regulator is registered against the charger node, not
    the `usb-otg-vbus` child, because the regulator core no longer resolves
    `desc->of_match`; the driver now sets `cfg.of_node` explicitly;
  - `CONFIG_EXTCON_PALMAS` was `=m`, so the palmas USB extcon provider never
    registered. It is now built in.
- After both, the controller still reports `-517`. The next diagnostic is to
  print the return values of the `reg_vbus`, `ext_vbus` and `ext_id` lookups
  in `ci_get_platdata()` in one run; a previous attempt did not reach the
  init dump before the tablet was reset, so it still needs capturing.

Config additions for the static test image (`arch/arm64/configs/flounder_defconfig`):
`CONFIG_CHARGER_BQ24190=y`, `CONFIG_USB_TEGRA_XUDC=y`,
`CONFIG_EXTCON_PALMAS=y`.

USB work is on branch `usb-bringup`, separate from the display PR series.

### The extcon property is the remaining deferral trigger

With all four dependency fixes in place the controller still returned `-517`.
Removing `extcon = <&palmas_usb>, <&extcon_usb_otg>` from `usb@7d000000`
**removed the deferred-probe message entirely** — the controller gets past
`ci_hdrc_add_device()`. With the normal 90 s init the run completed and the
display painted white.

But the system then wedges, and not consistently: one run with that DT
completed, the next (with an added early `dev_info`) hung before the log dump.
That looks like the USB controller itself (OTG/role switching, charging or an
interrupt storm) wedging the machine once it actually comes up, rather than
anything in the diagnostics.

Next options, in order:

1. Try `dr_mode = "host"` and `dr_mode = "peripheral"` with `extcon` removed,
   to avoid the OTG/role machinery that appears to hang.
2. Fix the palmas extcon provider properly instead of dropping it: confirm the
   `ti,palmas-usb-vid` child device is created by the palmas MFD and that its
   extcon device registers, then re-add the property.
3. Get the debug UART attached; every remaining question here is much cheaper
   with a serial console than with 4-minute RAM boots and button resets.

Note: the short (20 s) init variant used for faster cycles appears to wedge
after painting, so future quick tests should stay at the 90 s dump.

### External references found later (2026-10-18)

- The pmOS wiki page (`wiki.nura.eco`, raw via
  `index.php?title=...&action=raw` because Anubis blocks normal fetches)
  lists `usbnet = N`, `otg = Y`, `screen = P`, and notes **USB port is
  EHCI1, id pin is PW2** -- which matches the ChipIdea controller we are
  using.
- A mainline branch exists at `github.com/TuxThePenguin0/linux`, branch
  `device/htc-flounder`. Its flounder DTS uses the same USB node:
  `nvidia,tegra124-udc`, `dr_mode = "otg"`, both extcon providers and
  `vbus-supply`.
- The maintainer's blog (`yuka.dev/blog-2026-02-21-nexus-9.html`) describes
  rebasing onto 6.19 and reaching X11 via `/dev/fb0`; device-mode USB is
  broken there too and no panel/DSI work is described. So the display fix in
  this repository is new ground, and USB is unsolved upstream as well.

### USB: current stopping point

With `extcon` removed the deferred probe clears and the controller starts.
From that point the machine sometimes wedges -- including before the init
dump -- both with and without a built-in `g_serial` gadget. That is a hang in
the USB bring-up itself, not in the DT dependencies. The next step needs the
debug UART on the test pads (or another console channel): RAM boots plus
button resets cannot resolve it efficiently.

## Next steps

1. **Backlight updates after streaming.** The panel driver currently latches
   brightness and skips writes once streaming has begun (that was the old
   workaround for `-110`). With `video_pkt_mode` in place those writes can be
   injected too; enable the flag for `jdi_panel_bl_update_status()` whenever
   the video stream is running and drop the skip.
2. **Try the mainline-computed PHY timing again.** The bootloader's values are
   currently forced. They are known-good, but the override should be removed
   and re-tested now that the command path works.
3. **Remove the DIAG instrumentation** once stable, or move the register dumps
   behind debugfs. The window/DSI dumps are cheap but noisy.
4. **Test with a real userspace** rather than the freestanding init: a normal
   ramdisk + Android or postmarketOS, checking the framebuffer, console and
   backlight.
5. **Upstream shape.** The real fix is enabling the panel after the video
   stream starts and delivering DCS with `DSI_VIDEO_MODE_CONTROL`; mainline's
   current ordering cannot work for a panel that only accepts vblank-synced
   commands.

Keep `bootimg-repack.py` output wrapper-stripped for `fastboot boot` (see the
section below) and always verify the `#<build>` line in the pulled log.

## Working loop (unchanged)

`fastboot boot` only; never flash diagnostic images. Init in
`tools/miniroot/init.c` now sleeps 90 s and holds the paint for 10 s. Log record
format and pull procedure are in `kernel-log.md`.

## The boot image must have the HTC wrapper stripped for `fastboot boot`

Discovered the hard way on 2026-10-18, after three "experiments" silently ran
yesterday's kernel. The symptom is deceptive:

- `fastboot boot <image>` prints `Booting OKAY` in under a second.
- The device **stays in fastboot** (or falls back to Android); no kernel runs.
- The DTB log partition keeps the previous record, so the log you pull looks
  plausible but is stale. Two consecutive runs produced byte-identical logs.
- **Always check the `Linux version ... #<build>` line against the build you
  sent before believing anything else in the log.**

`tools/bootimg-repack.py --stock extract-lte/boot.img` preserves the stock
256-byte HTC wrapper (`78 56 34 12`) and puts `ANDROID!` at 0x100. That layout
is correct for `fastboot flash boot`, but this `fastboot boot` path passes the
buffer straight to hboot's kernel loader and **requires `ANDROID!` at offset
0**. The working images (e.g. `boot-lte-6.19-diag23.img`) are exactly 256 bytes
smaller for this reason.

Make a bootable test image like this:

```sh
python3 -I tools/bootimg-repack.py ... -o wrapped.img
tail -c +257 wrapped.img > bootable.img   # strip the HTC wrapper
fastboot boot bootable.img
```

Confirm the run started by watching USB: the device disappears from both
`fastboot devices` and `adb devices` within ~6 s while the kernel runs. If it
sits in `fastboot devices` for 40 s, it was rejected.
