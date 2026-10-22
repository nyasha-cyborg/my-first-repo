# Handoff — Nexus 9 (flounder) mainline port

Written 2026-10-19 05:15 NZDT, for the next session.

## Repos and branches

| Repo | Branch | Tip |
|---|---|---|
| `~/code/linux-flounder` | `usb-bringup` | `65429d8f7` |
| `~/code/nexus9` | `nexus9` | see `git log -1` (`notes:` handoff commit) |

**Nothing is pushed and nothing should be.** An accidental push to the public
repo earlier was undone; `origin/nexus9` is back at `5d0d8a3`.

Build:
`make -C ~/code/linux-flounder O=~/code/linux-flounder-out ARCH=arm64 LLVM=1 -j16 Image modules`
Config in `linux-flounder-out/.config`, snapshot in `configs/flounder_defconfig`.

## Tablet state at handoff

Stalled in "mode B" (see below) since 00:35. `lsusb` still enumerates
`0525:a4a7 Gadget Serial v2.4` but the gadget is silent and the shell does not
answer. **It needs one power cycle when the operator is back.**

## Proven on hardware

- **Display** — done earlier, PR-ready.
- **USB host** — done earlier.
- **USB device mode / g_serial** — works; host sees `0525:a4a7`, `cdc_acm`
  creates `ttyACM0`. Root cause and fix in `usb-debug.md`.
- **Serial console** — reliable workbench (with the line-settings trap).
- **WiFi (BCM4354, SDIO)** — WPA2 association, DHCP, DNS, ICMP, HTTP; the
  whole sequence now runs automatically at boot and reaches the internet.
- **Touch** — `Synaptics S7504` (RMI4/SPI) registered as `event0`,
  `gpio-keys` as `event1`; evdev loaded from the ramdisk. No finger has been
  on the panel yet, so events are unproven.
- **Watchdog** — `tegra-wdt`, 120 s, opened first thing by init. Verified:
  a full-machine stall reset the tablet by itself
  (`ro.boot.bootreason=watchdog`).

## Not working: the stability problem

Two stall modes have been seen:

| Mode | Symptom | Watchdog |
|---|---|---|
| A | whole machine dies, USB disappears | **fires** (verified) |
| B | USB stays enumerated, gadget silent, no shell, WiFi also unreachable | does **not** fire |

Mode B looks like userspace stuck in an uninterruptible syscall holding a lock
the tty write path needs — but network was dead too, so it may be broader.
Prime suspect: the rolling record's raw eMMC write (was in flight every 2 s;
now 10 s). Other suspects: SDIO/MMC runtime PM, display driver first modeset.

## Traps (do not re-learn)

1. **VBUS comparators** — force bits 28/27/20/19 at 0x404 or the D+ pull-up
   never happens.
2. **`brcmfmac-wcc.ko`** — mandatory; brcmfmac requests it via modprobe, so the
   ramdisk needs `/sbin/modprobe -> busybox` and `modules.dep`.
3. **Module paths must equal `make kernelrelease`**, including `-dirty`. Any
   commit changes it: rebuild modules *and* the init.
4. **The 8 s PMC reset timer** used to reset slow boots; now behind
   `n9.hangreset`.
5. **Serial line settings** — always `stty 115200 raw -echo`; use pyserial or
   socat with one held connection.
6. **DHCP gateway** — the Pi (`192.168.1.71`) serves DHCP but the router is
   `192.168.1.1`; the lease gives LAN-only connectivity. Init forces `.1`.
7. **Never unbind/rebind `sdhci-tegra`** — it blocks in the kernel and takes
   the machine down.
8. **Loading brcmfmac seconds after boot can stall the SDIO probe** — init
   waits 20 s and runs WiFi in a child so the console survives.
9. **Record freshness** — the record's flags word now carries uptime; check it
   before believing a record is from the last boot.

## Images (persisted; `/tmp` is tmpfs)

`~/Downloads/nexus9/bootimg-build/n9-mainline/` holds the stripped images,
ramdisks, `n9root.ext4` and the compiled inits.

