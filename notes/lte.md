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
