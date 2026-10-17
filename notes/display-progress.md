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

## Next steps (in order)

1. Implement vendor-style panel commands: stop the DC stream at a frame end,
   send DCS (`0x11`, `0x53/0x55/0x35`, `0x51`, `0x29`), restart the stream.
   This is the largest remaining behavioural difference.
2. Re-check DSI PHY timing registers against the vendor's ps values.
3. Establish the pixel clock the bootloader actually ran. Reading its registers
   while it streams hangs the kernel (confirmed again this session — one boot
   had to be recovered with Power + Volume Down). A safer route is a cold-boot
   read before the DSI is streaming, or hardware probing.
4. If the 500 MHz ceiling is the blocker, revisit `pll_d_params` for Tegra132
   (vco_max) and the DSI clock parent in the DT.

## Working loop (unchanged)

`fastboot boot` only; never flash diagnostic images. Init in
`tools/miniroot/init.c` now sleeps 90 s and holds the paint for 10 s. Log record
format and pull procedure are in `kernel-log.md`.
