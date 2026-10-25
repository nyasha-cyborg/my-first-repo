# Android (LineageOS 16 on stock 3.10 kernel) as the reference for pmOS slowness/flicker

Probed 2026-10-25 23:59 on LineageOS 16.0-20251224 (root adb, idle home screen). Collected with
`adb shell` + debugfs (`mount -t debugfs none /sys/kernel/debug`). Conclusions are idle-state only; repeat under load.

## Live values (idle)
| Item | Android | pmOS (last state) |
|---|---|---|
| EMC (DRAM) | **204 MHz idle**, 12.75-924 MHz range, scaled by `tegra_actmon` + `emc_usage_table`, 3d.emc cap | fixed 924 MHz (devfreq blacklisted: mainline EMC switch corrupted memory) |
| GPU (gbus) | **72 MHz idle**, 72-852 MHz; caps: battery 756, edp 852, throttle 852; `gk20a_scaling` governor | pinned 612 MHz, DVFS off |
| CPU | `interactive` governor, 204-2295 MHz (cclk_g), hispeed 1530, go_hispeed_load 99, target_loads `65 228000:75 624000:85` | schedutil, ~2.5 GHz at 70 C under Firefox |
| Display clocks | pll_d 743 MHz; disp1/dsia/dsib 371.5 MHz | same pixel clock (247.6 MHz mode) |
| Backlight | `tegra-dsi-backlight.0` 102/255 | PWM backlight, low-duty pulsing |
| Thermal | CPU 61 C, GPU 47 C, MEM 53 C idle (zones CPU/GPU/MEM/PLL-therm, `edp`, `dram-therm`) | CPU ~70 C, GPU ~65 C |
| Idle | `denver_idle` cpuidle driver | mainline cpuidle |

## Why pmOS is slower / hotter (supported by the table)
1. **DRAM stays at 924 MHz** on pmOS (EMC scaling had to be disabled) while Android idles at 204 MHz: more heat and
   power. Fixing mainline `tegra124-emc` (REA vendor `tegra12_emc_set_rate`) would let both bandwidth and heat scale.
2. **GPU is pinned** at 612 MHz with no DVFS (PLL-slide hangs earlier); Android scales 72-852 MHz with EDP/thermal caps.
3. **CPU policy**: Android's tuned `interactive` + EDP/battery caps vs generic schedutil at max clock.
4. Userspace weight (Phosh/Firefox on ~1.8 GB) and no HW video path.

## Open for next probe
- Under load: gbus/emc rates while scrolling/video, `emc_usage_table`, `cap.throttle` triggers, actmon thresholds.
- Display: dump DSI/DC registers live (`/sys/kernel/debug/tegradc.*`), backlight PWM freq/duty path, panel init.
- REA `tegra_emc` / `gk20a_scaling` in the Android kernel for the exact switch sequence.
- Flicker: Android shows almost none (owner), so compare PWM backlight + DSI HS timing first.
