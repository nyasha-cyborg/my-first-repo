# The Nexus 9 panel — JDI QXGA 8.9"

What a mainline driver needs to know, and where each fact came from.

## Provenance

- Downstream driver: **`arch/arm/mach-tegra/panel-j-qxga-8-9.c`** in
  `LineageOS/android_kernel_htc_flounder`, branch `cm-14.1` — Android 7.1, the same
  release as the stock N4F27P kernel we measured.
  <https://raw.githubusercontent.com/LineageOS/android_kernel_htc_flounder/cm-14.1/arch/arm/mach-tegra/panel-j-qxga-8-9.c>
- **The filename is misleading in two ways.** It is `panel-j-qxga-8-9.c`, not
  `panel-jdi-lpm089a128a.c`, and it does *not* live in
  `drivers/video/tegra/dc/panel/`. Searching for the obvious names finds nothing —
  which is why this took a symbol table to locate.
- The downstream driver finds its device tree node by **node name**
  (`of_find_node_by_name(NULL, "panel_jdi_qxga_8_9")`), whereas the mainline fork's
  DTS matches on `compatible = "jdi,lpm089a128a"`. Two different identifiers for one
  panel.
- The panel driver is compiled into the stock kernel: `kernel-lte.raw` carries
  `panel_jdi_qxga_8_9` and `tegra_dc_dsi_vs1.0/1.1` in its kallsyms.

## Panel facts

- 8.9" JDI, **1536 × 2048** portrait (2048 × 1536 landscape).
- Physical size **135 mm × 180 mm** — diagonal 225 mm = 8.86", and the ratio is 3:4,
  matching the pixel ratio. Taken from `dc->width` / `dc->height`.
- **Dual DSI, ganged symmetric left/right** (`TEGRA_DSI_GANGED_SYMMETRIC_LEFT_RIGHT`),
  8 data lanes, DSI v1.0 (`controller_vs = DSI_VS_1`).
- Shipped configuration is **video mode**, not command mode — `DC_CTRL_MODE` is
  `CONTINUOUS | INITIALIZED`, no burst, 24 bpp, virtual channel 0.
- The host drives reset (`panel_reset = DSI_PANEL_RESET`).

## Timing (the shipped video-mode table)

| | |
|---|---|
| `pclk` | 247,600,000 Hz (60 Hz) |
| `h_active` / `v_active` | 1536 / 2048 |
| `h_sync_width` / `v_sync_width` | 76 / 4 |
| `h_back_porch` / `v_back_porch` | 80 / 8 |
| `h_front_porch` / `v_front_porch` | 300 / 12 |
| `h_ref_to_sync` / `v_ref_to_sync` | 1 / 1 |

- The same file also holds a command-mode alternative (pclk 294,264,000, 2560 × 1600)
  behind `#if DC_CTRL_MODE & TEGRA_DC_OUT_ONE_SHOT_MODE`. Flounder ships the
  continuous-mode branch, so **the table above is the live one** and the 2560×1600
  entry is dead code for this device.
- The geometry matches the `simple-framebuffer` the mainline DTS declares
  (1536 × 2048) — consistent, since that framebuffer is the bootloader's.

## Init sequence

| # | type | command | data | note |
|---|---|---|---|---|
| 1 | generic short write, 2 params | `0xB0` | `0x04` | page select |
| 2 | generic long write | `ce[]` | 24 bytes, below | |
| 3 | generic short write, 2 params | `0xD6` | `0x01` | |
| 4 | generic short write, 2 params | `0xB0` | `0x03` | page select |
| 5 | DCS write, 0 params | `0x11` EXIT_SLEEP_MODE | — | not clubbed |
| 6 | *delay* | — | 120 ms | |
| 7 | DCS write, 1 param | `0x53` | `0x24` | clubbed |
| 8 | DCS write, 1 param | `0x55` | `0x00` | clubbed |
| 9 | DCS write, 1 param | `0x35` | `0x00` | clubbed |
| 10 | DCS write, 0 params | `0x29` SET_DISPLAY_ON | — | clubbed |

```
ce[] = {0xCE, 0x5D, 0x40, 0x48, 0x56, 0x67, 0x78, 0x88, 0x98, 0xA7, 0xB5, 0xC3,
        0xD1, 0xDE, 0xE9, 0xF2, 0xFA, 0xFF, 0x05, 0x00, 0x04, 0x04, 0x00, 0x20}
```

