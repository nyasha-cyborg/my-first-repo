# Charging under mainline

## 2026-10-24 22:40 — "not charging": charger-mode boots pmOS, and mainline pins the input at 500 mA

- Plugging in the powered-off tablet makes hboot boot LNX with `androidboot.mode=charger` — that is now
  pmOS, so the full system (software-rendered Phosh, 2.5 GHz, modem) runs instead of Android's charger.
- `bq24190` probe does a register reset (`bq24190_hw_init` → `bq24190_register_reset`), wiping the chip's
  own adapter detection; nothing raises IINLIM again (`external_power_changed` has no supplier here), so
  **IINLIM stays 500 mA even on a wall adapter**. The vendor stack set it per cable type
  (`htc_battery_bq2419x_input_control`, symbol in the Lineage kernel; not decompiled yet).
- Result: RepSOC 11.9 % (20:35) → 3.3 % (22:37) across a wall-charger session; current −777 mA peak,
  −280 mA average on the laptop port; still −300…−380 mA with greetd/modem stopped, powersave 204 MHz,
  backlight 0 (REG08 0x6c: USB host, fast charge, DPM active).
- Fix (rootfs, not boot image): `tools/pmos/local.d/n9-charge.start` → `/etc/local.d/` on the tablet.
  Every boot: keeps `input_current_limit` at 1.5 A (re-checked every 10 s, logs to
  `/var/log/n9-charge.log`); VINDPM 4.36 V throttles a weak source. Charger-mode boots additionally stop
  greetd + n9-modem, set powersave and backlight 0.
- After: **+252…+341 mA into the battery (avg +281 mA) on the laptop port**, RepSOC rising.
- Laptop-port charge log (gauge raw, tablet clock): 09:48 RepCap 222 mAh / RepSOC 3.4 % / 3.70 V /
  avg +262 mA → 11:10 616 mAh / **9.3 %** / 3.72 V / avg +275 mA (VFSOC 13.6 %). +394 mAh in 82 min
  = ~288 mA, ~4.3 %/h. No reboot (the host rebooted at 22:52 NZDT without disturbing it), CGAIN still
  0x4000, IINLIM held at 1.5 A, no charger faults.
- 2026-10-25 00:38 NZDT, laptop USB-C port1 (3.0 A Type-C source, non-PD partner = the C→micro-B cable):
  VINDPM/IINLIM step test, 30 s each, battery current: 4.36 V/1.5 A +200 mA; 4.28 V +349; **4.20 V +423**;
  4.20 V/2.0 A +453 (reg avg 434); 4.20 V/3.0 A +420 (447). DPM active throughout, PG=1, no faults, no
  host USB disconnects. Input ≈ 1 A at the 4.36 V floor → the cable drops ~0.6 V; the limit above 1.5 A
  is irrelevant on this cable. n9-charge.start now holds **VINDPM 4.20 V (code 4) + IINLIM 2.0 A**.
  Not lower than 4.20 V without checking Palmas/chipidea VBUS detection.
- 2026-10-25 08:10 NZDT: **RepSOC 51.3 %** after ~10 h (3.4 % at 22:48), +256 mA at 3.92 V, no reboot.

### 2026-10-25 — vendor input-current logic (REA) and the kernel fix

REA of the Lineage 16 kernel (`boot-backup-lineage16.img`; symbols recovered offline with the new
`tools/kallsyms-decode.py`, window `ffffffc0006da700-6dec00` wrapped by image2elf, Ghidra):
- `htc_battery_bq2419x_aicl_wq` = **AICL**: set 900 mA, then +300 mA steps (900 → 1200 → 1500) every
  200 ms, averaging `bq2419x_get_vbus` 3× per step. If VBUS falls disproportionately
  (`(V900−V1200)·3 < (V1200−V1500)·2`) it drops back to 900 mA and retries after 300 s. Cap 1500 mA (0x5db).
- `htc_battery_bq2419x_input_control`: VBUS < ~4.1 V (`< 0x1003` mV) → 900 mA.
- `bq2419x_set_dpm_input_voltage(mV)`: REG00[6:3] = (mV − 3880)/80; stock DT
  `input-voltage-limit-millivolt = <0x1158>` → **VINDPM 4.44 V**. So stock is stricter than our 4.20 V;
  it relies on the stock charger + short cable and backs off by measuring VBUS (mainline can't: no VBUS
  ADC while the Palmas GPADC times out).

