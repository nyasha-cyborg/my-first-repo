# linux-flounder local series

`git format-patch origin/flounder..HEAD` of `~/code/linux-flounder` (branch
`usb-bringup`), exported 2026-10-22. Base: `origin/flounder`
(https://cyberchaos.dev/yuka/linux.git, Linux 6.19-based, Nexus 9 DT).
**Local only — never push this tree to that remote.**

Apply on a clean checkout of the base: `git am patches/linux-flounder-series/*.patch`

Build: `make O=../linux-flounder-out ARCH=arm64 LLVM=1 -j16 Image modules dtbs`
(config snapshot: `configs/flounder_defconfig`).

## What each group does

| Commits (subject keywords) | Area | State |
|---|---|---|
| panel / DSI / D-PHY / backlight / video stream | display | working, PR-ready (`notes/display-pr.md`) |
| chipidea host/device, VBUS comparators, Tegra124 pad | USB host + gadget | working |
| sdhci-tegra 1.8V-only hosts | WiFi SDIO | works |
| watchdog: allow arming at probe | stall recovery | working |
| rt5677 supply gates | audio codec | codec binds, card registers |
| Bluetooth ... (WIP) x3 | BT bring-up history | superseded by the next one |
| **Bluetooth: order WLAN power and power the chip before serdev** | BT | **works** (hci0 up, LE scan hears devices) |
| **do not invert the PMC interrupt polarity** | PMIC irq | fixes the Palmas irq storm; PMIC irq delivery still to verify |
| **ASoC: tegra: tolerate codecs without set_sysclk** | audio | speaker PCM plays; silent, parked |

Tested kernel release for the last three: `6.19.0-htc-flounder-g6988accc2d82`.
