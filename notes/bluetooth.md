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

So: the module is a **BCM4350C0**, ~~its ROM answers at 3 Mbaud~~ (wrong —
see "libbt-vendor's real opening" below: the first Reset is at 115200 and
unlogged), and the firmware is **bcm4350c0.hcd** (the vendor dir has it; `bcm4354.hcd` is
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

## GPIO chardev bugs, and the first bytes from the chip (2026-10-20 18:xx)

Three separate bugs kept `btwake` from ever driving BT_WAKE:

- `CONFIG_GPIO_SYSFS` is off, so `/sys/class/gpio` does not exist. The chip
  map now comes from `/sys/kernel/debug/gpio` (`gpiochipN: <count> GPIOs`,
  in probe order): chip0 is tegra-gpio (256), chip1 is the PMIC (8), so
  line 241 = chip0 offset 241.
- `struct gpiohandle_request` gained `char consumer_label[32]`; the ioctl is
  now `_IOWR(0xB4,0x03, 364 bytes)` = `0xC16CB403`, and `SET_LINE_VALUES`
  is `_IOWR(0xB4,0x09,...)` = `0xC040B409`. The old numbers/sizes return
  EINVAL.
- `GPIOHANDLE_REQUEST_OUTPUT` is bit 1 (=2); bit 0 is INPUT. With 1 the
  line was requested as an input and `SET_LINE_VALUES` returned EPERM.

First signal ever received from the chip, on the boot after the struct fix
(n9bt32/33, with the wake pulse still failing):

```
n9bt: 921600 raw: got 04 0e
n9bt: 1500k raw: got 00 80 00 00 80 00 00
n9bt: 3M raw: got 00 00
```

`04 0e` is the HCI event header (Command Complete) — almost certainly
mangled by a baud mismatch, but it is the first non-empty read. The properly
wired wake pulse (output flag fixed) is image `n9bt34`.

Environment note: the early-stall rate rose sharply in the evening
(~9 of 11 boots around 18:00-18:30), with battery at 44%. Charging on a wall
socket before the next run.

## 2026-10-20 evening: REA results, PR1 discovery, reader bug

**REA of `libbt-vendor.so`** (pulled from the device):
- Android powers BT by writing `/sys/class/rfkill/rfkillN/state`; it never
  touches a GPIO directly.
- Wake/sleep uses vendor UART ioctls `0x8003`, `0x8004`, `0x8005` issued on
  the tty, handled by the downstream serial driver. Userspace has no other
  wake path, so manually driving PEE1 is the correct mainline analogue.
- Firmware: `/vendor/firmware/<FwPatchFileName>`, and BT_VND_PWR_ON forces a
  power-off first (already seen in logcat).

**REA of `audio.primary.flounder.so`:** the HAL only flips ALSA mixer
switches (`SPK VMixer SPK Switch`, `Codec VMixer Codec Switch`); amp and
codec handling lives in vendor kernel drivers. `RT5506` in `/system/etc` is
a register table, not code.

**GPIO chardev corrections:** request struct is 364 bytes with
`consumer_label` (ioctl `0xC16CB403`); `SET_LINE_VALUES` is `0xC040B409`;
`GPIOHANDLE_REQUEST_OUTPUT` is 2. The BT_WAKE pulse now works.

**PR1 (BT_REG_ON) finding, still being tested:** every DTB where PR1 is not
driven high by a boot-time kernel consumer fails to reach init (no `n9st`
marks, reset by the early watchdog). That covers: PR1 unclaimed, and PR1
owned by `rfkill-gpio` as a module (probe only happens after init). The
always-on `regulator-fixed` DTB boots. Test in flight: `rfkill-gpio` built
into the kernel so it claims PR1 high at boot, then userspace writes the
rfkill state to reproduce Android's power-off-first.

**Diagnostic bug:** earlier "stall" verdicts from the fast reader were false
when `adb root` restarted adbd and `dd` returned empty: md5(empty) is stable,
so the records compared equal. The reader now requires ≥32 KiB and retries.

## 2026-10-20 late: the polarity and clock bugs (n9bt44..60)

Live Android state with Bluetooth powered (verified on the device):

```
gpio-137 (shutdown_gpio) out lo     <- low = powered
gpio-241 (bt_ext_wake)   out hi     <- idle = "BT sleeping"
gpio-166 (bt_host_wake)  in  lo
```

Consequences, all now fixed in our code/DT:

- **BT_REG_ON is active low.** The vendor DTB lists PR1 (0x89) and PEE1
  (0xf1) in `gpio-output-low`, and `bluedroid_pm` powers the section on by
  setting `shutdown_gpio` to **0**. Our always-on `regulator-fixed` drove it
  high, i.e. kept the chip shut down. The old "regulator" DTB was therefore
  never a working BT configuration; the stray `04 0e` reads were noise.
- ~~BT_WAKE is active low~~ — **unverified, see "REA: Android's running kernel" below**: in
  Android's bluedroid_pm, lpm "1" drives ext_wake raw high + stay_awake. Old claim:
  `TIO_ASSERT_BT_WAKE` sets `ext_wake = 0`;
  `ext_wake = 1` means "BT sleeping".
- **CRTSCTS is 0x80000000**, not 0x8000. Every earlier flow-control attempt
  silently set the wrong bit. Android's HAL ORs `CRTSCTS|CLOCAL` into
  c_cflag before `tcsetattr`.
- **32 kHz LPO**: the vendor PMIC node has `ti,clock-boot-enable` on
  `clk32k_kg`. Mainline's `clk-palmas` ignored the property, so the LPO was
  never enabled. The driver now honours it and the DT sets it.
- `rfkill-gpio` aborts its probe on a NULL `reset-gpios` (it drives reset
  before shutdown), so a shutdown-only node silently never claims the pin.
  Our node points both properties at PR1, active low.
- Programmed baud is 3,040,800 for a requested 3,000,000 (1.36% high, from
  the 48.65 MHz uart clock), same source Android uses.

Still no HCI reply from the chip in the latest runs; the focused probe in
`n9bt60` isolates LPO status plus one corrected btwake pass.

## Clean 90 s run (n9bt61 @ heartbeat=90)

With the watchdog given enough time the whole probe completes, so the earlier
"record ends at sending HCI Reset" was the 45 s watchdog truncating the run,
not a crash:

```
n9bt: clk32kg 1                      <- LPO enabled
btwake: power off (high)
btwake: power on (low)
btwake: wake asserted (low)
btwake: sending HCI Reset
btwake: no reply in 2s
btwake: retry ... no reply in 2s
btwake end
post3M raw: no reply in 6s
```

So: chip powered, awake, LPO on, 3.04 Mbaud, true CRTSCTS — still silent.
Next hypothesis from Android's log order: the HAL performs a baud dance
(3000000 -> 115200 with ~100 ms settlement -> 3000000) *before* the first HCI
command, which looks like a deliberate UART resync. That sequence has never
been reproduced. Test it next, then fall back to hciattach/btbcm with the
ROM assumed at 115200.

## libbt-vendor's real opening (REA, 2026-10-20 21:00)

The "baud dance" read off logcat was a misreading. Decompiled
`/vendor/lib64/libbt-vendor.so` (sha256 `5890605f…`):

- `op(BT_VND_OP_USERIAL_OPEN)` -> `userial_vendor_open(cfg 09 02 07 00)`:
  8N1, baud index 7 -> table `0x104d90[6]` = `0x1002` = **B115200**;
  `cfmakeraw`, `c_cflag |= 0x80000000` (CRTSCTS), then vendor ioctls
  `0x8003`, `0x8005` (downstream serial driver only).
- `hw_config_start`: **HCI Reset at 115200** (no log line), then
  `hw_config_cback`: VSC `fc18` (`06 00 00 c0 c6 2d 00`) -> *then* logs
  "set UART baud 3000000" -> Read Local Name (`0c14`, logs "Chipset") ->
  firmware (`fc2e` + records) -> 115200 + 100 ms settle (fw restarts at
  115200) -> Reset -> `fc18` -> 3M -> `fc01` bdaddr.
- So the 3M->115200->3M sequence is **post-firmware**, not a resync before
  first contact.

## n9bt63: Android's exact opening, still silent (build 63)

`btwake` now replays it: PR1 off/on, PEE1 asserted low, 115200+CRTSCTS,
Reset, retry with a fresh wake edge, `fc18`/3M/Local Name on success, 3M
Reset as fallback. Also fixed: `puthex`/`putdec` wrote single chars to
stderr->kmsg, so any reply bytes were split into 1-char records.

```
n9bt: clk32kg 1
n9bt: btwake: user line 241 -> /dev/gpiochip0 offset 241
n9bt: btwake: power off (high) / power on (low) / wake asserted (low)
n9bt: btwake: no reply to HCI Reset @115200     (x2, second with new edge)
n9bt: btwake: no reply to HCI Reset @3M
post3M raw: no reply in 6s
```

First n9bt63 boot hit the early stall (no record, 90 s watchdog return);
battery 22% on USB only.

**Dead:** "wrong initial baud" — both 115200 and 3M silent with CRTSCTS.

**Open question now:** do our bytes leave the UART at all? With CRTSCTS the
Tegra transmits only while CTS (= chip RTS) is asserted; a chip held in
reset never asserts it, and the command sits in the queue. Never measured.

## n9bt64: transmit diagnostics (build 64)

All legs silent, including **115200 no-flow**. `cts=1 rts=1 outq=0`
everywhere, but that is uninformative: mainline `serial-tegra`
`get_mctrl` always reports CTS (hardware handles it), and `outq` only shows
the tty buffer drained into DMA/FIFO.

## REG_ON is ACTIVE HIGH — the 2026-10-20 "polarity fix" was wrong

Live Android, toggled with `svc bluetooth enable/disable`, read from
`/d/gpio`, repeated on/off/on/off:

```
BT off: gpio-137 (shutdown_gpio) out lo   gpio-166 in lo   gpio-241 out hi
BT on:  gpio-137 (shutdown_gpio) out hi   gpio-166 in lo   gpio-241 out hi
rfkill: bluedroid_pm state 1
```

The earlier "`out lo` = powered" sample was taken with BT off. Every btwake
run from n9bt44 to n9bt64 therefore held the chip **off**. The old
always-on regulator (PR1 high) had the right polarity but ran with the
wrong CRTSCTS bit, LPO off and 3M-only probes.

## n9bt65: FIRST HCI REPLY (build 65)

btwake with PR1 low->high, PEE1 asserted low, 115200+CRTSCTS, LPO on:

```
n9bt: btwake: power off (low) / power on (high)
n9bt: btwake: send HCI Reset @115200
n9bt: btwake: got 04 0e 04 01 03 0c 00            <- Command Complete, ok
n9bt: btwake: send VSC fc18 -> 3000000
n9bt: btwake: got 04 0e 04 01 18 fc 00            <- ok
n9bt: btwake: send Read Local Name @3M
n9bt: btwake: got 04 0e fc 01 14 0c 00 42 43 4d 34 33 35 30 43 30 ...
n9bt: btwake: local name BCM4350C0
n9bt: held-gpio gpio-137 out hi ; gpio-241 out lo
```

Chip, UART TX/RX, pads, LPO and the 3M switch are all proven. Reply
latency ~50 ms per command.

**Confirmed:** REG_ON active high; BT_WAKE asserted low works; ROM speaks
115200 first; `fc18` + host 3,040,800 baud works.

**Dead:** "wrong initial baud" (the silence was REG_ON), "bytes never
leave the UART", "ROM answers at 3M".

## Next actions

1. Kernel DT: PR1 `shutdown-gpios` (and the rfkill node's `reset-gpios`)
   must be **GPIO_ACTIVE_HIGH**; BT_WAKE polarity unverified (see REA section below). Then let
   `hci_uart`/`hci_bcm` own the chip via serdev, `init_speed` 115200,
   `oper_speed` 3000000.
2. Firmware: `btbcm` has no BCM4350C0 subver entry; stage
   `bcm4350c0.hcd` as `brcm/BCM.hcd` (or add the subver) and confirm the
   download + post-patch 115200 Reset.
3. BlueZ: `bluetoothctl` scan, then pair earbuds (A2DP).
4. Early stall still ~50% at 21% battery on USB: charge from a wall socket
   before long runs.

## Kernel path: hci_bcm over serdev (n9bt66/67, 2026-10-20 21:30, PAUSED)

Kernel tree `~/code/linux-flounder` (uncommitted on top of `45145e3cf`):
- DT: `bluetooth` child of `serial@70006200`, `brcm,bcm43540-bt`,
  `max-speed = <3000000>`, `shutdown-gpios` PR1 **ACTIVE_HIGH**,
  `device-wakeup-gpios` PEE1 ACTIVE_LOW, `clocks = <&palmas_clk32kg>`
  ("lpo"); HOST_WAKE omitted; `bluetooth-rfkill` node removed.
- `hci_bcm.c` restored to upstream (proto `init_speed` 115200), plus a
  temporary `n9dbg bcm rx/tx` raw trace in `bcm_recv`/`bcm_enqueue`.
- Ramdisk: `/etc/bt-hci` makes init insmod bluetooth/btbcm/hci_uart
  instead of running btwake. `brcm/BCM.hcd` == vendor `bcm4350c0.hcd`.

n9bt66 (third attempt; two early stalls first):

```
hci_uart_bcm serial0-0: supply vbat/vddio not found, using dummy regulator
Bluetooth: hci0: command 0x1001 tx timeout
Bluetooth: hci0: BCM: Reading local version info failed (-110)
n9bt: bt-gpio gpio-137 (shutdown) out hi ; gpio-241 (device-wakeup) out lo ACTIVE LOW
```

HCI Reset succeeded (btbcm_reset is silent on success); the next command,
Read Local Version at 115200, got no reply. Android never sends 0x1001
before fc18 — it goes Reset -> fc18 -> 3M -> Read Local Name.
`bcm43540-bt` data sets `no_early_set_baudrate`, so hci_bcm stays at 115200.

n9bt67 = n9bt66 + rx/tx trace, to tell "chip ignores 0x1001" from "host
loses the 15-byte reply". One attempt was in flight when paused for
charging; its record (if init ran) is still on the DTB partition.

Next:
1. Read the n9bt67 record (`start build 67`, `n9dbg bcm`), or re-boot it.
2. If the chip ignores 0x1001 at ROM stage: try a compatible without
   `no_early_set_baudrate` (fc18 before setup, like Android), or move
   btbcm's Read Local Version after the baud switch.
3. Early stall is ~50% at <20% battery; charge on a wall socket first.

### n9bt67/68 raw trace: under hci_uart the chip answers only HCI Reset

n9bt67 (`bcm43540-bt`, no early baud):
```
3.048 n9dbg bcm tx 4: 01 03 0c 00            Reset
3.152 n9dbg bcm rx 7: 04 0e 04 01 03 0c 00   ok
3.253 n9dbg bcm tx 4: 01 01 10 00            Read Local Version -> nothing, 5.41 timeout
```
n9bt68 (`bcm4335a0` experiment, fc18 before setup):
```
2.912 tx 10: 01 18 fc 06 00 00 c0 c6 2d 00   fc18 -> nothing, 4.98 timeout
4.985 tx 4:  01 03 0c 00                     Reset
4.987 rx 7:  04 0e 04 01 03 0c 00            ok (1.6 ms)
5.088 tx 4:  01 01 10 00                     Read Local Version -> nothing
```
Zero RX bytes for every non-Reset command, so this is not reassembly loss.
**Dead:** "wrong command order" (fc18 first fails too). The same chip
answered Reset, fc18 and Local Name to btwake over the tty on the old
kernel (n9bt65).

n9bt69 discriminates kernel/DT vs serdev path: new kernel, bluetooth node
`status = "disabled"` via `fdtput` on a DTB copy (ttyTHS2 returns), and
btwake extended to Reset -> 0x1001 @115200 -> fc18 -> 3M -> Local Name ->
0x1001 @3M. Init now reboots ~8 s after `n9bt: done` unless `/etc/bt-stay`.

### n9bt69: new kernel, tty path, btwake — every command answered

BT node disabled with `fdtput` (ttyTHS2 returns). Reset, **0x1001 @115200**
(`... 06 00 10 06 0f 00 0c 61`: manufacturer 0x000f, **LMP subver 0x610c
= "BCM4354"** in btbcm's table, so it requests `brcm/BCM4354.hcd`), fc18,
Local Name "BCM4350C0", 0x1001 @3M. **Dead:** "new kernel/DT broke the UART".

### n9bt70: hci_uart over N_HCI (tty) — FIRMWARE DOWNLOADED

btwake `hold` powers/wakes, `hciattach-min` (fixed: TCSETS2 at 115200 had
CBAUD 0 = B0/hang-up) attaches N_HCI + BCM. `BCM4354.hcd` = vendor
`bcm4350c0.hcd` (HTC board file kept as `BCM4354-htc-board.hcd`).

```
3.76 tx fc18(115200) -> ok;  Reset -> ok;  0x1001 -> ok (subver 610c)
3.93 BCM: chip id 92 / features 0x2f / BCM4350C0
3.96 BCM4354 (003.001.012) build 0000 / BCM4354 'brcm/BCM4354.hcd' Patch
     ~1000 fc4c records, all acked
13.50 tx fc4e (launch RAM) -> ok
13.76 tx fc18 -> timeout          (250 ms after launch)
15.87 tx Reset -> rx only at 17.74 (chip still booting new firmware)
17.85 tx 0x1001 -> timeout         (100 ms after that reply)
```

**Confirmed (timing):** the chip ignores commands for a while after it
boots — from power-on (serdev: 100-120 ms settle) and after Launch RAM
(250 ms). A late Reset reply = "just finished booting"; the next command
100 ms later is dropped. That explains n9bt66/67/68 too. **Dead:** "serdev
vs tty" as the cause.

Freshness check trap: a trace flood pushes `start build N` out of the
rolling record; compare record md5 + kernel build instead.

n9bt71: serdev path again (`bcm43540-bt`), test delays `msleep(500)` after
power-on (hci_bcm) and `msleep(1000)` after every Reset (btbcm), init
syncs before the early reboot.

### n9bt71: longer delays alone do not fix serdev

500 ms power-on settle + 1 s after Reset: `tx Reset -> rx ok (1.7 ms)`,
`tx 0x1001` one second later -> nothing. The tty path answered 0x1001
100 ms after Reset (n9bt70), so plain post-Reset timing is **dead**.

### REA: Android's running kernel (bluedroid_pm), 2026-10-20 23:50

Artifact: running LNX (`mmcblk0p16`), `Linux 3.10.103-g5cef0dc1890 #13
Dec 20 2024` (custom 2024 build, not the 2017 stock). Image wrapped as ELF
windows with `/proc/kallsyms` (`/tmp/n9tools/image2elf.py`).

- struct fields: `[0] reset_gpio` (absent on flounder), `[1] shutdown_gpio`,
  `[2] gpio_host_wake`, `[3] gpio_ext_wake`; probe sets ext_wake **output
  high**; supplies `avdd`/`dvdd` optional.
- `bluedroid_pm_rfkill_set_power(unblock)`: 100 x udelay(1000), regulators
  on, `shutdown=1` (reset=1), 100 ms. **BT_WAKE is not touched at
  power-on** — the chip boots with it raw high.
- `/proc/bluetooth/sleep/lpm` write: `"1"` -> ext_wake raw **1** +
  `__pm_stay_awake`; `"0"` -> ext_wake raw 0 only once host_wake is low,
  else re-arm a 1.5 s timer; `__pm_relax`. So in Android's own driver raw
  high means awake. The "BT_WAKE active low" note above came from a
  misread and is **unverified**; what is certain is that the chip boots
  with BT_WAKE high in both working cases (Android, btwake).
- Failing case is unique: hci_bcm drives BT_WAKE low in the same instant
  as REG_ON.

n9bt72: hci_bcm power-on reordered to btwake's proven sequence (wake
deasserted -> REG_ON high -> 500 ms -> wake asserted -> 50 ms -> 100 ms),
btbcm 1 s post-Reset kept. Kernel rebuilt (release
`g6499bae9e9de-dirty`) with all modules restaged.

### n9bt72: btwake's wake order under hci_bcm — still only Reset answered

hci_bcm power-on reordered (wake deasserted -> REG_ON -> 500 ms -> wake
asserted -> 50 ms -> 100 ms): `tx Reset -> rx ok (1.7 ms)`, `tx 0x1001`
1 s later -> nothing. **Dead:** "BT_WAKE asserted together with REG_ON".

So with identical hci_bcm/btbcm code and identical chip power sequence,
tty/N_HCI (n9bt70) gets every reply and serdev gets only the first.
Code read: hci_serdev receive/write paths look equivalent; runtime PM
(`bcm_suspend_device`, which drops RTS) is only enabled with a host-wake
IRQ, which we do not declare — **dead** from the code.

n9bt73 traces the two remaining layers: `n9dbg serdev write len/total
tiocm` in hci_serdev's write work (did the bytes reach the UART, or is TX
stuck behind CTS?) and `n9dbg ttyport rx count active` in
serdev-ttyport (do reply bytes reach serdev and get dropped?).

### n9bt73: the second command never leaves the host

```
tx Reset           -> n9dbg serdev write 4/4 tiocm=0x26 -> ttyport rx 7 -> bcm rx ok
tx 0x1001 (+1 s)   -> n9dbg serdev write 4/4 tiocm=0x26 -> (no ttyport rx at all)
```

`write 4/4` = accepted into the serial core's xmit buffer, not "on the
wire". Code check: soft CTS (`hw_stopped`) cannot latch — modem-status
interrupts need `nvidia,enable-modem-interrupt` (absent) and
`tegra_uart_get_mctrl` always reports CTS. Remaining gate: **hardware
CTS** (`MCR CTS_EN` with CRTSCTS) holding the FIFO while the chip's RTS is
deasserted, i.e. the chip stops accepting after replying to Reset.
serdev's `ttyport_open` forces CRTSCTS *before* hci_bcm powers the chip;
the working paths enable it after the chip is up.

Also: this record's last snapshot is at 4 s (`uptime_at_write=4s`) even
though the run completed and rebooted at ~23 s — snapshots after that were
not persisted. Open.

n9bt74: `bcm_open` turns host flow control off (RTS kept asserted) right
after power-on under serdev.

### n9bt74: host flow control off -> even Reset unanswered

`bcm_open` set flow off + RTS on: `tx Reset -> write 4/4 -> nothing ->
0x0c03 tx timeout`. With CRTSCTS off the Tegra RTS output is apparently not
asserted (despite tiocm 0x26), so the chip never sends; with CRTSCTS on,
auto-RTS lets exactly one reply through. **Dead** as a fix; reverted.

Remaining ordering difference vs both working paths: serdev opens the
UART (`serdev_device_open`, hci_serdev.c:320) *before* `p->open` powers
the chip (:324), so the port watches the unpowered chip's TX held low
(break/framing errors) through boot. btwake/hciattach power first.

n9bt75: hci_bcm probe powers the chip (`bcm_gpio_set_power(true)`) right
after its power-off, i.e. before hci_uart opens the port; bcm_open's
second power-on only re-edges BT_WAKE.

### n9bt75: ROOT CAUSE — serdev opened the port before the chip had power

hci_bcm probe now powers the chip *before* hci_uart's `serdev_device_open`.
Under the real serdev driver:

```
Reset ok -> 0x1001 ok (subver 610c) -> fc79 chip id 92 -> fc6e features 0x2f
-> 0c14 "BCM4350C0" -> BCM4354 'brcm/BCM4354.hcd' Patch -> fc2e ok
-> fc4c patch records, every one acked (208-byte writes, 7-byte replies)
```

**Confirmed:** opening the UART while the chip is unpowered (its TX held
low through boot) is what limited serdev to a single reply. The record
filled at 14.2 s (~2000 trace lines) mid-download, so the post-Launch-RAM
stage is not visible yet.

n9bt76: same fix, trace quiet during fc4c records, serdev/ttyport traces
removed. Kernel commit `80e28b1bf` local (see `git -C ~/code/linux-flounder log`).

### n9bt76: firmware loads under serdev; same failure after Launch RAM

```
5.20  BCM4354 'brcm/BCM4354.hcd' Patch, fc2e ok
13.00 489 patch records sent, fc4e (Launch RAM) ok
13.25 fc18 -> 3M (250 ms after launch)          -> no reply, timeout
15.44 Reset                                     -> reply only at 17.24
18.26 0x1001 (1 s after)                        -> no reply, timeout
```

Launch RAM reboots the chip *while the port is open* — the same condition
the probe-power fix removed at power-on, with the same "one reply gets
through" result. Android downloads at 3M and after launch sets the host
back to 115200: a real speed change, so the Tegra UART is reprogrammed
after the chip reboots. With `bcm43540-bt` (`no_early_set_baudrate`)
mainline stays at 115200 throughout, and the serial core skips
set_termios when nothing changes — no reprogram.

n9bt77 (DT only): compatible `brcm,bcm4335a0` (no device data) so
hci_uart sets 3M before setup and btbcm returns to 115200 after launch —
Android's order. (n9bt68's early-baud test predates the probe-power fix.)