| Image | Purpose |
|---|---|
| `n9auto18-stripped.img` | current: 10 s record, watchdog first, shell first, WiFi+MAC in child |
| `n9auto15pm-stripped.img` | runtime PM disabled everywhere |
| `n9console-stripped.img` | no WiFi auto-load |
| `n9bare-stripped.img` | no record, no WiFi (baseline) |
| `n9audio-stripped.img` | audio modules + `/etc/audio` |

Boot them with `fastboot boot <image>` (wrapper already stripped). hboot
ignores the image roughly half the time and boots Android; detect a real
start by the `0525:a4a7` gadget. Rebuild pattern: `bootimg-repack.py
--append-cmdline "console=tty0"`, then `tail -c +257`.

## Prepared but untested

- **Audio**: `SND_SOC_TEGRA30_I2S`/`_AHUB` enabled, machine drivers
  (`nvidia,tegra-audio-rt5677`, `nvidia,tegra-audio-tfa989x-flounder`) are
  in-tree, modules packaged in `n9audio`. Never run. `rt5677-spi` is separate.
- **Bluetooth**: DT written; `bcm4354.hcd` extracted from the ROM. Never run.
- **Installed boot**: `tools/miniroot/init-boot.c` loop-mounts a raw ext4
  rootfs (`n9root.ext4`, Alpine + modules + firmware) using
  `n9.root_offset=`. Blocker: mainline cannot see the tablet's partitions
  (GPT at sector 69631). Flashing needs operator approval; boot is
  `LNX` = `mmcblk0p16` (32 MiB), rollback is the proven stock backup
  (`b26351cb…`).

## Ranked next actions

1. **Power cycle**, then read the stalled boot's record
   (`adb root; adb exec-out "dd if=/dev/block/mmcblk0 bs=512 skip=79872
   count=64"`) — its flags word carries the uptime, so a stale record is
   obvious. It should name the blocked path.
2. Run `tools/stability-run.sh` over `bare → console → pm-off → auto18` to
   isolate the stall.
3. Fix the stall (suspects above), because it blocks every long experiment.
4. Audio bring-up (smallest remaining feature with a clear plan).
5. Touch event verification (needs a finger on the panel).
6. Bluetooth.
7. Installed boot (needs approval to flash).
8. Upstream: the VBUS comparator fix and `nvidia,only-1-8v` handling.

---

# Session 2026-10-20 (evening)

Tip after this session: nexus9 `dc0e86a` (+ note commits), kernel `45145e5`.
`origin/nexus9` was pushed once on request up to `b87585c`; later commits are
local.

## Bluetooth: what was wrong, what is now true

- ~~REG_ON active low~~ — **wrong, corrected 21:10**: live Android shows
  gpio-137 `out hi` with BT on, `out lo` with BT off. REG_ON (PR1) is
  **active high**. See `bluetooth.md`; n9bt65 got the first HCI replies.