Kernel (local `7b0972efa`, `patches/candidates/bq24190-input-limits-from-dt.patch`): bq24190 reads
`input-current-limit-microamp` / `input-voltage-limit-microvolt` (bq256xx names), applies them at probe
and on every PG rising edge; binding updated; flounder DT 2.0 A / 4.20 V. Compile-tested only. The
driver is built in, so the test needs a new Image (not just a DTB swap). checkpatch: two >100-column
`dev_warn` lines to wrap before upstreaming. Risk to keep in mind: on a weak 500 mA port a 2 A
request relies on VINDPM alone (vendor ramped from 900 mA).
- **2026-10-25 08:17 NZDT — gauge DT fix verified on hardware.** `fastboot boot` of
  `~/code/scratch/n9work/gaugeimg/n9gauge-stripped.img` (known-good LNX + `maxim,rsns-microohm`,
  md5 08afc9d5…, normal boot). `/proc/device-tree/.../maxim,rsns-microohm` = 0x2710. `modprobe
  max17042_battery` (blacklist still in place) left **CGAIN 0x4000 / MiscCFG 0x0810**; `capacity` = 51 =
  RepSOC 0x3373; `current_now`/`current_avg` now exist. Odd: FullCAP (0x10) now reads 0x33c0 = DesignCap
  (6624 mAh), was 0x2fd8 (6124) — not explained yet. Ready to flash once the owner OKs an LNX write;
  then delete `/etc/modprobe.d/n9-gauge.conf`.
- **Normal boots never ran the charge script:** `local` starts last in the default runlevel and
  `n9-modem` hangs in "starting", so the charger stayed at 500 mA / 4.36 V and the tablet drained
  −1.42 A with Phosh up. Now its own OpenRC service `n9-charge` in the **boot** runlevel
  (`tools/pmos/n9-charge.initd` → `/etc/init.d/n9-charge`, script `tools/pmos/n9-charge.sh` →
  `/usr/lib/n9/n9-charge.sh`). After: −168…−236 mA with full Phosh on the laptop port. The n9-modem
  start hang is a separate open item.
- Open: proper fix in the kernel (DT `input-current-limit` / charger detection from the Tegra USB PHY,
  as the vendor does); verify a wall adapter actually delivers ~1.5 A; the earlier "DCP replug kills
  mainline" hang (a laptop→laptop replug survived today at 22:36).

## 2026-10-24 20:30 — battery % wrong in pmOS: mainline disables the gauge's current sense (root cause found)

Symptom: pmOS shows `capacity=11` while `charge_now/charge_full` = 5890/6124 mAh (96 %).
Raw dump (`/tmp/n9build/i2cread 0 36 00 32 w`, read-only), pmOS boot, laptop USB port:

| reg | value | meaning |
|---|---|---|
| 0x06 RepSOC | 0x6031 | 96.2 % — frozen |
| 0x0D MixSOC / 0x0E AvSOC | 0x408d / 0x087b | 64.5 % / 8.5 % (drifting to VFSOC) |
| 0xFF VFSOC | 0x0b2c | **11.2 %** (voltage model; what the driver reports) |
| 0x09 VCELL / 0xFB VFOCV | 3.64 V / **3.69 V** | low state of charge |
| 0x0A/0x0B Current/AvgCurrent | **0 / 0** | constant over 3 samples |
| 0x2E CGAIN / 0x2F COFF | **0x0000** / 0 | current gain zero (POR 0x4000) |
| 0x2B MiscCFG / 0x28 LearnCFG | 0x0003 / 0x0017 | |

Cause: `max17042_battery.c` probe, when the DT has no `maxim,rsns-microohm`
(`enable_current_sense` false), writes **CGAIN=0, MiscCFG=0x0003, LearnCFG=0x0007** — voltage-only
mode — and reports `capacity` from VFSOC. These registers live in the battery-backed gauge, so the
coulomb counter stays dead across reboots and OSes. That is what the old DT comment "breaks the
battery meter in Android until the battery is disconnected" meant.