### n9bt77: early baud works — 3M download in 0.45 s; post-launch still stuck

```
4.18 fc18 -> 3M ok; Reset, 0x1001, fc79, fc6e, 0c14 all ok at 3,040,800 baud
5.74 489 patch records in 0.45 s (7.8 s at 115200), fc4e ok
6.00 host back to 115200 (real change -> UART reprogrammed, 258 ms after launch)
6.00 fc18 -> no reply;  8.19 Reset -> reply at 9.99;  10.99 0x1001 -> no reply
```

The reprogram happened but did not help. Order differs from Android after
launch — Android: host 115200, 100 ms, **Reset**, then fc18. Mainline:
host 115200, **fc18 first** (unanswered), Reset only in btbcm_finalize.

n9bt78: bcm_setup inserts 100 ms + HCI Reset after the host returns to
115200, before fc18. Full rebuild, release `g80e28b1bf7c7-dirty`.

### 00:41: tablet off USB during n9bt78 — needs a manual power cycle

n9bt78's mainline gadget enumerated (00:37:46), then the tablet vanished
from USB (no gadget, fastboot or adb) and did not come back within ~4 min;
the early watchdog did not recover it. Same signature as the 23:00 hang on
n9bt67, so not obviously caused by the n9bt78 change. No record read yet:
after the power cycle, pull the record first (`tools/record-id.py`) — if it
says build 78, the run got far enough to log.

