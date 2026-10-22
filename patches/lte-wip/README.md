# LTE modem: HSIC host work in progress (not for upstream as is)

Seven kernel commits on `usb-bringup` (local tree), on top of `5d830bfca`:
1. `032f3c38c` HSIC `phy_type` in `phy-tegra-usb.c` (UHSIC block recipe from the vendor
   driver), NULL-safe HSIC pad supply in `xusb-tegra124.c`, flounder DT: HSIC pad lanes
   + `usb@7d008000` host + `phy3` hsic.
2. `95115d84d` debug dump of the UHSIC registers after power on (temporary).
3. `bb6478be9` module parameters for the HSIC pad tuning (`/sys/module/phy_tegra_xusb/
   parameters/hsic_*`), experiment.
4. `3219cf7e3` power both HSIC pad lanes + pad register dump, experiment.
5. `e846893ae` fix debug offsets.
6. `e7505a04e` `hsic_pd_trx` knob (vendor sets PD_TRX again after the pad delay).
7. `9282a7e23` vendor generic `_usb_phy_init` writes (0x498 |= 0x30, USBMODE.SDIS clear, DEVLC bit 28): no effect.

State and findings: `notes/lte.md`. Status: PHY powers up, the modem is detected as a
high-speed device on the HSIC port, enumeration fails with EPROTO (-71).
Squash 2-5 away before anything is sent upstream; (1) needs binding docs and the
vendor register names cleaned up.

Later commits: `set_suspend` no-op for HSIC (the chipidea Tegra glue called the PHY's
power_off/power_on on every LPM transition; fixing it did not cure -71) and an
alternative route: HSIC lanes handed to the **xHCI** controller (`usb@70090000`,
`nvidia,function = "xusb"`, firmware `nvidia/tegra124/xusb.bin` from linux-firmware,
uncompressed into the ramdisk). Image `n9xhciA`, kernel `g8b0d00cb9ee1`.

Patches 0010-0016 (later experiments, all still ending in -71): revert of the xHCI DT
route (0010), EHCI HSIC without the xusb pad PHY (0011), debugfs register dump / poke
(0012, 0014), re-applying the vendor port-power writes after the controller reset
(0013), chipidea Tegra HSIC port-power hook (0015), PLL_U 480 MHz gate (0016).
A vendor force-enable-HS (PORTSC PTC=5) experiment was committed and reverted again
(no effect). Key result in `notes/lte.md` (2026-10-22 21:55): with the modem **off** the
EHCI port shows the same phantom connect and the same -71, so the connect is produced by
the controller's own pad pulls, not by the modem.