REA (Lineage 16 kernel, `gauge.elf` window via tools/image2elf.py, Ghidra):
- `htc_batt_max17050_get_soc` reads **reg 0x06 RepSOC** (rounded up) → Android/TWRP show the frozen
  value. The "TWRP 97 %" in handoff.md was this frozen RepSOC, not the real charge.
- The stock driver writes only 0x3a (V_empty), 0x12, 0x22 (`max17050_set_parameter_by_temp`, values
  from the DT `param_adjust_map_by_id` table; the gauge currently holds the id0 low-temp set
  af59/4d84/2484). It never writes CGAIN/MiscCFG/LearnCFG: those come from the factory/hboot model.

Consequences:
- **The battery really is low (~11 %, OCV 3.69 V).** hboot's `battery low` refusal was probably
  correct; retire the "hboot battery reading is stale garbage" conclusion.
- On a 500 mA laptop port the tablet's load exceeds the input (−250 mA net, 2026-10-23), so mainline
  sessions drain the pack. Low SOC on an aged pack (Age 0x07 = 92 %) under CPU/LTE bursts → voltage
  sag → brown-outs. **Plausible contributor to the hard hangs, `-71` enumerations and the power-off on
  cable replug** (replug = battery alone carries the load for a moment). Not proven yet.
- Palmas GPADC (`iio:device0`) reads all time out — consistent with the Edge-typed Palmas IRQ; no
  second voltage measurement available until the LEVEL_LOW fix is active.

Fix: `patches/candidates/flounder-max17050-rsns.patch` (kernel `3171a4096`, local): DT
`maxim,rsns-microohm = <10000>` (10 mΩ; DesignCap 0x33c0 = 6624 mAh confirms). DTB built, not booted.
With it the driver leaves CGAIN alone and reports RepSOC. **The gauge still holds CGAIN=0** — a
one-time restore is needed (CGAIN=0x4000, MiscCFG/LearnCFG to POR 0x0810/0x2602 or the factory
values if found, then MiscCFG quick-start so RepSOC restarts from VFSOC). Not written yet: needs the
owner's OK (persistent gauge state).

### 2026-10-24 20:35 — gauge restored (owner OK), coulomb counter running again

Full 96-register snapshot first: `/tmp/n9build/gauge/gauge-before.txt` (tmpfs; key values in the table
above). Writes with the new `tools/miniroot/i2cw16le.c` (write + read-back), live under pmOS:
`2e CGAIN 0000→4000`, `28 LearnCFG 0017→2602`, `2b MiscCFG 0003→0810`, then `2b=0c10` (quick start;
the QS bit self-cleared to 0x0810 within 2 s). Values are the POR defaults. Possible factory values:
FilterCFG 0x87a4, RelaxCFG 0x506b and FullSOCThr 0x5f00 in the gauge match Maxim's MAX17050 init
guide, which (from memory, unverified) also sets LearnCFG 0x2606 / MiscCFG 0x0870 — differences are minor.

After (laptop USB port, Phosh up, bq24190 says `Charging`), 30 s of 5 s samples:
- Current 0x0A −458 mA first sample, then **−79 … −99 mA**; AvgCurrent −134 mA settling.
- RepSOC **11.9 %**, RepCap 790 mAh, MixSOC 12.2 %, VFSOC 12.2 % — consistent.
- So on the laptop port the tablet **discharges ~100 mA while "Charging"**.

Protecting the restore until the DT fix is in the boot image: `/etc/modprobe.d/n9-gauge.conf` in the
rootfs blacklists `max17042_battery` (`modprobe -c` shows it; not yet proven over a reboot). pmOS shows
no battery after the next boot until the fixed DTB is flashed — then delete that file. **After any
reboot, re-check `i2cread 0 36 2e 1 w` = 4000** before trusting the gauge. The running driver keeps
reporting VFSOC (`capacity`) until then; it will not re-probe on its own.

Next: charge with the tablet off on a wall charger (mainline still dies on a DCP replug); build a boot
image with the fixed DTB, `fastboot boot` it on a fresh hboot, check `current_now` exists and `capacity`
follows RepSOC, then flash and remove the blacklist.

## 2026-10-23 11:50 — verified: the battery charges under mainline

