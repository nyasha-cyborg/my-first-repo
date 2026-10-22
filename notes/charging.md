# Charging under mainline

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
