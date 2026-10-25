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

## 2026-10-26 00:10 — under load (LineageOS 16, 1 Hz sampler `adb shell sh sampler.sh`; Settings scroll then 2x CPU burn)
| t (s) | phase | CPU MHz | GPU MHz | EMC MHz | CPU C | GPU C |
|---|---|---|---|---|---|---|
| 0-11 | idle | 1.7-2.2 GHz (bursts) | 72 | 204 <-> 924 (flips) | 51 | 43 |
| 15-46 | scroll + burn | **2295** | **756** | 924 | 69 -> 86 | 55 -> 70 |
| 46-63 | burn, hot | 1.8-1.9 GHz (thermal step-down at ~85 C) | 648 | 924 | 85 | 70 |
| 66-73 | load ended | 1.5-1.7 GHz | 648 | 204 <-> 924 | 66 -> 61 | 59 -> 54 |
- Takeaways: Android runs just as hot (CPU 86 C) but **throttles gradually** (CPU 2295 -> ~1850 MHz, GPU 756 -> 648 MHz) via
  `pid_thermal_gov` + EDP caps, and drops EMC back to 204 MHz within seconds. pmOS has none of this: fixed clocks.
- Driver settings captured (debugfs): interactive governor `hispeed 1530, go_hispeed_load 99, target_loads 65 228000:75
  624000:85, timer_rate 20 ms`; gk20a_scaling `load_target 700, load_max 900, scaleup_limit 1100, scaledown_limit 1300,
  bias 80, damp 7, smooth 10, slowdown_delay 10` (nvhost devfreq-like, per mille loads); EDP: CPU table 2499/2300 MHz
  (1/2 cores) flat to 102 C, GPU limit 852 MHz; sysedp budget 29.9 W; passive trips: CPU 85 C, GPU 89 C, therm_est 45 C
  (skin, `adaptive_skin`); critical 105/101 C; cooling devs cpu_edp (max 12), gpu_edp (9), gpu_scaling (4), cpu/gpu-balanced (83).
  EMC: 13 rates 12.75-924 MHz (table ids `02_<kHz>_01_V6.0.4_V1.1`, rev 0x19), 529 transitions in the first ~26 k units.
- Raw captures in /tmp/n9probe (not committed).

## 2026-10-26 00:40 — display: live register dump on Android (for diffing against a booted pmOS)
- Dumps committed in `notes/android-reference/`: `lineage16-dsi-regs.txt` (`/sys/kernel/debug/tegra_dsi/regs`, both links
  0x54300000/0x54400000), `lineage16-dc-regs.txt` (`tegradc.0/regs`), plus thermal trips, GPU/EMC tunables, CPU/EDP tables
  and the load sample. Capture again on pmOS with debugfs `tegra_dsi/regs`, `dri/0/...` and diff.
- Highlights (Android, screen on, brightness 102): DSI_CONTROL 0x00103032, SOL_DELAY 0x17f, MAX_THRESHOLD 0x1e0,
  DSI_HOST_DSI_CONTROL 0x23, PHY timing regs 0xf0 = 0x0a090b06/0x060c1705-0x000501ff, 0x110 = 0x20000e97/0x9b092000,
  0x140 = 0x00077110/0x3333; PKT_SEQ_0..5 = 0x40091e08 / 0x40091f08 / 0x40091f08 / 0x3f3b2b08+0x2cc / 0x40091f08 /
  0x3f3b2b08+0x2cc. DC: DISP_TIMING (ref_to_sync 11, sync 4/76, back 8/80, active 2048x1536, front 12/300) = notes;
  DC_DISP_DISP_CLOCK_CONTROL 1, SHIFT_CLOCK_OPTIONS 0, DC_COM_PM1_CONTROL 0x00148480 and PM1_DUTY_CYCLE 0x20 **fixed
  regardless of backlight level** (checked at 5/20/102/255) -> PM1 is not the backlight control; mainline also enables PM1.
- Display debugfs: `tegradc.0/stats` underflows 0; `mode` pclk reads 6666000 (vendor-internal units).
- Brightness on Android: 0..255 sysfs, same curve as mainline's jdi_bl_map (7..90..255) -> brightness path is equal.
- So far NOT yet different from mainline: timings, brightness curve, CABC (0x55=0), PM1. Still to compare: pmOS
  DSI PHY timing/PKT_SEQ/HS clock registers (above), panel init MCS order/timing, DC underrun/FIFO settings.