Image `n9hsicI2` (kernel `usb-bringup`), tablet on the laptop's USB port (SDP), LTE modem + WiFi up.
Tool: `tools/miniroot/i2cread.c` (read-only I2C_RDWR register dump; never writes; works on driver-owned addresses).
The `max17042` gauge driver was deliberately **not** loaded (DT comment: enabling it breaks Android's battery meter
until the battery is disconnected) — the gauge was read raw instead.

**Charger bq24192 @ i2c-0 0x6b** (driver `bq24190`, built in; power_supply `bq24190-charger`):
status Charging, charge_type Fast, health Good, online 1, input_current_limit 500000.
| reg | value | meaning |
|---|---|---|
| 00 | 0x32 | HIZ off, VINDPM 4.36 V, **IINLIM 500 mA** |
| 01 | 0x1b | charging enabled |
| 02 | 0x98 | ICHG 2944 mA (DT `constant-charge-current-max`) |
| 04 | 0xd6 | VREG 4352 mV (DT) |
| 05 | 0x8a | termination on, I2C watchdog off |
| 08 | 0x6c | VBUS = USB host (SDP), **fast charging**, DPM active (input limited), power good |
| 09 | 0x00 | no faults |

**Gauge MAX17050 @ i2c-0 0x36** (10 mΩ sense: DesignCap 0x33c0 = 6624 mAh confirms; 1 LSB current = 156.25 µA,
capacity = 0.5 mAh): RepSOC 99.5 %, VCell 4.28 V, FullCap 6244 mAh, 30 °C.

**Battery current vs load** (reg 0x0a now / 0x0b average, 8 s apart):
| state | now | avg |
|---|---|---|
| backlight 224, WiFi + LTE up | −245 / −252 mA | −267 / −259 mA |
| backlight 0 | +192 / +177 mA | −41 / +54 mA (settling) |
| backlight 0, wlan0 + wwan0 down | +191 / +192 mA | +111 / +153 mA |

Conclusion: the charger path works (current flows into the battery). On a 500 mA laptop port with the screen on the
tablet's load exceeds the input limit and the battery drains slowly (~250 mA) while reporting "Charging" — expected
for an SDP port, not a driver bug. The battery was near full (CV taper), so +190 mA is not the maximum charge rate.

## Open (for pmOS)

- **Wall charger (DCP)**: not tested. Check REG08 VBUS_STAT = 10 (adapter) and whether IINLIM rises above 500 mA
  (bq24192 D+/D- detection, or the driver/extcon must set it). Needs the user to plug a wall charger.
- **Battery percentage in pmOS** needs the `max17042` driver bound to the gauge (DT node exists, module built). Side
  effect per the DT comment: Android's meter is confused afterwards until a battery disconnect. Decide when choosing
  whether Android stays on the tablet.
- Charging at a low state of charge (full 2.9 A CC phase) not observed yet.

## 2026-10-23 12:10 — moving the cable from the laptop to a wall charger kills mainline

Logger (`/tmp/charge.log`, 10 s samples) started on `n9hsicI2`, cable moved laptop -> wall charger by the user for 5 min,
then back. The tablet came back in **Android with `ro.boot.bootreason=watchdog`, Android uptime 266 s** at that point:
mainline hung within seconds of the cable change and the hardware watchdog reset it, so the charger session ran in
Android/hboot and the tmpfs log was lost. The eMMC rolling record was stale (ends at uptime 316 s, the logger was past
850 s), so no kernel log of the hang. Unknown yet: is it the USB unplug itself (gadget disconnect / VBUS loss) or the
charger plug (DCP detection, bq24190/palmas VBUS interrupts)? **Blocker for pmOS** (plugging in a charger must work).
Next: stream the charge log and /proc/kmsg over WiFi (tablet `nc -l`, host `socat` connects out; ufw on the host),
then separate (a) unplug + replug to the laptop from (b) unplug -> wall charger.

**Parked 2026-10-23 12:20 (user):** fix later, pmOS install comes first. Until then: charge with the tablet off or in
Android, or keep it on the laptop cable while mainline runs; do not move the cable while mainline is up. The WiFi
streaming setup above (tablet `nc -l -p 5555/5556`, host `socat TCP:192.168.1.100:<port> -`) is the plan for the retest.
