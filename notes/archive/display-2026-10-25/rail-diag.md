# flounder display power tree / simplefb→DRM rail lifetime — host-only analysis

Date 2026-10-25. Sources: notes/pmos.md, display-progress.md, display-port.md,
stability-debug.md, instability-plan.md; patches/flounder.dts.orig; ~/code/linux-flounder
(DTS, drivers/video/fbdev/simplefb.c, drivers/gpu/drm/tegra/{drm,dsi,fbdev}.c,
drivers/video/aperture.c, drivers/regulator/{core,devres}.c,
drivers/gpu/drm/panel/panel-jdi-lpm089a128a.c). No tablet access.

## 1. Power tree (reference DTS = patches/flounder.dts.orig; same in mainline DTS)

| Rail | Type / control | Reference DTS | Mainline DTS | Consumers declared |
|---|---|---|---|---|
| avdd-lcd | regulator-fixed, GPIO R0 (PWM0? bank R bit0), 4.x V from vdd-battery, enable-high, regulator-boot-on | 1261-1269 | 1561-1569 | simplefb `lcd-supply` (45 / 50); panel0 `avdd-supply` (83 / 88) |
| iovdd-lcd | regulator-fixed, GPIO Q2, 1.8 V from vdd-1v8 (Palmas SMPS8), enable-high, boot-on | 1270-1279 | 1570-1578 | simplefb `io-supply` (46 / 51); panel0 `iovdd-supply` (84 / 89) |
| avdd-dsi-csi | Palmas LDO5, 1.2 V, i2c-4 regulator slave 0x58, boot-on | 971-976 | 1090-1095 | simplefb `dsi-supply` (44 / 49); dsi@54300000 (77 / 82); dsi@54400000 (94 / 104) |
| DISP1/DSIA/DSIB clocks | Tegra CAR | simplefb `clocks` (42) | (48) | simplefb enables them early |

- Both DSI0 and DSI1 get `avdd-dsi-csi-supply`; the panel's own avdd/iovdd are declared only on
  `panel_primary` (dsi@54300000/panel@0), and it owns the DSI peripheral for both links via `link2`
  (mainline DTS 98; the reference DT used the broken `port_b/port_a`).
- The reference DT is mainline-shaped (pre-patch copy), not the Android 3.10 DT. It expects three
  supplies on the *boot* framebuffer node and the same rails again on the DSI/panel nodes, i.e. it
  deliberately declares the handover rather than handing ownership over.
- Vendor panel power sequence (REA, notes/pmos.md 18:00): iovdd(GPIO Q2) → avdd(GPIO R0) → dcdc_en(EE5)
  → reset(H5); off reverse. Our panel driver matches (prepare 191/199/206/219-222, unprepare 161-167).

## 2. Who owns the rails at boot, and the simplefb→DRM lifetime bug

Ordering on flounder:

1. `of_platform_default_populate_init()` finds `/chosen/framebuffer` and creates platform device
   `ac001000.framebuffer` (drivers/of/platform.c:576-586).
2. `simplefb_probe()`: `simplefb_regulators_get()` walks every `*-supply` property and takes
   `devm_regulator_get_optional()` (simplefb.c:344-393, get at 381), then
   `simplefb_regulators_enable()` calls `regulator_enable()` and enables DISP1/DSIA/DSIB
   (simplefb.c:396-413, 614-623).
3. `tegra_drm_load()` (drm.c:1254-1261): once any CRTC is registered it calls
   `aperture_remove_all_conflicting_devices()`, which `platform_device_unregister()`s simplefb
   (aperture.c:200-219). Unregister → `simplefb_remove()` (simplefb.c:667) → `unregister_framebuffer()`
   → (when the last fb_info ref drops) `simplefb_destroy()` → `simplefb_regulators_destroy()` →
   `regulator_disable()` for each rail, then `devres` drops the managed reference
   (simplefb.c:102-115, 415-425; devres.c:218-234).
4. `drm_client_setup()` brings up tegra DRM fbdev (`tegra/fbdev.c`, `drm_fb_helper`). It is pure
   memory/scanout emulation — it takes **no** regulators — so it is not a second rail owner. The
   DSI/panel drivers are the only owners after the handover.

