# Bluetooth on flounder

Surveyed 2026-10-17. Wireless audio matters for this tablet's stated use — music
while doing cardio, where a cable is in the way — so it is worth knowing what
stands between here and a pair of earbuds.

**Short version: this survey concluded Bluetooth was blocked on firmware — and
the firmware then turned up in the ROM's vendor partition, so what is left is a
device tree node.** See [`vendor-partition.md`](vendor-partition.md) for how the
image was opened.

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

So the firmware is absent from linux-firmware. **It is in the ROM, though**, at
`/vendor/firmware/bcm4354.hcd` in the vendor partition, extracted and identified
in [`vendor-partition.md`](vendor-partition.md). It announces itself as
`BCM4354 37.4MHz WLBGA HTC T1-0192` — this chip, this board.

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

1. ~~Extract the firmware from the ROM~~ — **done.** `/vendor/firmware/bcm4354.hcd`
   is extracted. It still has to be named the way `btbcm` looks for it, or
   pointed at with a `firmware-name` property on the node.
2. ~~Identify the UART~~ — **done.** `/etc/bluetooth/bt_vendor.conf` states
   `UartPort = /dev/ttyTHS2`, which is `serial@70006300`. What is still missing
   is its control pins: the enable and wake GPIOs, for which the downstream
   `board-flounder.c` is the place to look, as it was for the audio pin numbers.
3. **Add the `bluetooth` node** under `serial@70006300`, with the wake and
   shutdown GPIOs and the firmware name.

None of this has been started, and none of it has run on hardware.
