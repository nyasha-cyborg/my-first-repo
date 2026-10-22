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
