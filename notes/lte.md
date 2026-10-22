# LTE modem — research notes (read-only, Android side)

Started 2026-10-22. Nothing here has been tried on mainline yet.

## What the modem is (evidence from the running Android kernel + userland)

- Qualcomm **MDM9k-class** modem on a **HSIC** link, not USB-attached to a hub:
  Android kernel strings `qcom_usb_modem_power`, `mdm_hsic_phy_*`,
  `proc_mdm9k_status`; platform device `qcom_usb_modem_power`; kernel threads
  `qcom_usb_mdm_queue`, `mdm_recovery_queue`, and several `MDM2AP_*` IRQ threads.
  debugfs entries seen earlier: `ks_bridge`, `ghsic_ctrl_xport`,
  `ghsic_data_xport`, `hsic_sysmon`, `rmnet_usb_ctrl`, `mdm_dbg`.
- HSIC port is `tegra-ehci.2` (the only USB device visible in Android right now is
  the EHCI root hub `usb1`; **no modem enumerated**).
- Control GPIOs (from `/sys/kernel/debug/gpio` in Android): `AP2MDM_WAKEUP` (113),
  `AP2MDM_STATUS` (114), `AP2MDM_ERRFATAL` (115), `AP2MDM_IPC1` (116),
  `AP2MDM_VDD_MIN` (118), `AP2MDM_CHNL_RDY_CPU` (135), `AP2MDM_PMIC_RESET_N` (221),
  and inputs `MDM2AP_WAKEUP` (149), `MDM2AP_STATUS` (150), `MDM2AP_ERRFATAL` (168),
  `MDM2AP_HSIC_READY` (169), `MDM2AP_IPC3` (144), `MDM2AP_VDD_MIN` (226).
- Partitions with modem-looking names: `MD1`, `MD2`, `WDM` (plus `EF1`, `EF2`
  = EFS copies). Not mounted in Android.
- Props: `ro.baseband=ROW`, `ro.baseband.arch=mdm`, `rild.libpath=
  /vendor/lib64/libril-qc-qmi-1.so`, `rild.libargs=-e wwan0`.

## State of this unit

- The ROM here is LineageOS. **No Qualcomm RIL/QMI blobs are installed**:
  `/vendor/lib64` has only `libril.so` / `libreference-ril.so` / `librilutils.so`,
  no `libril-qc-qmi-1.so`, no `mdm_helper`, `ks`, `qmuxd`, `netmgrd`, `rmt_storage`.
  No `wwan0` interface; `gsm.network.type = Unknown`, no operator. So LTE is
  **not working in Android on this unit either**, and the Android side cannot be
  used as a working reference for the modem bring-up sequence.
- Modem firmware is not on a mounted partition (`/firmware` absent); it would
  have to come from the stock Google factory image's radio files (not pulled yet).

## What mainline would need (unverified plan)

1. HSIC host port on `tegra-ehci.2` enabled in DT (Tegra124/132 USB3 pads / HSIC pad).
2. Modem power/reset sequence on the AP2MDM_* GPIOs, derived from the Android
   `qcom_usb_modem_power` driver (REA the Android kernel as done for audio).
3. Firmware download: Qualcomm HSIC modems are normally booted by a userspace
   helper (`mdm_helper`/`ks` pushing images over `ks_bridge`/Sahara); that needs
   the proprietary modem images and helper behaviour.
4. After boot: QMI over USB (`qmi_wwan`/`option` class drivers) + ModemManager.

## Next (when picked up)

