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

- **The chip was powered off the whole time.** On flounder `BT_REG_ON` (PR1,
  gpio 137) is **active low**: the vendor DTB lists it in `gpio-output-low`
  and `bluedroid_pm` powers on by writing 0. Our always-on regulator held it
  high = shutdown.
- **`BT_WAKE` (PEE1, gpio 241) is also active low.** Live Android state with
  BT on: `shutdown_gpio lo`, `bt_ext_wake hi` (idle = sleep).
- **`CRTSCTS` is 0x80000000.** Every earlier "flow control" run used 0x8000,
  so hardware flow control was never actually on.
- **32 kHz LPO was off.** Vendor marks `clk32k_kg` boot-enabled; mainline
  ignored the property. `clk-palmas` now honours `ti,clock-boot-enable` and
  the DTB sets it. Verified in the record: `n9bt: clk32kg 1`.
- **`rfkill-gpio` quirk:** it drives `reset-gpios` before `shutdown-gpios`
  and aborts on NULL, so shutdown-only nodes never probe. Our node gives both
  properties the same pin, active low.
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
