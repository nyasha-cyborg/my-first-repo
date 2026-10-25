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

## 2026-10-22 21:55 — the EHCI "connect" is a phantom; vendor bring-up quirks tried

- REA `tegra_ehci_probe` (vendor): nothing HSIC-specific (platform-data bytes, phy open,
  usb_add_hcd). `tegra_usb_phy_power_on.part.6`: enables regulator + three clocks, then
  runs the PHY ops wrapped in board pre/post hooks. The board hooks `mdm_hsic_phy_init/
  open/pre_resume/...` only log (and timestamp). No hidden register work there.
- `usb_phy_bringup_host_controller` (vendor, `uhsic_phy_*`): USBCMD reset, USBMODE host,
  DEVLC PTS=HSIC, PORTSC.PP, **PORTSC.PTC = 5 (Force_Enable_HS) for ~43 us then 0**
  (only if ASYNCLISTADDR == 0), wait CCS and PE, clear USBSTS PCI, suspend the port.
  Mirrored in `hsic_phy_port_power()` (kernel `ga8c25f1bca64`, image `n9hsicP`,
  param `hsic_force_hs`): PORTSC goes 0x1005 (PP|PE|CCS) but enumeration still fails
  with -71. (The wait helper sleeps under the hub-control spinlock: "scheduling while
  atomic" splat; harmless, needs a `readl_poll_timeout_atomic` if kept.)
- `vddio_hsic` = Palmas LDO5 `avdd-dsi-csi` (1.2 V, always-on): rail is fine.
- **Control experiment (decisive): with the modem NOT powered (cold Android boot,
  `modem-gpio-min read` = all inputs 0, HSIC_READY = 0) the EHCI port reports exactly the
  same thing: CCS=1, line state J (PORTSC 0x00601801), "new high-speed USB device",
  `device descriptor read/64, error -71`. UHSIC regs 0xc04-0xc34 are identical with the
  modem on and off.** So the "connect" the whole -71 chase was based on is produced by
  the controller's own pad pulls (UHSIC_PADS_CFG1 = 0x91) and says nothing about the
  modem. Every earlier "no effect" result (trims, strobe, PD_TRX, vendor init writes,
  pll_u_480m, force-HS) was measured against a link that may not have a device on it.
- The xHCI route (real HSIC idle detect) saw no connect with the modem on: consistent
  with the modem not driving HSIC idle at all (or the pads not reaching it).
- Vendor `mdm_subsys_powerup` waits up to 60 s for MDM2AP_STATUS = 1 before it loads the
  HSIC host; in all tests STATUS stays 0 (HSIC_READY = 1). So the modem may not be in the
  state where it drives HSIC. Open: what raises STATUS (boot-ROM download stage?).
- Android on this unit: `androidboot.baseband=ROW`, vendor kernel registers the modem
  (`mdm_init: Registering mdm modem`, all AP2MDM_* out low, PMIC_RESET_N low): the SKU
  has a modem but Android here never powers it (no mdm_helper in the ROM).

## 2026-10-22 22:10 — PMC USB_AO pad isolation: candidate fix built, NOT yet tested

- Vendor `uhsic_powerup_pmc_wake_detect`/`uhsic_setup_pmc_wake_detect` (REA, window
  0xffffffc000783df8-0xffffffc000784700): at HSIC power-up clear PMC `USB_AO` (0xf0)
  nibble 4 (bits 19:16; nibble 3 = bits 15:12 for the other HSIC index) and PMC 0x284
  bit 0 (0x1fc bit 24 for the other index); setup sets PMC 0x29c bit 0 and 0xec bit 1.
- Mainline `tegra_usb_phy_configure_pmc()` only touches VBUS/ID detector bits of the
  instance in non-host modes, so for a host-mode HSIC instance nothing is cleared.
- Live read on mainline (image `n9hsicQ`, modem off): `PMC_USB_AO = 0x000ffff3`
  (nibbles 1-4 all set = pad isolation on), PMC 0xec = 0x2. Clearing bits 19:16 live
  via debugfs poke changed nothing on the already-failed port (PORTSC still 0x601801).
  The needed test is a boot where it is cleared BEFORE the hub brings the port up.
- Kernel `g189353253b78` (image `n9hsicR`): `hsic_phy_power_on` clears USB_AO[19:12].
  Built, `reboot -f` to Android done, boot of the image was denied by the auto-mode
  classifier (plain `tools/n9boot.sh`, same as earlier allowed boots); not retried.
  To run: `tools/n9boot.sh $B/n9hsicR-stripped.img`, then check dmesg for
  `n9: hsic: cleared PMC USB_AO` and whether `usb 1-1` still appears with the modem off
  (if the phantom connect disappears, the isolation was the cause; then power the modem
  with `modem-gpio-min hold` and see whether a real device enumerates).
- Also still to try if this is not it: PMC 0x284 bit 0 / 0x29c bit 0 / 0xec bit 1 (outside
  the PMC regmap's readable range; needs an in-driver ioremap of PMC).

## 2026-10-22 22:15 — PMC USB_AO isolation released: no effect (dead end)

Image `n9hsicR` (kernel `g189353253b78`, booted by the user after the classifier blocked
my boot): dmesg `n9: hsic: cleared PMC USB_AO[19:12]`, `PMC_USB_AO = 0x00000ff3`
afterwards, modem OFF: the port still reports the phantom connect (PORTSC 0x00601801)
and `device descriptor read/64, error -71`. The isolation bits are not what makes the
connect appear or what breaks enumeration. (Kept in the tree; harmless, matches vendor.)

## 2026-10-22 22:25 — official Google factory images for the LTE Nexus 9 DO exist

(The earlier note that Google lists no Nexus 9 radio was wrong: the live
developers.google.com/android/images page dropped the old Nexus entries, but the archived
copy https://web.archive.org/web/2019/https://developers.google.com/android/images still lists
them and the dl.google.com files are still served.)
- `volantisg` = Nexus 9 (LTE), newest: 7.1.1 N4F27P (Oct 2017)
  https://dl.google.com/dl/android/aosp/volantisg-n4f27p-factory-1e29c858.zip
  857,896,156 bytes, SHA-256 1e29c858d283d75dab5c53eaa6397cd1f8bf4b3dd24efa03fb4b6f153eb899ac
  (HTTP 200 checked with HEAD; also volantisg-nmf26f 858,282,899 B, nrd91n 824,730,733 B).
- `volantis` = Wi-Fi: N9F27M factory `volantis-n9f27m-factory-a0d47736.zip` (and OTA
  `volantis-ota-n9f27m-ad1aee0f.zip`, 817,456,682 B).
- Not downloaded yet (needs the user's OK). Purpose: vendor blobs for REA (`mdm_helper`,
  `ks`, RIL/QMI libs, modem firmware `radio`/`MD1` equivalents) and a restore path.

## 2026-10-22 22:40 — official LTE factory image downloaded and unpacked (the missing modem userspace)

Downloaded (user gave the exact URL): `volantisg-n4f27p-factory-1e29c858.zip` (SHA-256
verified = Google's value) to `~/Downloads/nexus9/google-volantisg-n4f27p/` (zip,
`extracted/`, `raw/` = simg2img'd system/vendor, `vendor-files/` = rdump of vendor
/bin /etc /firmware/mdm). Not flashed. REA `extract_artifact` of the inner image zip gave
boot/system/vendor/recovery/cache; bootloader image = 3.50.0.0143 (same as this unit).
- vendor `/bin`: `ks`, `efsks`, `qcks`, `netmgrd`, `port-bridge`, `qmiproxy`, `qmuxd`,
  `bridgemgrd`, `usbhub`, `usbhub_init`, `diag_*`, `time_daemon`, ... ; `/lib64`:
  `libril-qc-qmi-1.so`, `libqmi*.so`, `libmdmdetect.so`, `libdsi_netctrl.so`, `libidl.so`.
- vendor `/firmware/mdm/image`: `sbl1.mbn rpm.mbn tz.mbn mba.mbn apps.mbn dsp1.mbn`
  (+ `htc*.mbn` stubs, `rcdata_{att,o2,tmo,ul,vzw}.img`) and `radiover.cfg`: the modem
  boot chain the AP pushes over HSIC (Sahara/QDL via `ks`). So the modem has no own flash
  image path: boot ROM waits for sbl1 over HSIC -> this is why STATUS stays 0.
- Next: REA of `ks`/`efsks`/`libmdmdetect` (what device node / protocol, timing, what
  triggers it, which usb VID:PID it expects), and the init rc in boot.img (mdm_helper
  equivalent). Then a userspace Sahara client for mainline once the HSIC link works.

## 2026-10-22 23:00 — REA of the stock LTE userspace: the complete boot flow

Sources: stock `boot.img` ramdisk (`init.flounder.rc`, split by hand: NVIDIA wrapper, Android
header at +256) and `vendor/bin/qcks` (strings; REA open_binary), kernel `mdm_modem_ioctl`.
- `androidboot.baseband` = `ROW` or `US` -> LTE SKU: init enables service
  `kickstart = /vendor/bin/qcks -i /vendor/firmware/mdm/image/ -r /data/qcks/mdm/`, plus
  `qmuxd`, `netmgrd`, `ril-daemon` (libril-qc-qmi-1.so, `-e wwan0`). `N/A` = Wi-Fi only.
  This unit reports `ROW` (so it IS an LTE unit; LineageOS just never starts the stack).
- The kernel does NOT power the modem by itself. `qcks` opens `/dev/mdm` and issues ioctls
  (`GET_MFG_MODE`, `WAKE_CHARM` = bring MDM9K out of reset -> `mdm_modem_ioctl` 0xcc01:
  reset state, enable IRQs, board `power_on` ops = the GPIO sequence I already mirror,
  `NORMAL_BOOT_DONE` 0x4004cc05, `POWER_OFF_CHARM`, `RAM_DUMP_DONE`, `WAIT_FOR_RESTART`,
  `TRIGGER_MODEM_RAMDUMP`).
- Then `qcks` waits for the boot ROM's USB serial port ("COMPORT_SAHARA", PBL 05c6:9008),
  runs the Sahara loader: first `dbl.mbn`/sbl images, then
  `ks -w <dir> -p <port> -s 21:.. -s 23:rpm.mbn -s 22:sbl2.mbn -s 12:dsp2 -s 25:tz.mbn
  -s 30:sdi.mbn -s 31:mba.mbn -s 28:dsp3 -s 8:dsp1.mbn -s 6:apps.mbn -s 29:acdb ...
  -s 16/17:efs1/efs2 -s 32:htcrcust ...`, waits for the 2nd enumeration port, spawns
  `efsks` (EFS server) and sets `ro.hw.ks.ready=1` (starts rild).
- So the whole remaining problem is the first HSIC enumeration of the boot ROM. After that
  everything is standard: mainline `qcserial` handles 05c6:9008, the Sahara protocol is
  open (Linaro `qdl`-style), `qmi_wwan` + ModemManager for the data path.
- Idea (needs the user's OK): run the stock `qcks`/`ks` binaries from the Google image on
  the device under the *vendor* kernel (Android) to see whether the modem enumerates there
  (ground truth for the hardware). Risk: `efsks` talks to EF1/EF2 (modem NV/EFS); would
  only run the Sahara part without `efsks`.

## 2026-10-22 23:40 — ROOT CAUSE OF THE WRONG-LINK CHASE: the modem is on USB2 (7d004000), not USB3

Ran the vendor flow on the device under Android's own 3.10 kernel (user approved):
`tools/miniroot/mdmwake` (static helper: open `/dev/mdm`, ioctl `WAKE_CHARM` = 0xcc01, hold),
no images sent, no `efsks`, no EFS access. Kernel log:
```
[MDM]: mdm_modem_ioctl: Powering on mdm
[MDM]: unload USB host / load USB host      <- tegra_usb_host_reset, tegra-ehci.1
phy_interface: USB_PHY_INTF_HSIC
tegra-ehci tegra-ehci.1: irq 53, io mem 0x7d004000     <- USB2 controller
[MDM]: modem_power_on: Pulling RESET gpio low / high
usb 2-1: new high-speed USB device number 2 using tegra-ehci
usb 2-1: New USB device found, idVendor=05c6, idProduct=9008, Product: QHSUSB__BULK
I: If#=0 Cls=ff Driver=ks_bridge  E: 81(I) bulk 512, 01(O) bulk 512
```
GPIOs at that point: AP2MDM_STATUS=1, PMIC_RESET_N=1, MDM2AP_HSIC_READY=1, MDM2AP_STATUS=0.
=> The boot ROM enumerates fine as the Qualcomm Sahara/QDL device (9008) within 0.35 s of the
reset release, **on `tegra-ehci.1` = `usb@7d004000` (phy2) in HSIC mode**. Vendor numbering:
ehci.0 = 7d000000 (USB1), ehci.1 = 7d004000 (USB2, the modem; platform device is registered
and reloaded by the mdm driver), ehci.2 = 7d008000 (USB3, idle root hub on bus 1).
My earlier note "HSIC port = third EHCI instance tegra-ehci.2 = usb@7d008000 (phy3)" was
WRONG; every HSIC experiment (pads, trims, PMC, force-HS, ...) was on a controller that has
nothing connected, which is why the phantom connect and -71 were independent of the modem.
Fix = move the HSIC setup in the flounder DT (and the test image) from `usb@7d008000`/`phy3` to
`usb@7d004000`/`phy2`; the UHSIC register recipe is the same per controller (+0xc00).

## 2026-10-22 23:50 — MILESTONE: the modem's boot ROM enumerates on mainline (USB2 HSIC host)

Image `n9hsicS` (kernel `g7fd3d31d0c6f`: DT moves the HSIC host to `usb@7d004000`/`phy2`),
`tools/lte-power-test.sh` (run by the user, the classifier blocks the modem power-on from my tools):
```
inputs before: all 0; power on: MDM2AP_STATUS=0 HSIC_READY=1
usb 1-1: new high-speed USB device number 6 using ci_hdrc
usb 1-1: language id specifier not provided by device, defaulting to English
T: Bus=01 Lev=01 Dev#=6 Spd=480   P: Vendor=05c6 ProdID=9008   S: Product=QHSUSB__BULK
I: If#=0 Cls=ff Sub=ff Prot=ff #EPs=2 Driver=(none)     PORTSC=0x1005 (CCS|PE|PP)
```
The earlier -71 with the modem off/on was a controller with nothing attached (USB3). With the
modem off the USB2 controller still shows a phantom "new high-speed USB device" + -71 (pad
pulls), but when the modem is powered a real device enumerates on a later attempt.
The PHY recipe that works is the already-committed UHSIC one (no force-HS, no PMC change needed
-- PMC USB_AO release is vendor-conform and kept). Next: Sahara client (PBL asks for image
ids; `ks -s id:file` list in the qcks notes above), `qcserial`/usbfs, firmware from
`~/Downloads/nexus9/google-volantisg-n4f27p/vendor-files/mdm/image`.

## 2026-10-23 00:10 — Sahara on mainline: stages 21,25,30,23,16,17 served; HTC NV images (REA of qcks)

`tools/miniroot/sahara.c` (usbfs Sahara client) + `tools/lte-sahara-test.sh` (full cycle; runs with
the user's permission rule for the scripts). Observed on mainline (kernel g7fd3d31d0c6f):
- PBL: HELLO, id 21 (sbl1.mbn, 0x2a174 bytes in 0x1000 reads), END ok, DONE_RESP 0.
- then one Sahara session per image on the same link: id 25 tz (ELF pieces), 30 sdi, 23 rpm,
  16 EFS1, 17 EFS2 (answered with a blank image: modem accepts it, END status 0), then id 40.
- id 40 with an all-zero image: `END_IMAGE_TRANSFER id=40 status=6` (header invalid).
- REA of `qcks` FUN_00402284 ("EFS Prepend"): efs1.bin/efs2.bin = `dd` of the EF1/EF2 partitions
  (0xc00 KiB each, never read by us); htc40/42/43/45/46 = [40-byte MBN header stub from
  vendor/firmware/mdm/image/htc*.mbn] + data of the HTC combined partition at offsets
  ssmem 0x0, NV_MFG 0x400, RF_NV 0xc00, USER_DATA 0x800, CDMA_RECORD (other partition) 0x0 (KiB);
  htc44/47/48/49/55/56 = carrier CNV slots: `rcdata_<carrier>.img` dd'd into the partition at
  seek 7168 KiB, then htccnv_<x>.mbn header + data at 0x1c00; `sbl1` variant chosen from the
  mdm9k serial byte in /data/qcks/htcssmem.bin (sbl1.mbn / sbl1_82 / _96 / _92).
- Stub headers (40 B, MBN v3): id 0x28 ssmem size 0x10000; 0x2a NV_MFG 0x80000; 0x2b RF_NV
  0x40000; 0x2d USER_DATA 0x20000; 0x2e CDMA 0x20000; 0x2c/0x2f/0x30/0x31/0x37/0x38 CNV 0x100000.
- Test mode (no tablet storage read): reply to these ids with the real stub header + zero payload
  (blank NV, RAM-only in the modem; efsks is never run so nothing is written back to EF1/EF2).
  Image `n9hsicW`. Real calibration/IMEI would need reading the tablet's HTC partition and
  EF1/EF2: needs the user's explicit go-ahead.

## 2026-10-23 00:50 — THE MODEM BOOTS ITS OS (MDM2AP_STATUS=1) from mainline

Run `lte-run10` (image `n9hsicB2`, `tools/lte-sahara-test.sh`): after the images served earlier,
the modem asked for id 8 (dsp1.mbn, 44 MB: pushed over the USB serial console with
`tools/n9push.py` + `tools/miniroot/rxfile.c`, 4 KB blocks with ACK, checksum OK; the console
runs commands with stdin=/dev/null so rxfile opens /dev/ttyGS0 itself) and id 6 (apps.mbn):
both `END_IMAGE_TRANSFER status=0`. Then (HELLO now with mode=1) the link went silent.
`/tmp/mdm.log` (modem-gpio-min hold, 1 line/s) on the tablet:
```
t+0..22  STATUS=0 HSIC_READY=1 (boot ROM / SBL, Sahara)
t+23     MDM2AP_STATUS=1  HSIC_READY=0   <- first time ever: the modem OS is up
t+54     ERRFATAL=1 (stays 1)            <- modem crash ~30 s after boot
```
Likely cause of the ERR_FATAL: blank EFS/NV (stub images with zero payload) and nobody
answering the EFS sync (`efsks`, the 2nd enumerated port "COMPORT_EFS"). After STATUS=1 the
modem renumerates on USB (new PID); the EHCI port still shows the stale 05c6:9008 device
(PORTSC CCS|PE, 0x1005): the host never saw the disconnect. Next: force re-enumeration (port
reset / power toggle via the tegra-hsic-poke debugfs), identify the new USB PID(s), load
qcserial/option/cdc-wdm/qmi_wwan modules in the test image, and decide about real EFS/NV
(needs the user's go-ahead: EF1/EF2 + the HTC combined partition).

## 2026-10-23 01:20 — blank NV: the modem OS boots then dies; now feeding it the unit's real EFS/NV

Runs 10-14 (blank EFS + stub-header HTC NV): all Sahara stages accepted (21,25,30,23,16,17,40,42,43,45,46,
44,31,8,6), `MDM2AP_STATUS=1` ~7 s after `apps.mbn`, **HSIC_READY stays 0 and no USB device
appears** (PORTSC CCS=0 after a port power-cycle), **ERRFATAL=1 exactly ~32 s after STATUS=1** (t+29 ->
t+61). With blank NV the modem OS never brings its HSIC up and crashes: consistent with it needing real
EFS/RF NV. (A first attempt failed because the script's wait loop used `ps`, which the tablet's busybox
does not have; use `pgrep`.)
User granted (chat, 2026-10-23) reading the tablet's own EF1/EF2/RCA/CDR partitions to give the
modem real data. REA of `qcks` (FUN_00402284 / FUN_00402e44) gives the recipe; partition names (from
the binary): EF1, EF2, RCA (the "HTC combined" partition), CDR (CDMA record), all under
`/dev/block/platform/sdhci-tegra.3/by-name/`, sizes 8/8/8/2 MiB:
- efs1.bin / efs2.bin = first 3 MiB of EF1 / EF2 (dd bs=1024 count=0xc00)
- htcNN.bin = 40-byte stub (htc*.mbn from the image) + 1 MiB of RCA (or CDR) at skip KiB:
  40 ssmem @0, 42 NV_MFG @0x400, 43 RF_NV @0xc00, 45 USER_DATA @0x800, 46 CDMA = CDR @0
  44/47/48/49/55/56 carrier CNV: rcdata_<att|tmo|vzw|spcs|ul|o2>.img is dd'd INTO RCA at 7168 KiB
  (a write by the stock tool; we only overlay it in memory) then 1 MiB is read from 7168 KiB.
Read-only copies (adb exec-out dd, nothing written to the tablet) are in
`~/Downloads/nexus9/modem-private/` (mode 700, OUTSIDE the repo, contains IMEI/calibration: never
commit, never upload). `tools/build-modem-blob.py` builds `mdata.bin` + `sahara-args.txt` there;
`sahara.c` takes `id:path@offset`; `lte-sahara-test.sh` pushes the blob over the serial console and
uses the real args automatically when `sahara-args.txt` exists.

## 2026-10-23 01:55 — run 15: real EFS/NV given (EF1/EF2/RCA/CDR), modem still dies

`lte-run15` (image `n9hsicF2`): dsp1 (44 MB, 200 s) + per-unit blob (17.8 MB, 100 s) pushed over the
serial console (byte counts match; the "CHECKSUM MISMATCH" lines were a pusher bug: it stopped
reading at `sum=` before the hex digits arrived; fixed). All stages status 0, including ids 16/17 with real
EFS. `MDM2AP_STATUS=1`, `HSIC_READY` stays 0, no USB device after a port power-cycle (CCS=0), and
`ERRFATAL=1` arrives later than with blank NV (somewhere between +43 s and +67 s after STATUS=1
instead of +32 s). Real NV changes the timing but not the outcome: the modem OS still never
raises HSIC_READY. Next: REA of the vendor `mdm_fatal` / errfatal / ramdump path and of what else
`qcks` does after Sahara (NORMAL_BOOT_DONE, ioctls) to find what the AP owes the modem.

## 2026-10-23 02:25 — MILESTONE 2: modem OS is stable and enumerates as 05c6:9048 (run 17)

`lte-run17` (image `n9hsicG2`, kernel `g5489f179b56d`): real EFS/NV data (host-built blob) + the new
`modem-gpio-min hold 4` (raises AP2MDM_WAKEUP as soon as MDM2AP_STATUS goes high, as the vendor
board ops `modem_status_changed`/`modem_boot_done` do: REA of mdmpow.elf, gpio at pdata+0x2c) +
faster serial pushes (16 KB blocks with ACK: dsp1 44 MB in 4-8 s, blob 17.8 MB in 2 s).
- All Sahara stages status 0; STATUS=1 at t+28; **ERRFATAL stays 0 for the whole run (>120 s)**
  (earlier: +32 s blank NV, +43..67 s real NV without the wake line).
- HSIC_READY stays 0 (not needed). The host must re-enumerate: `echo 0/1 > usb1/authorized` (the
  stale 05c6:9008 device object stays otherwise; PORTSC pokes had cleared the W1C change bits,
  poke fixed in the kernel `g5489f179b56d`). After the toggle: `usb 1-1: new high-speed USB
  device number 7`, **05c6:9048 "Qualcomm CDMA Technologies MSM"**, 1 config, 500 mA,
  9 vendor-specific interfaces: 0-2 two bulk endpoints each (diag/modem/ks-efs), 3-8 three
  endpoints each (bulk + interrupt: rmnet/QMI-style), no driver bound yet.
- Open: which interface is the EFS server port (stock `efsks` talks to it, saves the modem's EFS back to
  EF1/EF2 -- we must NOT write the partitions), load qcserial/option/qmi_wwan(/cdc-wdm) for these interfaces,
  `modem_nv_write_done` = pulse of the gpio at pdata+0x40 (IPC1?) after the EFS sync.

## 2026-10-23 03:10 — MILESTONE 3: QMI works on mainline (modem reports model/firmware/IMEI)

`lte-run18` (image `n9hsicH2`: kernel `gcb8985407c88` with `qmi_wwan`, `cdc-wdm`, `qcserial` as modules)
+ `tools/miniroot/qmiraw.c` (raw QMUX over cdc-wdm) + `tools/qmi-probe.py` (host driver):
- `modprobe qmi_wwan` before the re-enumeration -> after the `authorized` toggle the 9048 device gets
  `cdc-wdm0..4` / `wwan0..4` (QMI interfaces 4-8). Modem stable (>3 min, ERRFATAL=0, never HSIC_READY).
- CTL: the modem sends a SYNC indication and answers GET_VERSION_INFO with the service table
  (CTL, WDS, DMS, NAS, UIM, ... 0x2b, 0x30, 0xe5).
- DMS: manufacturer `QUALCOMM INCORPORATED`, revision `0.09.30.0105`, model "0", a valid IMEI (so the real
  per-unit EFS/NV blob works; IMEI is NOT recorded in the repo), operating mode value 5.
- UIM card status: card state "error"/no card (probably no SIM inserted), NAS: not registered
  (searching), signal -128. Radio was not switched online (no SIM; left to the user).
Per-boot recipe (all scripted, ~4 min): `tools/lte-sahara-test.sh` (reboot test image, power modem, push
dsp1 + blob over serial at ~5 MB/s, Sahara all stages, auto-wake on STATUS=1, `usb1/authorized` toggle,
modprobe qmi_wwan). Remaining for a usable LTE tablet: (1) turn the cycle into a proper boot service in the
real rootfs (init script running power sequence + a Sahara loader reading the images from
/lib/firmware or the stock vendor image + the EFS/RCA data read from the partitions at boot),
(2) EFS write-back (stock `efsks` saves the modem's EFS to EF1/EF2/EF3; we do not write), (3) SIM +
ModemManager/oFono + wwan0 data path, (4) cleanup/upstreamable HSIC PHY patches.

## 2026-10-23 03:55 — MILESTONE 4: whole bring-up runs on the tablet as one script from a cold boot

- `tools/mdm-data.sh` builds the per-unit Sahara data on the device from the eMMC partitions (GPT names via
  sysfs PARTNAME: EF1/EF2/RCA/CDR; `dd`/`cat` only, read-only; mainline sees mmcblk0 with the Android partition
  numbers: EF1=p21 EF2=p22 RCA=p8 CDR=p23). Output verified **byte-identical** to the host-built blob.
- `tools/mdm-boot.sh` (device side): data -> `modem-gpio-min hold 4` -> wait 9008 -> `sahara` (15 images) ->
  wait STATUS=1 -> `modprobe qmi_wwan` -> hub re-authorize -> 9048 -> `/dev/cdc-wdm0..4`.
- `tools/lte-service-test.sh` = cold-boot test (image `n9hsicI2` has the scripts, /fw stubs, rcdata baked in; only
  dsp1.mbn (44 MB, too big for fastboot boot) is pushed over the serial console): result "modem enumerated as
  05c6:9048: /dev/cdc-wdm0..4", QMI probe identical to run 18 (firmware 0.09.30.0105, valid IMEI).
- Restart without reboot also works (`tools/lte-retry.sh`): `qcserial` must NOT be loaded (it claims the 9008).
- One unexplained tablet hang + watchdog reset while running a long foreground n9sh command; the same steps run
  fine as a background service polled from the host.

## 2026-10-23 04:20 — rootfs packaging drafts

`tools/rootfs/n9-modem.initd` (OpenRC service running `mdm-boot.sh`) and `tools/rootfs/provision-modem-fw.sh`
(extracts the modem images from the official volantisg zip into /lib/firmware/n9-modem). Untested in a
real rootfs (the test image is a ramdisk); paths differ from the test image only by FW/DSP1 variables.

## 2026-10-23 09:10 — SIM inserted: card ready, radio online, not registering (yet)

- Service test (`tools/lte-service-test.sh`) failed twice at the 44 MB `dsp1.mbn` serial push (no ACK at 28 MB / 32 MB, tablet
  then hung ~10+ min; 1.8 GB RAM free, so not memory). **Workaround that works:** `split -b 8M` the file, push each part with
  `n9push.py`, `cat p?? > /tmp/dsp1.mbn` on the tablet (sha256 matched host). Note `/tmp/n9build` is tmpfs and vanishes on host
  reboot: `mkdir -p /tmp/n9build` first, `qmiraw` must be rebuilt (clang line in `tools/miniroot/qmiraw.c`) and pushed.
- `mdm-boot.sh` then ran clean: sahara 15 images, STATUS=1 at t+26, 05c6:9048, cdc-wdm0..4.
- `qmi-probe.py --online`: UIM card status = card present, USIM app state 7 (ready); DMS mode online (0); NAS serving system
  stays reg_state 2 (searching), RAT 8 (LTE), signal ~0, for >2.5 min. Not yet explained: antenna/RF NV, carrier NV (rcdata),
  APN/PLMN, or no coverage. Each probe run leaks a QMI client id (no release).
- Next: NAS get_system_info / PLMN scan, check which rcdata overlay matches the SIM's carrier, check coverage by trying other bands.

## 2026-10-23 09:40 — second SIM: card ready, LTE signal seen, registration unconfirmed

- `lte-service-test.sh` now pushes dsp1 in 8 MB parts + qmiraw and runs unattended end to end (modem enumerated, QMI ok).
- New SIM: USIM ready. `--online` accepted (the replies right after the mode switch are garbage for a few seconds).
  ~30-60 s later: oper. mode 0 (online), NAS RAT 8 (LTE), signal byte 0xbb (= -69 dBm), serving-system reg_state still 2
  (searching), CS/PS detached. So the RF path/antenna works; registration not reached/confirmed yet.
- `qmi-probe.py` leaks one QMI client id per service per run; after ~6 runs alloc returns None. Fix: release clients
  (CTL 0x23) at exit, or restart the modem. Next: NAS get_system_info (0x4d) / PLMN, then WDS start network; check SIM carrier/APN.

## 2026-10-23 10:05 — Skinny NZ SIM: network seen (530-05), still not attached

- Carrier: Skinny (NZ, runs on Spark's network, PLMN 530-05). `qmi-probe.py` now prints all NAS serving-system TLVs and releases its
  QMI clients at exit (client ids no longer leak; the modem was restarted with `lte-retry.sh` to reset them).
- After `--online`: serving PLMN TLV = mcc 530 / mnc 5, RAT LTE, signal ~ -72 dBm (stable over 100 s), but reg_state 2 /
  CS+PS detached. So the modem finds Spark's LTE cell and does not complete attach. Candidates: attach rejected (need NAS
  get_system_info 0x4d for the reject cause), no APN profile / no data call requested, carrier NV (rcdata overlays are US carriers),
  Skinny SIM provisioning. Next: get_system_info, WDS start network with APN `internet`.

## 2026-10-23 10:30 — cause of "camped, not attached": Verizon attach profile; Skinny APN set (attach unconfirmed)

- Service test ran clean from cold (dsp1 in 8 MB parts): sahara 15 images, STATUS=1, 05c6:9048, cdc-wdm0..4.
- `--online` then (+45 s) `--sysinfo`: serving system reg_state 2, CS/PS detached, RAT LTE, PLMN 530-05.
  NAS sys info (0x4d): LTE srv_status 1 (limited), true_srv_status 3 (limited regional), srv_domain 4 (camped),
  network 53005, `is_sys_forbidden` 0. RF band info (0x31): LTE, band enum 0x7e = **B7** (2600). Sys sel pref (0x34):
  LTE band pref 0x7ff5bdf3fff (B1-14, B3/B7/B20/B28 all allowed), mode pref GSM|UMTS|LTE, network sel automatic,
  domain CS+PS. So bands/prefs are not the blocker.
- `--wds wapaccess.co.nz` (start network): QMI error 14 CALL_FAILED, end reason 3 (no service), verbose type 3 / 2001.
- **`--profiles`: default 3GPP profile = 1; all 10 profiles are Verizon (1 `VZWIMS` IPv4v6, 2 `VZWADMIN`, 3 `VZWINTERNET`,
  4 `VZWAPP`, 5 `VZW800`, 6-10 repeat).** The LTE attach PDN uses profile 1's APN, so Spark is very likely rejecting
  the attach (unknown APN). Earlier fix in `qmi-probe.py`: `--sysinfo` used NAS 0x43 (cell location), now 0x34 + 0x31.
- Skinny APN verified on the web (skinny.co.nz settings page): `wapaccess.co.nz`, IPv4, no auth, 530/05.
- `--setapn wapaccess.co.nz` (WDS 0x28 on profile 1, APN + PDP IPv4; RAM-only EFS, efsks never runs) returned 0, then
  low power -> online. **Right after this the tablet console stalled (mode B: gadget enumerated, n9sh no reply)**, so
  the attach result is unknown. The modem restart that follows recovery reverts profile 1 to VZWIMS.
- Next: after recovery rerun `lte-service-test.sh`, `--setapn wapaccess.co.nz` *before* `--online` (avoid the
  mode switch storm), wait 45 s, `--sysinfo`; if attached, `--wds wapaccess.co.nz` then DHCP on wwan0 (raw-ip).
  Persistent fix for the rootfs: set profile 1 at every modem boot (or ModemManager's initial-EPS-bearer APN).

## 2026-10-23 10:45 — MILESTONE 5: registered on Spark LTE, data call connected (Skinny SIM)

- Fix confirmed: rewrite 3GPP profile 1 (attach PDN) from Verizon `VZWIMS` to `wapaccess.co.nz` / IPv4 **while the modem is
  still in low power (oper. mode 5) right after boot**, then `--online`. No extra radio cycle needed.
  Sequence: `lte-service-test.sh` -> `qmi-probe.py --setapn wapaccess.co.nz` -> `--online` -> 45 s -> `--sysinfo --wds wapaccess.co.nz`.
- After 45 s: serving system `01 01 01 02 01 08` = **registered, CS attached, PS attached**, LTE; PLMN 530-05 (network name TLV
  present), LTE sys info srv_status 2 (full service), cell id valid.
- WDS START_NETWORK (APN wapaccess.co.nz, IPv4): result 0, packet data handle 0x04046b10; GET_PKT_SRVC_STATUS = 2 (connected).
- `qmi-probe.py` releases the WDS client at exit, which ends the call: the IP path needs the client kept (or WDS autoconnect).
- Service test: dsp1 parts now retried up to 3x (`n9push.py` exit status checked; the old `| tail -1` hid failures). The
  serial console stalled twice this session (after a low-power/online cycle and mid dsp1 push), each time followed by a
  watchdog reset to Android within ~3-5 min.
- Rootfs: the boot service must set profile 1's APN before going online (per SIM; or let ModemManager set the initial EPS
  bearer APN). The stock EFS is a Verizon carrier config (rcdata/CNV), so other profiles stay VZW.
- Next: keep the WDS client, WDS GET_RUNTIME_SETTINGS (IP/gw/DNS), bring up wwan0 (802.3 + DHCP, or raw_ip + static), ping.

## 2026-10-23 11:00 — MILESTONE 6: IP over LTE works on mainline (ping + DNS through wwan0)

Same boot as milestone 5 (profile 1 APN set before online, registered on Spark 530-05 LTE).
- `qmi-probe.py --wds wapaccess.co.nz --runtime --keep`: call up, runtime settings IPv4 10.238.125.48/27, gw .49,
  DNS 122.56.237.1 / 210.55.111.1, MTU 1500. `--keep` leaves the WDS client allocated (releasing it ends the call).
- **802.3 framing (modem default, WDA 0x21 link layer = 1) does not work:** ARP is answered by the modem
  (02:50:f3:00:00:00), uplink leaves the modem (last-call tx 828 B), but last-call rx = 0 B and wwan0 only sees the ARP replies.
- **Raw IP works:** `--rawip` (WDA SET_DATA_FORMAT 0x20, TLV 0x11 = 2) + `echo Y > /sys/class/net/wwan0/qmi/raw_ip` (link down
  first). Changing the data format **ends the active call** (WDS 0x24 then returns QMI error 15 out-of-call): start the call again
  after the switch. Result: `ping -c 4 1.1.1.1` 4/4 (54-305 ms), `nslookup example.com 122.56.237.1` answered; modem stats
  tx 6 / rx 6 packets.
- wwan0 <-> cdc-wdm0 (wwan1..4 <-> cdc-wdm1..4, unused). Only host routes for 1.1.1.1 and the DNS server were put on wwan0;
  WiFi stayed the default route.

Working order per boot (all from the host, tablet in the n9hsicI2 test image):
1. `tools/lte-service-test.sh`
2. `qmi-probe.py --setapn wapaccess.co.nz` (modem still in low power) -> `--online` -> ~45 s
3. `qmi-probe.py --rawip --keep`; on the tablet: `ip link set wwan0 down; echo Y > .../qmi/raw_ip; ip link set wwan0 up`
4. `qmi-probe.py --wds wapaccess.co.nz --runtime --keep`; `ip addr add <ip>/<mask> dev wwan0`, routes/DNS as wanted.

Next: turn steps 2-4 into the rootfs service (or ModemManager: it does raw-ip, WDS and the initial bearer APN itself, given
`qmi_wwan` + cdc-wdm), HTTP test, longer soak, the console stalls during long serial transfers.

## 2026-10-23 11:30 — MILESTONE 7: data call from the device-side service, cold boot

`APN=wapaccess.co.nz tools/lte-service-test.sh` (image n9hsicI2, mdm-net.sh + qmi-connect pushed to /tmp because the image's
/bin/mdm-boot.sh predates them): mdm-boot as before (boot ROM after ~12 s, 15 Sahara images, 9048), then within 5 s
`qmi-connect`: profile 1 APN error 0, raw IP error 0, online error 0, call up on the first START_NETWORK;
`mdm-net: wwan0 up: 10.245.22.210/30 gw 10.245.22.209 dns 122.56.237.1 210.55.111.1 mtu 1500`, default route via wwan0
metric 200, `ping -I wwan0 1.1.1.1` 4/4 (27-77 ms).
- The DNS check timed out because WiFi stayed the preferred default route and the query to Spark's resolver left via
  wlan0 (Spark resolvers only answer their own customers). Not an LTE problem; with LTE as the only/preferred route, or
  RESOLV=1 with METRIC below WiFi's, it resolves (manual test at 11:00 with a host route via wwan0 worked).
- n9push printed CHECKSUM MISMATCH for the two small files although both ran correctly (pusher quirk; not chased: the
  serial console only matters for the test images, the goal is an installed pmOS).
- For the rootfs: install `qmi-connect`, `mdm-net.sh` next to `mdm-boot.sh` in /usr/lib/n9-modem and set APN in
  /etc/conf.d/n9-modem (tools/rootfs/n9-modem.initd).

## 2026-10-25 15:10 — owner switched back to Android: stock Google 7.1.1 N4F27P flashed (LTE stack present)

- Decision (owner): leave pmOS (3D works but slow/unstable on 1.8 GB; LTE only via our own work); try stock Android first
  for LTE, YouTube-alternatives (NewPipe/SmartTube) and Stremio. LineageOS 16 + vendor-blob transplant is plan B
  (stock vendor files are in ~/Downloads/nexus9/google-volantisg-n4f27p/).
- Flash (host fastboot 37, unlocked bootloader 3.50.0.0143 = factory one, so the bootloader image was NOT flashed):
  `fastboot -w update` fails on this bootloader (`Snapshot cancel FAILED (remote: 'not allowed')`). Worked instead:
  unzip image-volantisg-n4f27p.zip, then `fastboot flash boot|recovery|system|vendor|cache`, `fastboot format userdata`
  (f2fs; plain `erase` only warns). `fastboot reboot` -> Android enumerates (18d1:4ee1 MTP).
- Gotcha: from pmOS, software reboot-to-bootloader (PMC bit + sysrq b) did NOT reach fastboot (hboot ignored it, came
  back as charger-mode pmOS); only Power + Volume Down by hand worked.
- Pmos is gone from the device (userdata formatted); pmOS boot images/rootfs build still in the repo.
- Next: owner finishes the setup wizard, inserts the SIM, enables USB debugging; check `getprop gsm.network.type`,
  `ip link` for wwan0, `getprop gsm.sim.state`.
- 15:30 owner: **LTE works on stock Android 7.1.1** (mobile data up, nothing to configure). Stock vendor stack
  (qcks/qmuxd/netmgrd/ril) is the reference for the pmOS modem flow, now confirmed working end to end on this unit.

## 2026-10-26 00:20 — MILESTONE: LTE modem boots on LineageOS 16 after transplanting the stock vendor LTE files
Owner plan: "update kernel and enable LTE; port security updates later". LineageOS 16 (Wi-Fi build) already ships the init
services (`kickstart`, `qmuxd`, `netmgrd` in /vendor/etc/init/init.rc, `ro.boot.baseband=ROW`) and the 3.10 kernel mdm driver,
but not the Qualcomm files or `rild`.
- Done (reversible, additive): extracted stock `vendor.img` (`debugfs rdump`), pushed 96 files (62 MB) with `adb root; adb remount;
  adb push stage/. /vendor/` — bins (`qcks ks efsks qmuxd netmgrd port-bridge qmiproxy ATFWD-daemon time_daemon irsc_util
  bridgemgrd ds_fmc_appd nl_listener radish dsdnsutil`), libs (`lib64`+`lib`: libqmi*, libril-qc-qmi-1, libdsi_netctrl,
  libnetmgr, libidl, libdiag, libmdmdetect, ...), `/vendor/firmware/mdm/image/*` (24 modem images) + `radiover.cfg`;
  `chmod 755` bins, `restorecon -R`. File list: `notes/android-reference/lte-transplant-files.txt`. Rollback = delete exactly
  those paths (all `comm -13` extras, nothing overwritten) and `rm -rf /data/qcks`.
- Needed by hand: `mkdir -p /data/qcks/mdm; chown system:system; chmod 770; restorecon` (stock init creates it; Lineage's
  /vendor/etc/init/init.rc has the mkdir lines but they ran before the dir was needed / not applied on this boot - check).
- `setprop ctl.start kickstart` (SELinux still Enforcing, no denials): modem powered via /dev/mdm, boot ROM 05c6:9008, Sahara
  uploads all images + efs1/efs2 (wrapper `dd`s EF1/EF2 into /data/qcks), `ks -m -w /data/efs/ -p /dev/efs_hsic_bridge` runs,
  modem re-enumerates as **05c6:9048 "Qualcomm CDMA Technologies MSM"**, kernel registers **rmnet_usb0..3**, `ro.hw.ks.ready=1`.
- Missing for telephony: `rild` (Android 9 `/vendor/bin/hw/rild` not in this build; `libril.so`, `libreference-ril.so` are in
  /vendor/lib64), `android.hardware.radio@1.x`/`deprecated IOemHook` entries in /vendor/etc/vintf/manifest.xml, rild init
  service (`vendor.ril-daemon`), sepolicy for qmuxd/netmgrd/rild, then a SIM test. Raw EF1/EF2/RCA/CDR backups are in
  ~/Downloads/nexus9/modem-private (never commit them).

## 2026-10-26 00:30 — LTE on LineageOS 16: whole telephony stack runs; modem says "No ATR received" (no SIM seen)
- Built `rild` (LineageOS lineage-16.0 hardware/ril rild.c + librilutils, NDK r26d clang aarch64 API 28, linked against the
  tablet's libcutils/libril) -> `/vendor/bin/hw/rild`; `/vendor/etc/init/rild.rc` defines `ril-daemon` (the stock init.rc
  already does `start ril-daemon` when `ro.hw.ks.ready=1`); added `android.hardware.radio@1.1 IRadio/ISap slot1` and
  `radio.deprecated@1.0 IOemHook slot1` to `/vendor/etc/vintf/manifest.xml` (original kept as /tmp copy; diff in
  tools/android/lte/vintf-manifest-radio.diff). Reproduce: `tools/android/lte/install-lte-lineage16.sh`.
- After reboot: kickstart, qmuxd, netmgrd, ril-daemon all `running`, rmnet_usb0..3 up, RILQ (qcril) initialised, Android
  telephony (RILJ/GsmCdmaPhone) talking to it. SELinux still Enforcing; only denial in the LTE path:
  `kickstart` cannot set property `efsks.pid` (harmless so far).
- Result: `qcril_uim_print_card_status: card_error: No ATR received`, `Number of apps: 0`, `SIM absent`, radio unavailable ->
  no SIM detected by the modem (tray empty/unseated, or a SIM the modem cannot read). Needs a SIM in the tray; then check
  `getprop gsm.sim.state`, `gsm.operator.alpha`, `dumpsys telephony.registry`, APN settings.
- Not yet done: sepolicy for efsks.pid, IMSA (`qmi_client_init failure(31) for IMSA`, VoLTE not needed), SIM test, data test.

## 2026-10-26 00:46 — MILESTONE: LTE mobile data works on LineageOS 16 (Skinny NZ, Spark network)
- Chain that finally worked: stock vendor LTE files + `rild` (see above) + (1) `android.hardware.telephony(.gsm)` feature XMLs in
  /vendor/etc/permissions (without them nothing connects), (2) static RRO `/vendor/overlay/N9MobileOverlay.apk` adding mobile
  entries to `networkAttributes`/`radioAttributes` (the Wi-Fi build's framework-res only had wifi/bluetooth/ethernet, so
  `Supported types: 1 7 9 17` and RILJ never requested the radio HAL), (3) Skinny APN `wapaccess.co.nz` (530/05) inserted into
  telephony.db (empty on this build), (4) preferred network mode 9 (LTE/GSM/WCDMA).
- Result: SIM `LOADED`, operator `Spark NZ`, RAT LTE (14), `mDataConnectionState=2`, `rmnet_usb0` got 10.197.202.x,
  with Wi-Fi off: ping 1.1.1.1 21-38 ms, DNS ok, active network MOBILE[LTE] apn wapaccess.co.nz.
- Files: tools/android/lte/{install-lte-lineage16.sh,install-lte-lineage16.sh.notes,rild.rc,vintf-manifest-radio.diff,
  overlay/,permissions/,apn-skinny.sql}. Not yet verified: survives a reboot untouched (all changes are on /vendor + /data),
  voice/SMS (tablet is data-only, config_voice_capable=false), IMS/VoLTE (not needed), the `efsks.pid` SELinux denial.