- ~~`BT_WAKE` (PEE1, gpio 241) is active low~~ — **unverified** (REA 23:50:
  Android's lpm "1" drives it raw high = awake; see `bluetooth.md`). Live Android state with
  BT on: `shutdown_gpio hi`, `bt_ext_wake hi` (idle = sleep).
- **`CRTSCTS` is 0x80000000.** Every earlier "flow control" run used 0x8000,
  so hardware flow control was never actually on.
- **32 kHz LPO was off.** Vendor marks `clk32k_kg` boot-enabled; mainline
  ignored the property. `clk-palmas` now honours `ti,clock-boot-enable` and
  the DTB sets it. Verified in the record: `n9bt: clk32kg 1`.
- **`rfkill-gpio` quirk:** it drives `reset-gpios` before `shutdown-gpios`
  and aborts on NULL, so shutdown-only nodes never probe. Our node gives both
  properties the same pin, active low. (Superseded: the node is removed,
  PR1 is active high and owned by hci_bcm's `shutdown-gpios`.)
- Programmed 3 M is really 3,040,800 (1.36% high) from the 48.65 MHz uart
  clock; reported by the temporary `n9dbg` print in `serial-tegra`.

## Where the BT bring-up stands

`btwake` now: powers PR1 off→on, asserts BT_WAKE low, opens ttyTHS2 at 3 M
with true CRTSCTS, sends `01 03 0c 00`. Still **no HCI reply**.

New observation (needs explanation): in `n9bt61` the record ends at "sending
HCI Reset" and Android was back 32 s after boot, i.e. the board seems to
reset a few seconds after the first HCI write, much earlier than the 45 s
watchdog. Test in flight: same image with `tegra_wdt.heartbeat=90`.

## Tooling truths (new)

- Repacked images **must be stripped** (`tail -c +257`) or hboot accepts the
  upload and does nothing; this caused a long false "stall" streak.
- `adb exec-out dd` returning empty makes two records compare equal; the
  reader now requires ≥32 KiB and retries.
- `/dev/kmsg` write = one record per write. Tools must build a whole line
  and write once; `sed` through a never-exiting pipe never flushes.
- every init now stamps `n9bt: start build N` so stale records are obvious.
- `tegra_wdt.early_start=1` arms the hardware watchdog at probe; stalls now
  self-reset after `heartbeat` seconds instead of needing a power cycle.

## Next actions

1. Finish the heartbeat-90 test: if the reset still happens seconds after the
   HCI write, it is not the watchdog — read the screen/panic, and try a
   plain 115200 no-flow send with 1 s settle to separate frame issues from
   hardware reset.
2. Once a reply is seen: `hciattach-min` with HCIUART_BCM, firmware
   `BCM.hcd` (from `bcm4350c0.hcd`), then BlueZ pairing.
3. Speaker: mainline tfa989x probe currently hangs the console; HAL only
   flips ALSA mixer switches (`SPK VMixer SPK Switch`).
4. Touch events, installed pmOS boot, stall root cause — unchanged priorities.

## Update 2026-10-20 21:20 — Bluetooth answers

n9bt65: HCI Reset @115200, VSC fc18 to 3M and Read Local Name
("BCM4350C0") all succeed. Root cause of the silence: REG_ON is active
**high**. Next: fix the kernel DT polarity, hand the chip to
hci_uart/hci_bcm with the vendor firmware, then BlueZ pairing. Details and
evidence in `bluetooth.md`.

---

# RESUME HERE — Bluetooth solved 2026-10-21 22:20

Supersedes every earlier "Next actions" list. Full evidence: `bluetooth.md`.

## Bluetooth: working
- **Root cause**: the BCM4354 is a Wi-Fi/BT combo; the BT firmware only runs
  properly while the WLAN side is alive. The SDIO card used to race the 32 kHz
  LPO (always-on `wifi-reg-on` regulator, one scan at host probe).
- **Fix** = kernel commit `bd93f7930` in `~/code/linux-flounder` (branch
  `usb-bringup`, local only, never push; exported as
  `patches/bluetooth-wip/0004-*.patch` on top of the three older WIP commits):
  DT `mmc-pwrseq-simple` with the Palmas `clk32kg` as `ext_clock` (replaces
  the regulator) + `hci_bcm` powers the chip in probe before serdev opens the
  UART. Everything else is upstream `hci_bcm`/`btbcm`.
- Proven: hci0 up (firmware build 0690) 3/3 repeats, no timeouts; LE scan hears
  9 distinct devices in ~11 s (`tools/miniroot/btscan-min.c`, `/etc/bt-scan`).
  Wi-Fi alone still works on the new DT (DHCP lease).
- Not done: BlueZ pairing with a real device; classic inquiry found nothing;
  Wi-Fi + BT together in one image (the n9bt101 test image started two
  wpa_supplicants — artifact); upstream series; installed rootfs with bluez.
- Handy: `tools/bt-bootloop.sh N` boots `n9bt<N>-stripped.img` and prints the
  record; `tools/bootimg-swap-ramdisk.py` swaps ramdisk/kernel region in a
  stripped image; init build recipe in `bluetooth.md` (n9bt82-84 section).
  `/tmp/n9build` is tmpfs: ramdisk templates are lost on host reboot (rebuild
  from `n9bt100-stripped.img`: `bootimg-split.py` + `cpio`).

## STATE at 2026-10-22 ~02:30 (overnight) — read this first

**First thing in the morning:** power-cycle the tablet (hold power ~15 s) and let
it charge, then run `tools/overnight.sh` (it waits for the tablet, then pulls
Wi-Fi calibration from Android, reads the Android PMIC irq registers, runs the
TFA9895 amp probe `tools/amp-probe.sh` on image `n9ampA` (REA-derived vendor
register recipe, prints amp status bits so no listener is needed), checks PMIC
irq delivery with an RTC alarm, and soaks 20 boots). Results land in
`/tmp/n9build/overnight/` (tmpfs: copy what matters into `notes/`). An
unattended launch of this script was blocked by the permission check, so it
was left for you to start.


- **Tablet is off USB** (no adb/fastboot/gadget) since ~01:35 during a soak run:
  needs a power cycle (hold power ~15 s) and probably charging (battery was
  ~flat earlier; test boots do not charge it). Nothing is flashed; everything
  is `fastboot boot`.
- Done today: **Bluetooth works** (hci0, LE scan hears devices); PMIC
  interrupt storm fixed by dropping `nvidia,invert-interrupt`; both sound
  cards register; **speaker root cause found 2026-10-22 09:10**: the bootloader
  leaves the DAP pads as GPIOs (GPIO_CNF=1), overriding the I2S function; the
  machine driver now releases them (`nvidia,i2s-pad-gpios`) and the amps lock
  (R0 `0xd05f`). Confirmed audible by the user (440 Hz, 10 %); details in `audio.md`.
  Kernel: `~/code/linux-flounder` `usb-bringup` @ `5d830bfca` (release
  `6.19.0-htc-flounder-g5d830bfca033`, image `n9ampN-stripped.img`); full
  series exported to `patches/linux-flounder-series/` (0030-0033 new).
- Open: (1) is the PMIC interrupt actually delivered after the invert fix
  (RTC alarm did not fire once; read INT status regs after an alarm to tell
  PMIC-side from delivery-side), (2) listen to the speakers, headphones (rt5506), (3) boot reliability
  soak on the fixed console (`tools/soak-dbg.sh <img> 20`, image
  `n9soak5-stripped.img`), (4) Wi-Fi+BT together in a real rootfs, BlueZ
  pairing.
- Harness lessons (do not re-learn): console must be the read-line-and-run
  shell (`/etc/n9-plainsh`) driven by `tools/n9sh.sh` (marker based);
  interactive `ash` over the gadget gets corrupted by host tty echo;
  a command inheriting the console as stdin eats later lines (init now runs
  every line with `</dev/null`); `pgrep -f`/`pkill -f` patterns can match your
  own command line; never `cat` a regmap debugfs file during an irq storm.

## NEW 2026-10-21 22:45 — likely root cause of the stalls
The Palmas PMIC interrupt storms (~1000 irq/s, i2c4 ~10k irq/s, all
`palmas_usb_vbus`) and starves the PMIC I2C bus, so every regulator operation
blocks (this is what looked like the `tfa989x` probe hang, and probably mode B
and the early stall). Android is quiet on the same hardware. Dead ends and
the REA recipe are in `stability-debug.md` (22:45 follow-up). Untested next
step: drop `nvidia,invert-interrupt` from the flounder `pmc` node (Android
has none), then re-measure `/proc/interrupts` on `n9dbgA`-style images.
Images: `n9dbgA` (consistent kernel `...gbd93f7930b07`, serial shell, all
modules staged by `tools/stage-modules.sh`); drive it with `tools/n9sh.sh`.
Never `cat` a regmap debugfs file while the storm runs: it wedges the shell.

## Next (ranked)
1. Fix the Palmas interrupt storm (above), then re-test the early stall.
2. BlueZ pairing; Wi-Fi+BT coexistence in a real rootfs.
3. Audio bring-up (`audio.md`), touch events, installed boot (needs approval
   to flash).
4. Upstream: pwrseq/LPO ordering, probe-time power, VBUS comparator fix.