Resume: power cycle (hold power ~15 s) -> Android -> read record ->
otherwise `tools/bt-bootloop.sh 78`.

### 2026-10-21 08:00: n9bt78 — inconclusive, tablet hangs on this image

- First `bt-bootloop.sh 78` run reported "fresh" but the record hash
  (`45dfc13ac2d995b0`) equalled the pre-run record: it came from the earlier
  interrupted attempt. Script fixed: fresh now requires a hash different from
  the pre-attempt record even when the build number matches.
- That (possibly stale) build-78 record: power-on, 3M early baud, Reset,
  0x1001, fc79, fc6e, 0c14, firmware download start all fine; no fc4e (Launch
  RAM) line and no `n9dbg post-launch Reset` line; ends `n9bt: rebooting` at
  87 s. Tablet came back `bootreason=watchdog`.
- Re-run with the fixed script: tablet fell off USB (no adb/fastboot/gadget)
  and needs a manual power cycle. Second hang on n9bt78, so the hang may be
  tied to this image (the post-launch path) rather than being the unrelated
  early stall.

Next: power cycle -> pull record -> `record-id.py`; if build 78 with a new
hash, look for the `post-launch Reset` line.

### n9bt78 clean result (08:20, fresh record confirmed): chip answers ~4 s after Launch RAM

