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

## Mainline attempts, all silent (2026-10-20)

Test images, all with the vendor `BCM4354.hcd` and `bluetooth`/`btbcm`/
`hci_uart`/`ecdh_generic`/`ecc` modules:

| Image | DT / config | Result |
|---|---|---|
| `n9bt` | GPIOs only | `command 0x0c03 tx timeout` |
| `n9bt2` | + `ecc.ko` (busybox modprobe needs manual order) | same |
| `n9bt3` | + LPO `clk32k_in`, host-wakeup interrupt | `command 0x1001 tx timeout` |
| `n9bt4` | + `uart-has-rtscts` | unchanged |

What is verified on hardware in every case:

- `hci_uart_bcm` binds the right controller: `serial0-0` resolves to
  `/serial@70006200/bluetooth`, i.e. uartc, matching `bt_vendor.conf`'s
  `ttyTHS2`.
- GPIOs are driven: gpio-137 `shutdown` out hi, gpio-241 `device-wakeup` out
  hi, gpio-166 `host-wakeup` in hi.
- uart3 pads are muxed to `uartc` (CTS/RXD input with pull-up, RTS/TXD output).
- The module is powered: with `brcmfmac` loaded the WiFi side enumerates and
  loads its firmware, so the shared BCM4354 die has power.
- The 8250_of driver deasserts the UART CAR reset and enables the clock.

Ruled out as the sole cause: REG_ON polarity (downstream rfkill sets the GPIO
to 1 for "enabled", same as `hci_bcm`), LPO clock presence in DT, flow control
on/off, and a short power-up delay (driver already waits 100–120 ms).

Known mainline fixes for this exact signature already present in this tree:
`btbcm`'s 100 ms module-reset delay and the `hci_h4` registered-bit check.
Next discriminators: whether Android itself can bring the chip up (hardware
vs mainline), then the PMIC 32 kHz clock output (`palmas-clk32kg`) instead of
the fixed-clock placeholder.

Note: two of the boots hit the intermittent early stall (watchdog reset) —
unrelated to BT, but it costs a cycle each time.

## Android's own logs, and the real numbers (2026-10-20)

Android's Bluetooth stack works on this tablet (`state: ON`, MAC
`D4:0B:1A:16:DC:F3`). Its logcat names everything the mainline path was
missing:

```
bt_userial_vendor: userial vendor open: opening /dev/ttyTHS2
bt_hwcfg: bt vendor lib: set UART baud 3000000
bt_hwcfg: Chipset BCM4350C0
bt_hwcfg: Found patchfile: /vendor/firmware//bcm4350c0.hcd
bt_hwcfg: bt vendor lib: set UART baud 115200
bt_hwcfg: Settlement delay -- 100 ms
bt_hwcfg: bt vendor lib: set UART baud 3000000
```

So: the module is a **BCM4350C0**, its ROM answers at **3 Mbaud** (not 115200),
and the firmware is **bcm4350c0.hcd** (the vendor dir has it; `bcm4354.hcd` is
the HTC board-named variant). Android also deliberately power-cycles REG_ON
("BT_VND_PWR_ON now forces power-off first").

Mainline fixes attempted and their state:

- DT: uartc switched to `nvidia,tegra124-hsuart`/`tegra30-hsuart` with
  `serialN` aliases (without aliases serial-tegra fails with `alias id -19`);
  `nvidia,adjust-baud-rates` added, which makes `uartc` clock land on exactly
  48 MHz (16 x 3 M) for 3 Mbaud.
- `hci_bcm`: tty path now takes init speed from the tty; the BCM proto
  `init_speed` set to 3000000 for this port.
- Chip power/wake provided as an always-on fixed regulator (PR1) and a
  gpio-hog (PEE1) because the tty path has no serdev device to drive them.
- Firmware staged as `/lib/firmware/brcm/BCM.hcd` (btbcm's fallback name; its
  UART subversion table has no BCM4350C0 entry).

Tooling: `hciattach-min` (freestanding, in the test ramdisk) opens the tty,
sets the speed, puts it in `N_HCI` and selects HCI_UART_BCM. Note
`HCIUARTSETPROTO` takes the value, not a pointer.

**Status:** HCI `0x0c03`/`0x1001` still time out at 115200 and at 3 Mbaud, with
and without CRTSCTS, on cold and warm (Android-powered) chips. Host side is
verified: right UART (serdev of_node = `/serial@70006200`), IRQ 56 firing,
48 MHz clock, correct pads. Next probes: pulse REG_ON from userspace via the
GPIO chardev (Android's "power-off first"), and check whether the chip answers
only after that explicit off->on cycle.

## BT_WAKE hypothesis (2026-10-20, n9bt28)

Android's bluedroid_pm raises BT_WAKE (PEE1) per transmit
(`gpio_direction_output(ext_wake, 1)`) and drops it when host_wake is low,
so the chip sees an idle->wake edge before HCI. A fixed regulator holding
PEE1 high from boot never produces that edge.

- DT: removed the always-on `bt_wake` regulator so userspace can own PEE1.
- New `btwake` tool: PEE1 low 250 ms -> high, 120 ms settlement, UART at
  Android's B3000000|cs8|cread|clocal|crtscts, HCI Reset, one retry with a
  fresh edge. Holds the line high afterwards.
- Ramdisk init runs it before the raw baud sweep; image `n9bt28`.

Result so far: inconclusive. The intermittent early stall hit four boots in
a row (no `n9bt: start` written, no adb, no fastboot - init never ran), and
the control image `n9bt27` stalled the same way, so the image is not the
cause. Needs a clean boot to test.

## 2026-10-20 later: image-wrapper bug, chip lookup, stall instrumentation

- **Bogus "stalls" explained:** repacked images retained the 256-byte HTC
  wrapper. `fastboot boot` reports OKAY, hboot then ignores the image and
  stays in fastboot. Strip with `tail -c +257` (or use a stripped stock);
  the `-stripped.img` name means exactly that. Several "failed boots" earlier
  today were this, not the hardware.
- **testA** (old DTB, new ramdisk) booted and wrote a fresh record. Its
  `btwake` failed with `line request errno 22`: global line 241 is not an
  offset on `/dev/gpiochip0`. The PMIC GPIO controller probes first. btwake
  now resolves chip path and offset from `/sys/class/gpio/gpiochipN/{base,
  ngpio}`.
- **The genuine stall is random, not the DTB:** a control boot with the old
  DTB stalled too. Two new-DTB boots and one old-DTB control boot all hung
  before writing any record.
- **Instrumentation added:** `tegra_wdt.early_start=1` arms the hardware
  watchdog in probe, so a pre-init hang now self-resets after 120 s instead
  of needing a power cycle; init also marks `devtmpfs`, `bt-check` and
  `bt-child` into the rolling record to locate how far userspace got.
- Image `n9bt30` = new DTB + early-watchdog Image + properly stripped
  modules for vermagic `g5bf55902df2e-dirty`.
