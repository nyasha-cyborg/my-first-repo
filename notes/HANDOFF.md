# Handoff — Nexus 9 (flounder) mainline port

Written 2026-10-19 01:10 NZDT, for whoever picks this up next.

## Repos and branches

| Repo | Branch | Tip |
|---|---|---|
| `~/code/linux-flounder` | `usb-bringup` | `65429d8f7` (gated reset timer) |
| `~/code/nexus9` | `nexus9` | `fbbc02d` (init restructure) |

**Nothing is pushed.** An accidental push to the public repo was undone
(`origin/nexus9` is back at `5d0d8a3`); do not push.

Build: `make -C ~/code/linux-flounder O=~/code/linux-flounder-out ARCH=arm64
LLVM=1 -j16 Image modules`. Config lives in `linux-flounder-out/.config`,
snapshotted to `configs/flounder_defconfig`.

## Proven on hardware (this session)

- **Display** — done earlier, PR-ready.
- **USB host** — done earlier.
- **USB device mode / g_serial** — works. Root cause of years of failure:
  the core never saw VBUS because flounder reports it through the PMIC.
  Fix: force the 0x404 comparators (see `usb-debug.md`).
- **Serial console over the gadget** — reliable workbench.
- **WiFi (BCM4354, SDIO)** — association (WPA2), DHCP, DNS, ICMP, HTTP all
  verified, and the whole sequence now runs automatically on boot.
- **Touch** — `Synaptics S7504` via RMI4/SPI registered as `event0`;
  `gpio-keys` as `event1`. evdev loaded from the ramdisk.
- **Watchdog** — `tegra-wdt` initialised, 120 s heartbeat, armed by init.

## Traps found (do not re-learn these)

1. **VBUS comparators.** Without the software override at 0x404 the D+
   pull-up never happens. Bits 28/27/20/19.
2. **`brcmfmac-wcc.ko` is mandatory.** brcmfmac calls `request_module()`
   during attach; the ramdisk needs `/sbin/modprobe -> busybox` and a
   hand-written `modules.dep`.
3. **Module paths must match `make kernelrelease` exactly**, including
   `-dirty`. Every commit changes it; rebuild modules *and* the init.
4. **The old 8 s PCM reset timer** in `ci_hdrc_tegra.c` was resetting slow
   boots mid-boot. It is now gated behind `n9.hangreset`.
5. **Serial line settings.** Without `stty 115200 raw -echo` on
   `/dev/ttyACM0` every byte arrives mangled (`sh: /: Permission denied`).
   Use pyserial/socat with matching settings, not repeated `cat`/`printf`.
6. **DHCP gateway.** The Pi (`192.168.1.71`) is the DHCP server; the router
   is `192.168.1.1`. The lease's router option gives LAN-only connectivity.
   Init forces the route to `.1`.
7. **Do not unbind/rebind `sdhci-tegra`.** It blocks in the kernel and takes
   the console and machine with it.
8. **Loading brcmfmac a couple of seconds after boot can stall the SDIO
   probe.** Init waits 20 s and runs WiFi in a child process so the console
   survives either way.

## The remaining stability problem (important)

Two different stalls have been seen:

| Mode | Symptom | Watchdog |
|---|---|---|
| A | whole machine dies; USB disappears | **fires** (verified: Android `ro.boot.bootreason=watchdog`) |
| B | USB stays enumerated, gadget silent, no shell; WiFi also unreachable | does **not** fire |

Mode B looks like *userspace stuck in an uninterruptible syscall holding a
lock that the tty write path also needs*, not a dead CPU: the watchdog's
ping work still runs, so the kernel is alive. Recovery needs a power cycle.
It appeared after WiFi bring-up and also within a minute of a plain boot.
Prime suspect: the rolling record's raw eMMC write, which was in flight every
2 s. The record now writes every 10 s; `/etc/no-record` disables it entirely.