The bug: the simplefb teardown tries to be the *last user* of `avdd-dsi-csi` and issue the Palmas
LDO5 disable exactly while the boot-time Palmas interrupt burst is NAKing the bus. In
`_regulator_disable()` (regulator/core.c:3156-3192), the last-user path calls
`_regulator_do_disable()`; on error it logs `"failed to disable: %pe"` (core.c:3185) and
**returns before decrementing `rdev->use_count`**. Consequences:

- The I2C write never landed → LDO5 is still physically on; the core also still thinks it is on
  (`use_count` stays 1).
- Later consumers can never switch it off: their `enable/disable` pairs only move `use_count`
  between 1 and 2, so the last-user branch is never taken again. This is the "rails never switch
  off" observation (pmos.md 18:00) and needs no lingering consumer to be true.
- The managed reference is then dropped while `enable_count != 0`; `_regulator_put()` fires
  `WARN_ON(regulator->enable_count)` (core.c:2578) — this is the `WARNING regulator_put` in the
  boot log. So the failed disable, the stuck count and the warning are one event.
- Correction to the note: only `avdd-dsi-csi` (Palmas I2C) can fail this way. `avdd-lcd`/`iovdd-lcd`
  are GPIO fixed regulators; their disables succeed, so they really do go off at takeover and are
  re-enabled by `jdi_panel_prepare()`. If regulator_summary really listed
  `ac001000.framebuffer-*` consumers as still present, that additionally means fb_destroy was
  deferred (fb_info held open, e.g. by fbcon or an open /dev/fb0) — a separate, rarer case; the
  stuck LDO5 does not require it.
- `regulator-boot-on` does not protect the rail: `_regulator_register()` only does
  `_regulator_do_enable()` for boot-on without incrementing `use_count` (core.c:1633-1666), and
  ARM DT never calls `regulator_has_full_constraints()`, so late cleanup just warns and leaves it on.

Can leaked rails cause the vertical lines? Only indirectly. A stuck-on 1.2 V DSI PHY rail is not a
signal-quality fault (the alternative — off — would give no image at all), and a structured line
pattern needs the panel streaming. The rail-related way to corrupt the panel is the *timing* of the
handover: simplefb tears the GPIO panel rails down while hboot's DSI stream is still running, and
`keep_power=1` means the panel never sees a full power cycle afterwards. A latched panel state is
plausible; a rails explanation for a *stable* line pattern is not. Rank it below the GPU/DSI-path
discriminator (section 4).

## 3. PMIC burst: is the rail wrong, or is it a log artifact?

The burst is on the Palmas interrupt slave (`dummy 4-0059`), read/write failures with `-121`
(`-EREMOTEIO`, no ACK). LDO5 writes go to the *other* slave address (0x58) via regmap
(`palmas_ldo_write()` → `PALMAS_BASE_TO_REG(PALMAS_LDO_BASE=0x150, reg=0x08)` = register 0x58), but
the same Tegra I2C controller. Bus saturation/PMIC internal state during the burst explains both.

Verdict: the `-EREMOTEIO` does **not** mean the rail is off or at the wrong voltage. `regulator_disable`
does not change the hardware if the write fails, so LDO5 stays in its previous (on) state; the
failure is real for the *software bookkeeping* (stuck use_count, WARN) but benign for the rail.
Evidence that distinguishes the two readings:

1. Read back LDO5_CTRL bit0 (MODE_ACTIVE) on the idle tablet:
   `i2cread 4 58 58 1` (bus 4, slave 0x58, reg 0x58 — the 0x58/0x58 coincidence is correct).
   bit0 = 1 → still on; a clean 0 with the display working would be surprising.
2. `regulator_summary`: `avdd-dsi-csi` use count ≥ 1 with 1200 mV and (possibly) no consumer.
3. Functional: the panel streams, so the DSI PHY rail must be powered; and a later DSI runtime
   suspend (`tegra_dsi_runtime_suspend()`, dsi.c:1190) that completes without the error shows the
   bus recovered; after that use_count still cannot reach 0.
4. Correlation: the `-121` lines and the failed disable are the same few-ms window on i2c-4.

Also note: `tegra_dsi_encoder_enable()` ignores the return of `drm_panel_prepare()`/`drm_panel_enable()`
(dsi.c:1021-1026). If a panel init ever fails (regulator enable NAK/DCS error) the stream is enabled
anyway and the panel is left un-initialised — that *could* look like garbage/lines, and it is silent
apart from the panel driver's own `dev_err`. Check dmesg for `failed to enable iovdd/avdd` or DCS
accum_err on the affected boots.

