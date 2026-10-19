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
   `UartPort = /dev/ttyTHS2`.
3. ~~Add the `bluetooth` node~~ — **done**, in
   `patches/flounder-bluetooth.patch`: `serial@70006200` enabled with a
   `bluetooth` child on `brcm,bcm43540-bt`, the compatible that maps to
   `bcm4354_device_data` in the driver's match table. No control pins are
   declared, because none are established.

The firmware filename is worth spelling out, because it is not the ROM's.
`btbcm` reads the chip subversion over HCI, looks it up in `bcm_subver_table`
— where `0x610c` is `"BCM4354"` — and requests `brcm/BCM4354.hcd`. The ROM
carries it as `bcm4354.hcd`, lower case, so installing it is a rename as well
as a copy.

Nothing here has run on hardware; the node has only been built and validated
against the bindings.

## Which controller is ttyTHS2

Worth writing down, because counting the UARTs is the obvious approach and it
gives the wrong answer. The downstream `board-flounder.c` AUXDATA table maps
them explicitly:

| Address | Device | Port |
|---|---|---|
| `0x70006000` | `serial-tegra.0` | `ttyTHS0` |
| `0x70006040` | `serial-tegra.1` | `ttyTHS1` |
| `0x70006200` | `serial-tegra.2` | **`ttyTHS2`** |
| `0x70006300` | `serial-tegra.3` | `ttyTHS3` |

Note the second entry is at `+0x40`, not `+0x100`, so the addresses are not
evenly spaced and numbering them off by hand goes wrong. **Bluetooth is
`serial@70006200`.** The port's device tree currently has that node
`status = "disabled"`.

## The control pins, which are the one thing still missing

Android drove this through an rfkill device — `init.flounder.rc` writes
`/sys/class/rfkill/rfkill0/state 0` under its `# bluetooth` heading — so a GPIO
is involved somewhere. It is not in `board-flounder.c`: that file includes
`rfkill-gpio.h` but never instantiates a device, and the shipped DTB has no
rfkill, bluetooth or `bcm_bt` node. So the registration is somewhere not yet
looked at.

That is recorded as the open item rather than as a blocker, because it may not
be one: a BCM4354's Bluetooth section on a design like this often runs from an
always-on rail, with the UART's flow-control pins used for host and device wake.
The way to find out is a node without the pins and see whether `btbcm` brings
the controller up.

None of this has been started, and none of it has run on hardware.

## What pmOS did (checked 2026-10-19)

**Nothing.** Their DTS leaves `serial@70006200` `status = "disabled"` and has no
`bluetooth` node; only the `uartc` pinmux group exists. Their kernel config does
enable `BT`, `BT_HCIUART` (H4, BCM) and `BT_BCM`, but with the UART disabled
there is nothing for it to bind. So pmOS is not a source here; the downstream
board file remains the only one.

## Control pins, from downstream (2026-10-19)

`board-flounder.c` registers a `bluedroid_pm` device with these GPIOs:

| Downstream resource | GPIO | Mainline property |
|---|---|---|
| `shutdown_gpio` (BT_REG_ON) | **PR1** | `shutdown-gpios` (1 = powered) |
| `gpio_ext_wake` (BT_WAKE) | **PEE1** | `device-wakeup-gpios` |
| `gpio_host_wake` (HOST_WAKE) | **PU6** | `host-wakeup-gpios` |

`tegra-asoc`/machine data is irrelevant here; this is the Android bluedroid
power driver. Mainline `hci_bcm.c` handles the same three properties, and
`bcm_gpio_set_shutdown()` treats `shutdown-gpios` as a power *enable* — which
matches BT_REG_ON.

## What is now in the tree (2026-10-19)

- `patches/flounder-bluetooth.patch` applied: `serial@70006200` enabled with a
  `brcm,bcm43540-bt` child (serdev; matches `bcm4354_device_data`).
- Child gained `shutdown-gpios` (PR1), `device-wakeup-gpios` (PEE1) and
  `host-wakeup-gpios` (PU6).
- Firmware: `~/Downloads/nexus9/vendor-firmware/bcm4354.hcd` (identified as
  `BCM4354 37.4MHz WLBGA HTC T1-0192`) is installed in the test ramdisk as
  `/lib/firmware/brcm/BCM4354.hcd`.
- Test image `n9bt-stripped.img` adds `bluetooth.ko`, `hci_uart.ko`,
  `btbcm.ko`, `ecdh_generic.ko`, `rfkill.ko` and the firmware.

Not yet tested: no boot has loaded the modules with this DT. The open question
is whether the UART advertises flow control (the pinmux has uart3 cts/rts) and
whether `hci_uart` binds the serdev child without `max-speed` set.
