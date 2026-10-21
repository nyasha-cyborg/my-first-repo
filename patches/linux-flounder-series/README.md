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
| **flounder: un-tristate DAP3 outputs, match Android drive_dap3** | audio | needed (pads must drive) |
| **ASoC: tegra: release I2S pads left in GPIO mode by the bootloader** | audio | **fixes the silent speakers**: amps lock (R0 `0xd05f`) |
| **flounder: release the DAP2 pads for the codec card too** | audio | same fix for the rt5677/headphone card, untested by ear |

Tested kernel release for the audio patches: `6.19.0-htc-flounder-g96949bf28c4c`.

## Before sending anything upstream (checkpatch 2026-10-22)

- `Bluetooth: flounder - order WLAN power...`: wrap the commit message at 75
  columns; put block-comment `*/` on its own line (two places).
- `ASoC: tegra: tolerate codecs without set_sysclk...`: same two nits;
  `-ENOTSUPP` is what `snd_soc_dai_set_sysclk()` itself returns for a missing
  op, so keep it (checkpatch prefers EOPNOTSUPP; explain in the commit text).
- All commits carry `Co-Authored-By:`; upstream wants `Co-developed-by:` +
  `Signed-off-by:` pairs, or drop the trailer.
- The `PMC invert-interrupt` change is DT-only but its justification (Android
  has no such property; bootloader leaves INTR_POLARITY 0) should be re-checked
  once PMIC interrupt delivery is confirmed (see `notes/stability-debug.md`).
- `ASoC: tegra: release I2S pads...` adds a new DT property
  (`nvidia,i2s-pad-gpios`) with no binding yet. A cleaner upstream fix is
  probably in `gpio-tegra`/`pinctrl-tegra` (clear GPIO_CNF when a pad is
  muxed to a non-GPIO function); decide before sending.
