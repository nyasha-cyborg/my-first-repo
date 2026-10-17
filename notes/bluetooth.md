# Bluetooth on flounder

Surveyed 2026-10-17. Wireless audio matters for this tablet's stated use — music
while doing cardio, where a cable is in the way — so it is worth knowing what
stands between here and a pair of earbuds.

**Short version: Bluetooth is blocked on firmware that is not in the kernel, not
in linux-firmware, and would have to come out of the Android ROM.**

## What the shipped artifacts show

All read from the 7.1.1 kernel and DTB, via REA and `dtc`.

- **No Bluetooth node exists.** The shipped DTB has no `bluetooth`, `hci` or
  `bcm43*` node at all. The four `nvidia,tegra114-hsuart` controllers are
  enabled and **nothing hangs off any of them**.
- **The kernel has no BCM firmware string.** Searching for `bcm4354` returns
  nothing, and a search for `hcd` returns only USB host-controller symbols
  (`ehci_hcd`, `xhci_hcd`) — no `.hcd` firmware path. Together that says the
  Bluetooth firmware was pushed from **userspace**, by Android's Bluetooth
  stack, the way `brcm_patchram_plus` does it. The kernel had no hand in it.
- **`broadcom,bcm20791` in the port's device tree is not Bluetooth.** Its driver
  strings are `bcm2079x_probe` / `bcm2079x_dev_write`, and BCM2079x is an **NFC**
  controller. Worth stating because the node sits near the audio parts and its
  name invites exactly that misreading.

## Firmware, which is the actual blocker

- **Wi-Fi's firmware is available.** `brcmfmac4354-sdio.bin` is in
  linux-firmware, matching the `brcm,bcm4354-fmac` node, so the Wi-Fi path is
  not firmware-blocked.
- **Bluetooth's is not.** linux-firmware here ships exactly two `.hcd` files,
  and neither is for this chip.

One of them looked like it might be: `BCM-0bb4-0306.hcd`, where `0bb4` is HTC's
USB vendor ID and the Nexus 9 is an HTC device. It is not, and the check is
worth recording because the VID made it tempting. Reading the blob itself:

```
$ zstd -dc /usr/lib/firmware/brcm/BCM-0bb4-0306.hcd.zst | strings | head -1
BCM20703A1 Generic USB 20Mhz fcbga_BU
```

It is **BCM20703A1**, the chip in the HTC **Vive** link box — a different HTC
product entirely, which is why the vendor ID matched.

So the firmware for this chip (a `BCM4354A2`-class `.hcd`, given the combo part)
would have to be pulled out of the Android ROM's system partition.

## What mainline already has

Better than expected, on the software side:

| Piece | State |
|---|---|
| `BT_HCIUART` with `BT_HCIUART_BCM` and `BT_HCIUART_H4` | **already enabled** in `configs/flounder_defconfig` |
| `btbcm` support for `shutdown-gpios` / `device-wakeup-gpios` | in tree |
| `CONFIG_BT` core | present |

So the driver side is largely there — mainline's `btbcm` will load a `.hcd` from
`/lib/firmware/brcm/` once it knows the chip, which is precisely what Android did
in userspace.

## What it needs, in order

1. **Extract the Bluetooth firmware from the ROM.** The OTAs in
   `~/Downloads/nexus9/roms/` carry a system partition; the firmware will be
   under `etc/firmware/` in it. Extracting an OTA needs `sdat2img`-style
   handling, so this is a task in itself rather than a file copy.
2. **Identify the UART and its control pins.** Which of the four
   `tegra114-hsuart` controllers carries Bluetooth, and the enable/wake GPIOs —
   the downstream `board-flounder.c` is the place to look, as it was for the
   audio pin numbers.
3. **Add the `bluetooth` node** under that UART, with `shutdown-gpios`,
   `device-wakeup-gpios` and, if the extracted firmware needs it,
   `firmware-name`.

None of this has been started, and none of it has run on hardware.
