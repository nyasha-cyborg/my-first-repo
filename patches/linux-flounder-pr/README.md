# flounder: audio, Bluetooth, USB and LTE modem series

`git format-patch origin/flounder..flounder-clean` of `~/code/linux-flounder`,
exported 2026-10-23. Base: `origin/flounder`
(https://cyberchaos.dev/yuka/linux.git, Linux 6.19-based, Nexus 9 DT, display
bring-up already applied). 13 patches.

Supersedes `../linux-flounder-series/` (which stopped at the audio patches)
and `../lte-wip/` (the HSIC experiment history).

Apply on a clean checkout of the base:

    git am patches/linux-flounder-pr/*.patch

Build:

    make O=../linux-flounder-out ARCH=arm64 LLVM=1 -j16 Image modules dtbs

Checked before export: every touched object and `tegra132-flounder.dtb` builds,
checkpatch is clean per patch apart from the intentional `-ENOTSUPP` check
(see the ASoC: tegra commit message).

## What each patch does

| Patch | Area | State on hardware |
|---|---|---|
| clk: palmas | 32 kHz LPO for the BT chip | works |
| mmc: sdhci-tegra | 1.8V-only SDIO hosts | works (WiFi card enumerates) |
| bq24190_charger | VBUS regulator child node | works |
| watchdog: tegra | `early_start` module param | works (bring-up aid) |
| phy: tegra (HSIC pad) | optional pad supply | works |
| usb: phy: tegra | HSIC PHY power sequence | **works** (modem enumerates) |
| usb: chipidea: tegra | Tegra124 UDC + HSIC port power | works |
| ASoC: tfa989x (binding + code) | `nxp,right-channel` | works (stereo split heard) |
| ASoC: tegra | no-set_sysclk codecs, release I2S pads | **fixes the silent speakers** |
| Bluetooth: hci_bcm | power the chip before serdev | works (hci0 up, LE scan) |
| arm64: tegra132: flounder | DT for all of the above | — |
| flounder_defconfig | charger, gadget, qmi_wwan/cdc-wdm/qcserial | works |

## The LTE modem result

The modem is an HSIC device and must be hosted on the **USB2 controller**
(`usb@7d004000`, `phy2`), not on the USB3 controller. With the host there, the
modem's boot ROM enumerates, Sahara loads the OS, and `qmi_wwan` binds
(05c6:9048). Full sequence and evidence: `notes/lte.md`.
