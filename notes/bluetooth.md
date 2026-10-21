# Bluetooth on flounder — working state

Last updated: 2026-10-22 · branch `nexus9` · kernel `usb-bringup` @ `6988accc2`
Full cycle-by-cycle history (n9bt1 … n9bt101, ~900 lines): `archive/bluetooth-log-2026-10-17_21.md`.

## Status: WORKS (hci0 up, radio hears devices)

- BCM4350C0 (Broadcom BCM4354 combo), UART `ttyTHS2` (serial@70006200), firmware
  `brcm/BCM4354.hcd` (= Android's `bcm4350c0.hcd`, sha256 `050d25eb…`).
- 5 consecutive/repeat boots: hci0 registers with firmware build 0690, no
  timeouts. LE scan (`tools/miniroot/btscan-min.c`) heard 20 advertising events
  from 9 devices in ~11 s. Classic inquiry heard nothing (not verified).
- **Not yet done:** BlueZ pairing / audio streaming to a real device (needs a
  normal userspace), Wi-Fi + BT together in one image.

## Root cause (what cost two days)

The BCM4354 is a Wi-Fi/BT **combo**. The BT firmware only behaves while the
**WLAN side is alive**. After Launch RAM (the firmware download) the chip was
"deaf for ~4-5 s and only answered Reset" whenever WLAN was dead — and in every
test image the Wi-Fi SDIO card never enumerated, because the DT held WL_REG_ON
high with an always-on regulator from the very start while the SDIO scan ran
once at host probe, racing the 32 kHz LPO (Palmas `clk32kg`).

## The fix (kernel commit `bd93f7930` in `~/code/linux-flounder`, local only)

1. DT: replace the always-on `wifi-reg-on` regulator by `mmc-pwrseq-simple`
   (`pwrseq_wifi`: `clocks = <&palmas_clk32kg>` as `ext_clock`, reset-gpios
   X7, `post-power-on-delay-ms = 300`), `mmc-pwrseq = <&pwrseq_wifi>` on mmc1.
   Order: LPO on -> WL_REG_ON -> 300 ms -> SDIO scan.
2. `hci_bcm`: power the chip in `bcm_probe` **before** serdev opens the UART
   (otherwise the open port sees the unpowered chip's TX low and only one reply
   ever arrives).
3. Everything else is upstream `hci_bcm`/`btbcm`; DT compatible
   `brcm,bcm4335a0` (3 Mbaud download in 0.4 s), BT_REG_ON (PR1) active
   **high** as `shutdown-gpios`, BT_WAKE (PEE1) `device-wakeup-gpios` active low.
   Palmas `clk32kg` boot-enabled (`ti,clock-boot-enable`, `clk-palmas` patch).

## Evidence, trimmed

```
launch RAM ok 22.04 | post-launch Reset ok 22.40 | fc18 ok 22.41 | hci0 up 23.5 s   (n9bt90, WLAN alive)
same boot with the old DT (no SDIO): Reset answered 4.2 s after launch, fc18/0x1001 lost
Android reference (logcat): launch -> 115200 -> 100 ms -> Reset+fc18 answered within ~100 ms
```
Android sequence (REA of `libbt-vendor.so` `hw_config_cback`, sha256 `5890605f…`):
`Reset -> fc18(3M) -> 0c14 -> fc2e -> records(…fc4e) -> 115200 -> 100 ms -> Reset -> fc18 -> 3M -> fc01`.
The kernel sequence already matched; the missing piece was WLAN power sequencing.

## Dead ends — do not retry

command order, post-launch delays (5 s / 2 s only "work" when WLAN is dead and
mask the real cause), BT_WAKE polarity (high/low identical), spacing of commands,
32 kHz LPO register (Palmas CLK32KG_CTRL d4=07 same as Android), the audio 32 kHz
node, UART runtime PM (already `on`), hardware flow-control toggling, serdev vs
tty/N_HCI (same behaviour), Wi-Fi power GPIO level (191 high in both), loading
brcmfmac first (card needs only the power sequence, not the driver).

## Tools

`tools/bt-bootloop.sh N` (boot `n9bt<N>` until a fresh record), `tools/read-record.py`,
`tools/bootimg-swap-ramdisk.py`, `tools/stage-modules.sh`, `tools/n9sh.sh`,
`tools/miniroot/btscan-min.c` (`/etc/bt-scan`: LE scan + HCI monitor trace),
`tools/image2elf.py` (REA of the Android kernel). Patches:
`patches/linux-flounder-series/`.

## Next

1. BlueZ in a real rootfs: scan, pair, A2DP/AVRCP to earbuds.
2. Confirm classic inquiry; Wi-Fi + BT coexistence.
3. Upstream: DT pwrseq + probe-time power (see the series README for nits;
   probe-time power should become a per-compatible quirk).