## 4. Ranked fixes for the vertical lines (low risk first)

| # | Change | Files | Expected effect | Lines? |
|---|---|---|---|---|
| 1 | **Discriminate GPU vs scanout first**: boot pmOS with software rendering (`GBM_ALWAYS_SOFTWARE=1 LIBGL_ALWAYS_SOFTWARE=1 WLR_RENDERER=pixman`) and/or `nouveau.modeset=0`; compare console-on-DRM (before Phosh) vs Phosh | rootfs env / baked cmdline, no kernel change | Isolates compositor/GPU buffer corruption from DSI/DC scanout. EMC is already fixed, so this is the cheapest live suspect | highest (test) |
| 2 | **Delete `dsi-supply`/`lcd-supply`/`io-supply` from `/chosen/framebuffer`** so the DSI/panel drivers are the only rail owners | tegra132-flounder.dts chosen node (mainline 49-51) | No rail toggling at handover; no `-EREMOTEIO`, no stuck LDO5, no `regulator_put` WARN; simplefb keeps working as a console | medium-low |
| 3 | `regulator-always-on;` on `avdd_dsi_csi` (ldo5) | DTS 1090-1095 | Removes the Palmas disable attempt entirely, matching vendor boot-on intent; costs ~nothing | low (removes the PMIC marker, not the lines) |
| 4 | Check/retry `drm_panel_prepare()`/`drm_panel_enable()` results in `tegra_dsi_encoder_enable()`; retry regulator/DCS on `-EIO`/`-EREMOTEIO` | dsi.c:1021-1026, panel driver prepare | A failed panel init becomes visible and recoverable instead of silent garbage | medium |
| 5 | After (2), test `panel_jdi_lpm089a128a.keep_power=0` | cmdline only | A real panel rail power cycle at blank/boot; clears a latched panel state if that is the mechanism | medium (test) |
| 6 | Longer panel power-up delays (iovdd→avdd→dcdc→reset, e.g. 20-30 ms) | panel driver 191-222 | Only if margin is marginal; sequence already matches REA | low |
| 7 | Stop the PMIC burst at the source (interrupt polarity/delivery K2, rate-limit palmas IRQ status reads) | DTS PMC/Palmas + palmas driver | Fixes the NAK root cause and the stability risk; does not by itself fix lines | low for lines |
| 8 | Disable simplefb entirely (`CONFIG_FB_SIMPLE=n` or remove the node) | config/DTS | Same ownership result as (2) but loses the known-good fallback console and the diag image | not recommended |

Do not read (2)/(3) as likely to fix the lines: they are the correct rail fixes and they remove a
real PMIC/instability failure, but a stuck *enabled* 1.2 V PHY rail cannot produce a stable image
defect. If lines persist with (1) software rendering, the next suspects are DSI timing/ganged split
(the mode is unchanged since the clean white-paint tests) and the panel state left by crashes.

## 5. Cheapest test plan — fastboot boot only

All variants are `fastboot boot` images (no flashing); each differs in one variable.

- V0 control: existing diag image (simplefb, no userspace) — known clean. Re-run if in doubt.
- V1 current pmOS image with software rendering forced (env-only) → clean means GPU/nouveau;
  lines mean DSI/DC scanout. Also observe the console *before* Phosh: if lines are already there,
  userspace is exonerated.
- V2 same image + `panel_jdi_lpm089a128a.keep_power=0` (repack cmdline) → tests whether a real panel
  power cycle clears the state.
- V3 same image + `nouveau.modeset=0` (repack cmdline) → second, independent GPU-off check.
- V4 DTS variant with simplefb supplies removed (rebuild, then fastboot boot) → verifies no
  `-EREMOTEIO`/WARN and that the lines are unchanged or not.
- V5 DTS variant with `regulator-always-on` on ldo5 (rebuild) → confirms the PMIC marker disappears.

Read-out per boot: dmesg `grep -E 'avdd-dsi-csi|regulator_put|failed to (enable|prepare)|4-0059'`,
`/sys/kernel/debug/regulator/regulator_summary` (avdd-dsi-csi use/consumer rows), `cat
/sys/kernel/debug/clk/clk_summary | grep -E 'disp1|dsi'`, and a photo of the panel.