## Suspend sequence

| # | type | command | data |
|---|---|---|---|
| 1 | DCS write, 1 param | `0x51` | `0x00` (brightness to zero) |
| 2 | DCS write, 0 params | `0x28` DISPLAY_OFF | — |
| 3 | DCS write, 0 params | `0x10` ENTER_SLEEP_MODE | — |
| 4 | *send frame* | ×3 | |
| 5 | generic short write, 2 params | `0xB0` | `0x04` |
| 6 | generic short write, 2 params | `0xB1` | `0x01` |

## Backlight

- Driven over **DSI**, not a PWM GPIO: DCS `0x51` (write display brightness).
- Default brightness 224; the driver applies a piecewise "shrink" curve mapping
  user brightness onto the panel's usable PWM range before sending it.
- A single backlight command is declared with the maximum value (`0x51 = 0xFF`),
  sent not-clubbed.

## Power-on order

```
enable():        iovdd_1v8 = 1           ; 15 ms
postpoweron():   avdd_4v   = 1           ;  1 ms
                 dcdc_en   = 1           ; 15 ms
                 lcm_rst   = 1           ; 15 ms

disable():       lcm_rst   = 0           ;  1 ms
                 dcdc_en   = 0           ; 15 ms
                 avdd_4v   = 0
                 iovdd_1v8 = 0           ; 10 ms
```

## Panel GPIOs

The node's `gpio` properties are read by index, so the order is the interface:

| idx | symbol | name | downstream GPIO |
|---|---|---|---|
| 0 | `IOVDD_1V8` | `lcmio_1v8` | `TEGRA_GPIO_PQ2` |
| 1 | `AVDD_4V` | `avdd_4v` | `TEGRA_GPIO_PR0` |
| 2 | `DCDC_EN` | `dcdc_en` | `TEGRA_GPIO_PEE5` |
| 3 | `LCM_RST` | `panel_rst` | `TEGRA_GPIO_PH5` |

- The mainline fork's DTS already carries `reset-gpios = TEGRA_GPIO(H, 5)` (PH5 =
  `LCM_RST`) and `dcdc-en-gpios = TEGRA_GPIO(EE, 5)` (PEE5 = `DCDC_EN`).
- It models the other two as **regulators** — `iovdd-supply = <&iovdd_lcd>` and
  `avdd-supply = <&avdd_lcd>` — where downstream drives them as GPIOs. Reconciling
  that mismatch, or proving the regulators are the same nets, is part of the work.

## What a mainline driver has to do

- **Template:** `drivers/gpu/drm/panel/panel-jdi-lpm102a188a.c` — already in the
  tree, also JDI, also dual-DSI ganged, also with a DCS backlight. Closest precedent
  by a wide margin.
- Port the init table above, then the suspend table, then a `backlight_device` that
  writes DCS `0x51`.
- Handle the ganged dual-DSI topology: the DTS links `port_b = <&panel_secondary>`
  and `port_a = <&panel_primary>`, so the driver has to deal with two DSI devices
  rather than one.
- **Not portable:** the CMU and smart-dimming tables. Those are downstream
  `CONFIG_TEGRA_DC_CMU` features with no mainline equivalent, so expect a different
  colour response until colour management is addressed separately.

## What the bootloader does with this panel

Read out of `hboot.img` (see `notes/evidence.md` for the method), and it corroborates
the above: `jdipanel_PanelInit` logs `"%s()"`, then runs a four-entry table at
`0xfcc84` — DCS `0x11` (exit sleep) with a 1-byte payload, 20 ms delay, DCS `0x29`
(display on) with a 1-byte payload, 20 ms delay. Those are exactly the
`EXIT_SLEEP_MODE` and `SET_DISPLAY_ON` opcodes from the driver above.

- It calls its writer through a **run-time-populated pointer table at `0x159b08`**,
  outside the 1 MB image, so the writer's semantics cannot be read statically.
- `jdiDsi_SetBacklightIntensity` sits alongside it, so hboot owns backlight too.
- This is the **logo path only** — just enough to unblank an already-initialised
  panel. The full sequence is the kernel's, above.