```
13.33 Launch RAM (fc4e ff ff ff ff) -> ok          (489 records in 0.74 s at 3M)
13.60 host back to 115200
13.71 post-launch Reset                           -> tx timeout at 15.87 (-110)
15.87 fc18 -> 3M                                  -> no reply
17.57 rx 04 0e 04 01 03 0c 00  (the Reset reply, 3.9 s after it was sent)
19.71 Reset again at 3M -> timeout; "BCM: Reset failed (-110)"
```

Pattern across runs: first reply after Launch RAM arrives 4.2 s (n9bt76:
13.0 -> 17.24), 4.0 s (n9bt77: 6.0 -> 9.99) and 4.2 s (n9bt78) later. So the
chip's firmware needs ~4 s to boot after Launch RAM; commands sent earlier
are lost (the 2 s HCI timeout is shorter than that), and a Reset sent early
is answered late. The "post-launch order" hypothesis (fc18 before Reset) is
**dead**; the delay is the variable. Earlier "hang" boots (00:38, 08:02)
left no record; those hangs are a separate, still-open problem.

n9bt79 (planned): replace the 100 ms before the post-launch Reset with a
~5 s sleep; expect Reset ok, fc18 ok, hci0 up. If the sleep works, tune it
down (Android's hciattach waits less, check btld/REA for the real figure).

### n9bt79–81 (08:10–08:35): settle delay found; wake polarity and spacing dead

All runs: 3M early baud, firmware 489 records in 0.4–0.7 s, Launch RAM ok.

| build | change | result after Launch RAM |
|---|---|---|
| 79 | 5 s sleep before post-launch Reset | **Reset ok, answered in 2 ms**; then fc18 lost (2 s timeout), Reset ok, 0x1001 lost |
| 80 | + BT_WAKE raw high (DT ACTIVE_HIGH, asserted before REG_ON); pin read `out hi` | identical to 79 |
| 81 | + 2 s sleep between Reset and fc18 | identical: Reset ok, fc18 lost, Reset ok, 0x1001 lost |

Conclusions:
- Chip firmware needs ~4–5 s after Launch RAM (Reset at 100 ms/2 s fails;
  libbt's own "settlement delay" for this chip is only 100 ms, so Android
  must differ elsewhere — e.g. the downstream UART ioctls 0x8003/0x8005).
- **Dead:** BT_WAKE polarity as the cause (79 vs 80 same). **Dead:** "command
  right after a reply is lost" (81 spaced fc18 by 2.1 s and still lost).
- Live pattern: post-launch only **Reset** is answered; fc18 (vendor) and
  0x1001 (Read Local Version) are not, though both worked before Launch RAM.
- Android's libbt-vendor (REA 08:25): `hw_lpm_enable` sends `fc27` with
  `01 01 01 01 01 01 01 00 00 00 00 00` (sleep mode 1, BT_WAKE active high),
  default settlement 100 ms. Never tried here: **fc27 as the first command
  after the post-launch Reset**.
- Tooling: stripped images are now assembled with
  `tools/bootimg-swap-ramdisk.py <in> <rd.gz> <out> [kernel-region]`;
  kernel release pinned by patching vermagic of the rebuilt hci_uart.ko
  (same-length hash swap) so init/module paths stay valid.
- The tablet stalls without writing a record in roughly 1 of 3 boots
  (watchdog at 90 s); the loop just retries.