- Pull the stock factory radio images (user's call; needs a download).
- REA `qcom_usb_modem_power` (GPIO order, delays) in the Android kernel Image with
  the kallsyms recovery from `stability-debug.md`.
- Check the DTS for an existing HSIC/modem node and `tegra-ehci.2` equivalent.


## 2026-10-22 18:30 — REA of the Android kernel modem driver (`qcom_usb_modem_power`)

Artifact: running Android kernel Image, symbols via the kallsyms recovery
(`stability-debug.md`); windows `mdm.elf` 0xffffffc0004db940-0xffffffc0004df000
(driver), `mdmpow.elf` 0xffffffc0000a2700-0xffffffc0000a3000 (board power
helpers), `mdmboard.elf` 0xffffffc000df2d00-0xffffffc000df3500 (board init).

**Registration is conditional.** `flounder_mdm_9k_init` only registers the
`qcom_usb_modem_power` platform device when `is_mdm_modem()` (= `get_modem_sku()`
is 1 or 2) is true; `set_radio_image_status` parses a `T1.xx` radio-image string.
Platform data is not in the DT (the stock DT has only the rails `vdd_5v0_mdm`,
`vddio_hsic`, `avdd_hsic_com`, `avdd_hsic_mdm`): the GPIO numbers come from board
code. The Android debugfs GPIO names give the numbers (see the table above).

**Platform-data layout** (offsets into the pdata the driver reads; mapping
inferred from which IRQ thread / GPIO helper uses each field):

| pdata off | role | GPIO |
|---|---|---|
| +0x18 | MDM2AP_ERRFATAL (irq, `errfatal_thread`) | 168 |
| +0x1c | AP2MDM_ERRFATAL | 115 |
| +0x20 | MDM2AP_STATUS (irq, `status_thread`) | 150 |
| +0x24 | AP2MDM_STATUS | 114 |
| +0x28 | MDM2AP_WAKEUP (irq, `wake_thread`) | 149 |
| +0x2c | AP2MDM_WAKEUP | 113 |
| +0x30 | MDM2AP_VDD_MIN (irq) | 226 |
| +0x38 | MDM2AP_HSIC_READY (irq) | 169 |
| +0x3c | AP2MDM_PMIC_RESET_N | 221 |
| +0x48 | MDM2AP_IPC3 (irq) | 144 |

(offsets +0x34/+0x40/+0x44/+0x4c = AP2MDM_VDD_MIN 118, IPC1 116, CHNL_RDY_CPU 135
not confirmed.)

**Power-on (`modem_power_on`)**: AP2MDM_WAKEUP = 0; AP2MDM_PMIC_RESET_N = 0;
sleep 5-10 ms; PMIC_RESET_N = 1; wait 40; AP2MDM_STATUS = 1; wait 40; wait 200.
(The wait helper's unit was not resolved; likely ms.)
**Power-down (`modem_power_down`)**: PMIC_RESET_N = 0; wait 4000.
**Subsystem powerup (`mdm_subsys_powerup`)**: AP2MDM_ERRFATAL = 0, AP2MDM_STATUS = 1,
then waits up to 60 s for the modem to report status (`MDM2AP_STATUS`) and later
`MDM2AP_HSIC_READY`; on ready the driver loads the HSIC host
(`tegra_usb_host_load` / `tegra_usb_host_reset`) and raises CPU frequency
(`cpu_freq_boost`) during enumeration. Panic/errfatal handlers reset the modem.

Implications for mainline: the electrical bring-up is small (6-8 GPIOs and the
rails); the hard part is still the userspace firmware boot (`ks_bridge` /
Sahara) and having the modem images. Open: who enables `vdd_5v0_mdm`, and the
HSIC pad/PHY setup in mainline Tegra124/132 (`tegra-ehci.2`).

**Raw partition reads were blocked** by the permission classifier (`dd` of
`MD1`/`MD2`/`WDM` from the device); not worked around. Needs the user's explicit
go-ahead; EF1/EF2 (IMEI/EFS) must never be copied.
**Official downloads**: Google's developer pages list only a generic AOSP
flounder image (`aosp_flounder-img-3458595-*.zip`, no radio); the Nexus 9
factory images are no longer on the public factory page.

## 2026-10-22 18:45 — more REA + what mainline lacks

- `mdm_status_changed` (MDM2AP_STATUS edge handler) is a small state machine:
  status high = modem running (sets flag, notifies the driver), status low after
  running = modem went away -> restart path (`mdm_fatal`, ramdump/recovery, calls
  the board `ops` callbacks). `mdm_hsic_ready` just latches MDM2AP_HSIC_READY = 1
  into the driver state; the HSIC host is loaded after both are seen.
- HSIC port = the third EHCI instance, `tegra-ehci.2` = USB3 controller
  `usb@7d008000` (`phy3`). **Mainline has no Tegra HSIC PHY support**:
  `drivers/usb/phy/phy-tegra-usb.c` implements UTMI/ULPI only (the `hsic` value
  exists in the binding enum but no code; only a `UHSIC_RESET` bit is touched).
  `tegra132.dtsi` declares `usb@7d008000`/`phy3` as `utmi`, status disabled, and
  the flounder DT does not enable it. So an HSIC PHY driver (port of the vendor
  `tegra_usb_phy` HSIC code: pad power, strobe/data trim, tristate, calibration)
  would have to be written before the modem could even enumerate.

### LTE feasibility, honest summary
1. GPIO/rail power sequence: small, known (see above).
2. **HSIC PHY driver for Tegra124/132: missing in mainline, the largest kernel job**
   (REA of the vendor HSIC PHY code in the Android Image would be the source).
3. Modem firmware boot over `ks_bridge` + the proprietary images: userspace,
   needs the modem images (device partitions `MD1/MD2` or a Google download) and
   knowledge of the Sahara/kickstart flow; the Android ROM on this unit does not
   ship the helper, so no working reference.
4. Then QMI (`qmi_wwan`) + ModemManager: mainline already supports.
Estimate: several focused sessions for 1+2, open-ended for 3. Risk to hardware
is low if EFS (EF1/EF2) is never touched and no modem partition is written.

## 2026-10-22 19:00 — REA of the vendor HSIC PHY (`uhsic_phy_power_on`, `uhsic_phy_open`)

Window `uhsic.elf` 0xffffffc000612a00-0xffffffc000614f00 of the Android Image.
Register offsets are relative to the USB controller base (HSIC = `usb@7d008000`);
the UHSIC block sits at +0xc00. Sequence from `uhsic_phy_power_on` (decompiled,
operation order kept; delays are the `udelay` arguments, ns/us not resolved):

```
UHSIC_PADS_CFG? (+0xc20): r = rd; wr(r & 0xfffff99b); wr((r & 0xfffff99b) | 0x89)
+0x400 (SUSP_CTRL): |= 0x4000 ; delay 0x10c7 ; |= 0x80000
+0xc08 |= 0x23040        +0xc0c |= 0x12        +0xc10 &= ~0x200
+0xc14 |= 0x80           +0xc18 |= pdata.byte5 << 2     (tx rtune/slew)
+0xc04 |= (pdata.byte4 & 0x1f) << 14 | (pdata.half8 & 0xfff)  (pll/timing trims)
+0x400 &= ~0x4000 ; delay 0x10c7
if the controller-clock-status bit (CAR 0x1fc / 0x284 reg, bit 24 / bit 0) is clear:
    +0xc20 &= ~0x8
+0xc20 &= ~0x10 ; delay 0x1a36f ; +0xc20 |= 0x10      (pad/ldo enable pulse)
+0xc2c |= 0x1000
+0x400 |= 0x20 ; +0x400 &= ~0x20
+0x1f8 |= 3 ; +0x1b4 = (v & 0x9ffffff) | 0x84000000 ; +0x174 &= 0xff9fffff
+0xc10 |= 0x40 ; +0xc1c = (v & 0xff00f0ff) | 0xa00
poll +0x400 for bit 7 (0x80) within 0x9c4 us  -> error "uhsic PLL/ready timeout" (-110)
then bring up the host controller (usb_phy_bringup_host_controller), poll
+0x174 (PORTSC) until bits 0xc0 clear (25 ms), clear +0xc34 bit 0, restore +0xc20 bit 3,
sleep 10-11 ms (25-26 ms in the irq-off path), poll +0x130 (USB_STS?) bit 0, finish
with +0x154 = 0x100000 (USB_PORTSC?? ) -- exact register names still to map.
```
`uhsic_phy_open` picks a per-board trim table (4 entries at 0xffffffc000f81240,
keyed by a regulator/chip id) and toggles the controller clock/reset (calls at
+0xb8/+0xb0). Pad rail handling is separate (`hsic_pad_enable`,
`hsic_pad_disable`, `hsic_power_rail_disable` in the vendor PHY, window
0xffffffc0005dfc00-0xffffffc0005e0e00 not yet decompiled).

Porting plan: add a `tegra_hsic_phy` set of ops to `phy-tegra-usb.c` (new
`phy_type = "hsic"` branch) with these register writes expressed with the
mainline `UHSIC_*` names from the Tegra TRM / vendor headers, plus the `vddio_hsic`,
`avdd_hsic_com`, `avdd_hsic_mdm` regulators and `vdd_5v0_mdm` in the flounder DT.
Without hardware access to the modem this can only be validated by seeing the
EHCI port connect when the modem is powered (modem GPIO sequence above).

## 2026-10-22 19:15 — correction: HSIC pad side exists in mainline (xusb-padctl)

`hsic_pad_enable` / `hsic_pad_pupd_set` (vendor window 0xffffffc0005dfc00-
0xffffffc0005e0e00) write the **XUSB padctl** HSIC registers:
`HSIC_PADx_CTL0` at 0xc0 + 4x (tx slew/tune nibbles), `CTL1` 0xc8 + 4x (RPU
strobe/data bits, 0x480 / 0x180 pull-up/-down patterns), `CTL2` at 0xd0 + 4x, and
`0xe0` (trk ctl) / `+4` (bit `0xe + pad` = pad enable). Mainline already
implements these in `drivers/phy/tegra/xusb-tegra124.c` (`XUSB_PADCTL_HSIC_PADX_CTL0..`,
`tegra124_hsic_phy_ops`), and `tegra132.dtsi` has the `padctl` node (flounder DT
enables it for the USB2 lanes). So the pad half is a DT problem (add an
`hsic-N` lane + `vddio-hsic` supply), not new code.

What is still missing is the **controller-side UHSIC block** at +0xc00 of
`usb@7d008000` (the register recipe in the previous section): mainline
`phy-tegra-usb.c` has no HSIC (`phy_type = "hsic"`) implementation.
Revised kernel work list for LTE: (1) DT: HSIC lane + rails, (2) new UHSIC ops in
`phy-tegra-usb.c`, (3) modem GPIO sequence (tiny driver or `gpio-hog` +
userspace script), (4) firmware download. (1) and (3) are small, (2) is moderate,
(4) is the unknown.

## 2026-10-22 18:30 (device time 05:30) — FIRST HARDWARE RESULT: the modem answers

Tool `tools/miniroot/modem-gpio-min` (gpio chardev v2, freestanding; modes `read`,
`on [secs]`, `hold`), image `n9modemA` (kernel g5d830bfca033). Rails already on in
mainline: `vdd-out2-5v0` 5 V (the `vdd_5v0_mdm` consumer), `avdd-dsi-csi` 1.2 V
(feeds `vddio_hsic`, `avdd_hsic_com`, `avdd_hsic_mdm`).

- Before: all MDM2AP_* inputs low (STATUS/HSIC_READY/ERRFATAL/WAKEUP/IPC3/VDD_MIN = 0).
- Ran the vendor sequence (all AP2MDM outputs low; PMIC_RESET_N low 10 ms -> high;
  40 ms; AP2MDM_STATUS high; 240 ms): **MDM2AP_HSIC_READY = 1 within 1 s and stayed 1
  for the 30 s watch, and still 1 after the tool exited and released the lines**.
  MDM2AP_STATUS stayed 0, no ERRFATAL.
- Interpretation: a modem is fitted and powers up; it signals "HSIC ready" (its HSIC
  PHY/boot ROM is up) but never reports STATUS (= software booted), consistent with a
  Qualcomm boot ROM waiting for the firmware download over HSIC (QDL/Sahara,
  `boot_hsic` driver in the Android kernel). So the next barrier is the AP-side HSIC
  host: `usb@7d008000` needs the missing UHSIC PHY support to see the modem as a USB
  device (expected: `05c6:9008`-style download mode).
- Safe state: nothing written to storage; the modem stays powered until a reset or
  power-cycle (HSIC_READY still high after the tool exited).

## 2026-10-22 18:45 (device 05:45) — HSIC host enumerates a USB device from the modem

Kernel `g95115d84d8b8` (linux-flounder: new HSIC mode in `phy-tegra-usb.c`, HSIC pad
lanes + `usb@7d008000` host + `phy3` hsic in the flounder DT; image `n9hsicC`).
- PHY power-on works: `SUSP_CTRL=0x000809c0` (CLK_VALID set), `PADS_CFG1=0x91`,
  `DEVLC=0x86000202` (PTS = HSIC), no timeout. (Reading the UHSIC registers from
  outside the driver with `regdump.ko` **hung the tablet** — the watchdog rebooted it;
  use in-driver prints.)
- After the modem power-on (`modem-gpio-min hold`, HSIC_READY = 1) the USB core logs
  `usb 1-1: new high-speed USB device number 3 using ci_hdrc` repeatedly, then
  `device descriptor read/64, error -71` and `device not accepting address N, error -71`.
  So the modem is **detected as a high-speed device on the HSIC port**; enumeration
  fails at the first control transfers with EPROTO = a signalling/tuning or timing
  problem. Next: HSIC pad trims (xusb-padctl `HSIC_PADx_CTL0..2`: rx strobe/data trim,
  tx rtune/slew, termination) from Android's values, and the vendor host bring-up
  quirks (`usb_phy_bringup_host_controller`).

## 2026-10-22 19:05 (device 06:05) — HSIC tuning experiments, no enumeration yet

Kernel `ge846893ae984` (image `n9hsicE`), built with the new `tools/build-test-image.sh`.
Patches exported to `patches/lte-wip/` (see its README).

Observed with the modem powered (HSIC_READY = 1) in either order (host first, or modem
first then `unbind`/`bind` of `7d008000.usb` — the vendor order is modem first):
- Pad registers after `tegra124_hsic_phy_power_on`: `ctl0=0x88 ctl1=0x480 ctl2=0
  trk(0xe0)=0 mux=0` for both lanes; PHY: `susp=0x809c0 pads1=0x91 pads0=0x8a88
  misc0=0x44f8e devlc=0x86000202`.
- `usb 1-1: new high-speed USB device` then `device descriptor read/64, error -71`,
  `device not accepting address N, error -71`, `unable to enumerate USB device`.
  A connect is seen (PORTSC CCS) and speed detected, the first control transfer dies.
- Tried, no effect (each = unbind/bind + 4-5 s, `phy_tegra_xusb` module parameters):
  rx strobe/data trim 0/2/4/7/10/15; tx rtune n/p over {0,4,8,12,15}; strobe trim
  0..31 in steps of 3; powering both HSIC lanes (hsic-0 and hsic-1).

Ideas not yet tried (most promising first):
1. (tried: vendor final `ctl1 = 0x488` via `hsic_pd_trx=1`, no effect.) **HSIC tracking clock**: mainline Tegra124 has no `hsic_trk` clock (no entry in
   `clk-tegra124.c` / dt-bindings) and the xusb HSIC lane code has no tracking /
   calibration step; the vendor sets the STRB_TRIM register (0xe0) from board data and
   ends `HSIC_PAD_CTL1` with bit 3 (PD_TRX) set after a 25-50 us delay (mainline leaves
   it clear). Try the vendor final value `ctl1 = 0x488` and a `trk` clock.
2. Vendor host quirk `usb_phy_bringup_host_controller`: host reset, PORTSC
   `PP`, a PORTSC test-control toggle (PTC = 5 then 0), then wait CCS/PE, then suspend
   the port; the generic chipidea path does none of it. Could matter because HSIC has
   no chirp handshake.
3. Board pad table of the vendor xhci driver (`hsic_pad_enable`: rx strobe/data trim,
   tx rtune/slew, `trk` start timer) lives in vendor board data not in the DT; find it
   in the Image (`tegra_xusb_pdata`) to get the real values.
4. Modem side: AP2MDM_WAKEUP / VDD_MIN lines untouched; the boot ROM may need a
   specific wake handshake; the vendor `qcom_usb_modem_power` driver also runs
   `mdm_hsic_phy_*` callbacks that are mostly logging.
5. The device resets the tablet if registers of the UHSIC block are read from outside
   the driver (`regdump.ko`); only in-driver dumps are safe.

The tablet is left in Android; the modem power GPIOs fall back on reboot.

Later (19:10): also tried the vendor `_usb_phy_init` writes (`+0x498 |= 0x30`,
`USBMODE &= ~0x10`, `DEVLC &= ~BIT(28)`; image `n9hsicG`, kernel `g9282a7e23cae`):
same -71 failure. Remaining untried: HSIC tracking clock/calibration (no `hsic_trk`
clock in mainline Tegra124), the vendor board pad table values, the vendor EHCI
HSIC port-reset special handling (vendor `ehci-tegra` hub control, not read yet),
and checking that chipidea actually forces `PFSC` for `phy_mode = hsic`.

## 2026-10-22 21:10 — vendor EHCI paths ruled out; trying the xHCI controller

- `tegra_ehci_hub_control` (vendor) is generic: after SetPortFeature(RESET/POWER) it just
  calls the PHY `bus_reset` / `port_power` hooks; nothing HSIC-specific. `tegra_usb_phy_open`
  (vendor) acquires only the usual clocks; no `hsic_trk` clock on the EHCI path.
- Found a bug in my port: chipidea's Tegra glue calls `usb_phy_set_suspend()` on LPM
  transitions, which re-ran the whole HSIC power-on/off. Made it a no-op for HSIC
  (`g7ac2bc15fd19`, image `n9hsicH`); enumeration still fails with -71.
- Vendor `_usb_phy_init` writes (0x498, SDIS, DEVLC bit 28) added: no effect.
- Alternative: the Tegra124 xHCI controller also owns the HSIC lanes and mainline has full
  HSIC port support in `xhci-tegra` + `xusb-tegra124.c`. Set up in the DT (lane function
  `xusb`, `usb@70090000` with phys `hsic-0/hsic-1` and the 8 supplies mapped to
  `avdd_pll` / `avdd_usb` / `vdd_1v8`), firmware `xusb.bin` in the ramdisk. Result so
  far: the xHCI controller loads the firmware and registers two buses (USB 2 and 3.0),
  both HSIC pads powered by xusb (`mux=0xc000`). **Not yet tested with the modem powered**
  (the permission check blocked `modem-gpio-min hold` at that point; the same command
  had been allowed many times before).

## 2026-10-22 21:30 — xHCI route result

Image `n9xhciA` (kernel `g8b0d00cb9ee1`), modem powered with `modem-gpio-min hold`
(HSIC_READY = 1, STATUS = 0): xHCI debugfs (`/sys/kernel/debug/usb/xhci/70090000.usb/
ports/port01..08/portsc`) shows all eight ports `0x0a0002a0` = RxDetect, PP, **no
connect on any port**, no USB device appears. So the xHCI route does not even see the
modem (no HSIC idle/connect handshake seen), while the EHCI route does see a connect and
fails at the first control transfer (-71). The EHCI route is the closer one; the xHCI DT
experiment is committed but should be reverted when going back to EHCI.
Missing observability: `CONFIG_DYNAMIC_DEBUG` is off in this kernel, no logic analyzer.
Permission-check note: during this experiment the auto-mode classifier blocked
`modem-gpio-min hold` twice and driver unbind/bind + dyndbg once; the user explicitly
approved the power-on (risk discussed in the chat), it then ran fine.
