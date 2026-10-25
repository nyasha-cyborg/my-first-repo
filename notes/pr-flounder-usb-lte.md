# PR draft: flounder audio, Bluetooth, USB and LTE modem bring-up

Branch: `flounder-clean` in `~/code/linux-flounder`, based on `flounder`
(`de78dfefe` tip at export time). 13 patches, exported to
`patches/linux-flounder-pr/`.

Target: fork PR against `yuka/linux`, branch `flounder`.

---

**Title:** arm64: tegra132: flounder: audio, Bluetooth, USB and LTE modem bring-up

**Body:**

This series brings up the remaining peripherals on the NVIDIA Tegra132
"Nexus 9" (flounder) beyond the display path already on the branch: the
tfa989x speaker amplifiers and the rt5677 headphone codec, the Broadcom
Bluetooth chip on HSUART2, the USB2 host/gadget controller, the palmas
charger, and the Qualcomm LTE modem.

The modem is the interesting part. It is an HSIC device, and the one thing
that made everything after the PHY work was hosting it on the **USB2
controller** (`usb@7d004000`, `phy2`) rather than on the USB3 controller.
The vendor kernel does the same; nothing in the DT made it obvious, and the
USB3 route produced a phantom connect that failed enumeration with `-EPROTO`
even with the modem powered off. On the USB2 port the modem's boot ROM
enumerates (`05c6:9008`), Sahara loads the modem OS, and it re-enumerates as
`05c6:9048` where `qmi_wwan` binds and QMI works.

Changes:

- `clk: palmas`: honour a `ti,clock-boot-enable` property so the 32 kHz LPO
  runs for the Bluetooth chip before any consumer binds
- `mmc: sdhci-tegra`: start 1.8V-only hosts (`nvidia,only-1-8v`) at 1.8V;
  the SDIO card is otherwise frequently left unenumerated
- `power: supply: bq24190_charger`: look the VBUS regulator up in a child
  node, otherwise consumers defer forever
- `watchdog: tegra`: `early_start` module parameter to arm at probe time
- `phy: tegra`: allow the HSIC pad to run without a supply
- `usb: phy: tegra`: HSIC (UHSIC block) power sequence, including the PMC
  USB_AO pad isolation release and staying powered across LPM transitions
- `usb: chipidea: tegra`: Tegra124 UDC with PMIC-based VBUS, and the HSIC
  port-power hook on `SetPortFeature(POWER/RESET)`; clear SLOM in device mode
- `ASoC: tfa989x`: optional `nxp,right-channel` so the bottom speaker can
  take the right I2S channel (binding patch separate)
- `ASoC: tegra`: tolerate codecs without `set_sysclk`, and release I2S pads
  the bootloader left in GPIO mode — this is what fixes the silent speakers
- `Bluetooth: hci_bcm`: power the chip before serdev opens the UART
- `arm64: tegra132: flounder`: DT for all of the above
- `flounder_defconfig`: charger, gadget and LTE modem drivers

Tested on hardware (Nexus 9 LTE):

- speakers play with the correct stereo split (top = left, bottom = right);
  headphone codec card registers (not yet verified by ear)
- `hci0` comes up and an LE scan sees nearby devices
- LTE: modem boots from mainline, `qmi_wwan` binds, registers on the network,
  and IP works — ping and DNS through `wwan0` in raw-IP mode
- USB host and gadget controllers enumerate

Known limitations / open questions:

- the `nvidia,i2s-pad` GPIO release is a workaround: the cleaner fix is
  probably in `gpio-tegra`/`pinctrl-tegra` (clear `GPIO_CNF` when a pad is
  muxed to a non-GPIO function), and the property has no binding yet
- `early_start` is a bring-up aid; happy to drop it if you prefer
- suspend/resume is not exercised on any of these paths
- Android/postmarketOS userspace has not been booted on top of this series

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## Second PR candidate (GPU): gk20a GR reset

`patches/linux-flounder-gpu/0001-drm-nouveau-gr-gk20a-reset-PGRAPH-and-FECS-before-lo.patch`
(branch `gk20a-gr-reset` in `~/code/linux-flounder`, commit `f51da75e8`). Fixes the intermittent
"gr: init failed -11/-110" on first GPU use. Only 2/2 clean boots so far — run `tools/pmos/gr-cycle-test.sh`
for 8+ boots before sending. Also needs: the tegra Mesa wrapper fix (`patches/mesa/`, separate upstream).
