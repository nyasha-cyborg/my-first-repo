# Touchscreen — working state

Last updated: 2026-10-22 · kernel `6.19.0-htc-flounder-g5d830bfca033`

## Status: works, no DT change needed

Synaptics S7504 on SPI (`spi@7000d800`, `syna,rmi4-spi`, IRQ gpio K2 = 82),
bound by the in-tree RMI4 stack (`RMI4_SPI`, `RMI4_F12`, `RMI4_F01`, built in)
at boot: `rmi4_f01 ... product: S7504, fw id: 1732172`, input device
`Synaptics S7504` = `/dev/input/event0` (needs `evdev.ko`). Up to 10 slots,
pressure, touch major/minor. IRQ counts rise with every touch.

## Axes (measured, three independent ways)

`tools/miniroot/evabs-min /dev/input/event0`: X 0-3072, Y 0-2304 (reported
resolution 16/17 per mm; the mm figures look wrong, see below), slots 0-9.

- Mainline, panel held upright (portrait): corner taps TL/TR/BR/BL gave
  (161,80) (2875,100) (2919,2195) (115,2233); a top-to-bottom swipe gave Y
  0 -> 2304 with X flat; left-to-right gave X 18 -> 2503 with Y flat.
- Android (rotation 0, `SurfaceWidth 1536 x 2048`, no swap/flip in its DT,
  `synaptics_dsx.idc` only calibrates size/pressure): left-to-right swipe gave
  X 382 -> 2991, Y flat. Same axis ranges via `getevent -pl`.

Conclusion: raw X already runs left to right, raw Y top to bottom, in the
panel's native portrait orientation. **No `touchscreen-swapped-x-y` or inverted
properties are needed**; a compositor scales X by 1536/3072 and Y by 2048/2304
(the sensor is not isotropic; Android does the same).

Pitfall I fell into: the driver's `x_mm`/`y_mm` (192 x 135 mm from node pitch)
suggested X was the long edge; that was wrong, ignore it. The test was also
muddied by the tablet being held landscape for one capture.

## Not done / ideas

- libinput/compositor behaviour (palm rejection, gesture thresholds) uses the
  mm values; if scrolling feels off set `touchscreen-x-mm`/`-y-mm` equivalents.
- Panel was dark in these test images (display is a separate area), so touch
  was verified from raw events only, never against on-screen targets.
- Android's per-sensor configs (`config_7/8/9` in the stock DT) are firmware
  tuning blobs; mainline uses the controller's stored config.
