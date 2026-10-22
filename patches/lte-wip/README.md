# LTE modem: HSIC host work in progress (not for upstream as is)

Five kernel commits on `usb-bringup` (local tree), on top of `5d830bfca`:
1. `032f3c38c` HSIC `phy_type` in `phy-tegra-usb.c` (UHSIC block recipe from the vendor
   driver), NULL-safe HSIC pad supply in `xusb-tegra124.c`, flounder DT: HSIC pad lanes
   + `usb@7d008000` host + `phy3` hsic.
2. `95115d84d` debug dump of the UHSIC registers after power on (temporary).
3. `bb6478be9` module parameters for the HSIC pad tuning (`/sys/module/phy_tegra_xusb/
   parameters/hsic_*`), experiment.
4. `3219cf7e3` power both HSIC pad lanes + pad register dump, experiment.
5. `e846893ae` fix debug offsets.

State and findings: `notes/lte.md`. Status: PHY powers up, the modem is detected as a
high-speed device on the HSIC port, enumeration fails with EPROTO (-71).
Squash 2-5 away before anything is sent upstream; (1) needs binding docs and the
vendor register names cleaned up.