Mitigations to try, in order:
1. `/etc/no-runtime-pm` in the ramdisk makes init set every
   `power/control` to `on` (images `n9auto15-stripped.img` and
   `n9auto15pm-stripped.img` are built from the same init, PM-off variant
   via that flag file).
2. Do not auto-load brcmfmac: keep the console usable and load WiFi by hand.
3. Read the rolling DTB-partition record after the next reset — it holds the
   kernel log up to the stall and will name the blocked path.

## Prepared but untested

- **Audio**: the machine drivers were already in the tree —
  `nvidia,tegra-audio-rt5677` (headphones/mics) and
  `nvidia,tegra-audio-tfa989x-flounder` (speakers, added by the port) — and
  the DT sound nodes carry both compatibles. What was missing was the
  **Tegra30 I2S/AHUB support in the kernel config**; it is now enabled
  (`SND_SOC_TEGRA30_I2S`/`_AHUB` = m), and the audio modules are assembled
  into `/tmp/audio-ramdisk.gz` (image `/tmp/n9audio-stripped.img`), loaded by
  init when `/etc/audio` exists. Never run on hardware.
  Note `rt5677-spi` is a separate module (the DSP interface).
- **Bluetooth** (`notes/bluetooth.md`): DT written; `bcm4354.hcd` extracted
  from the vendor partition.
- **Installed boot** (`notes/flash-plan.md`): everything so far runs via
  `fastboot boot` with an initramfs. No rootfs on flash yet. Flashing was
  never approved and never attempted.

## Test images and how they were built

- Images (all wrapper-stripped with `tail -c +257`, booted with `fastboot boot`):
  `n9auto14` (last verified working), `n9auto15`/`n9auto15pm`
  (runtime-PM on/off), `n9console` (no WiFi auto-load), `n9audio` (audio
  modules + `/etc/audio`).
- Ramdisk: busybox-static (Alpine), `/sbin/wpa_supplicant` + libs
  (musl, libnl3, libcrypto/libssl, dbus-libs, pcslite),
  `/lib/modules/<release>/{rfkill,evdev,cfg80211,brcmutil,brcmfmac,brcmfmac-wcc}.ko`,
  `/lib/firmware/brcm/brcmfmac4354-sdio.{bin,clm_blob}` + the NVIDIA
  p2371 NVRAM copied to `brcmfmac4354-sdio.txt`, and
  `/etc/wpa_supplicant.conf` (local only — contains the SSID and a derived
  PSK; never commit it, never serve the ramdisk directory over the network).
- Harnesses: `tools/miniroot/init-auto.c` (this image),
  `init-live.c`, `init-wifi.c`, `udhcpc-default.sh`, `tools/watch-n9.sh`.
- Boot success with `fastboot boot` is ~50%; hboot silently falls back to
  Android. Detect a real kernel start by the `0525:a4a7` gadget appearing.

## Ranked next actions

1. **Installed boot.** Flash a boot image and a rootfs so the tablet starts
   Linux without a host. This unlocks everything else (packages, audio
   userspace, Bluetooth daemon). Needs explicit user approval to flash.
2. **Audio.** Build the two-link machine driver from `notes/audio.md`.
3. **Bluetooth.** Load the firmware and bring up `hci0`.
4. **Touch verification.** Read `event0` while touching the panel; evdev
   nodes exist but no input has been observed yet.
5. **SDIO retry policy.** If the card ever fails to enumerate, prefer a
   reboot over poking `sdhci-tegra`.
6. **Upstream.** The VBUS comparator fix and the `nvidia,only-1-8v` handling
   are genuine mainline fixes; both need review before sending.
7. **MAC address.** The chip reports `00:90:4c:16:70:01`. Init now applies
   `flounder.wifimacaddr` from the kernel command line to `wlan0`
   (`B4:CE:F6:DF:17:D3` on this unit); a proper vendor NVRAM would still be
   better.
8. **Read the DTB-partition record after the next reset** (sector 79872 of
   `mmcblk0`, 32 KiB) — it holds the kernel log up to the stall.
