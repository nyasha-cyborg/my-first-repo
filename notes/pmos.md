# postmarketOS install (rootfs image in Android's /data)

Decisions (user, 2026-10-23): keep LineageOS; pmOS root filesystem = ext4 image file `/data/pmos/rootfs.img` inside
userdata (`UDA` = mmcblk0p31, 25.6 GB, **not encrypted**: plain names, mountable from mainline); only `LNX`
(boot, mmcblk0p16) gets flashed at the very end, after asking. Boot backup `b26351cb…`, restore proven.
Until then everything is tested with `fastboot boot`.

## Layout

| Piece | What |
|---|---|
| `tools/pmos/build.sh` | host: installer image `n9pmos-inst`, pmOS boot image `n9pmos-boot`, `overlay.tgz` |
| `tools/pmos/install-rootfs.sh` | tablet (installer ramdisk): mke2fs via apk-staged e2fsprogs, `apk.static` pmOS v26.06 + Alpine v3.24 |
| `tools/pmos/push-overlay.sh` | host -> tablet over WiFi: modules, firmware, LTE modem service + firmware, ssh key |
| `tools/pmos/finish-rootfs.sh` | tablet: user `user` (screen PIN 147147, pmbootstrap default — change it), SSH key-only (no password, no root), services, ttyGS0 root autologin (USB only), WiFi |
| `tools/pmos/init` | pmOS boot ramdisk: busybox, mounts UDA, loop-mounts the image, `switch_root` to OpenRC; rescue shell on ttyGS0 |

- No pmbootstrap: it needs sudo (password on this host). The rootfs is built on the tablet with `apk.static` (native
  aarch64, scripts run for real). Package signatures verified with alpine-keys + postmarketos-keys fetched by build.sh.
- `device-htc-flounder` (v5, still in v26.06) gives the deviceinfo/firmware deps; its kernel dependency
  `linux-htc-flounder` (yuka/linux) is satisfied by an empty virtual package — our kernel/modules come from the overlay.
- OpenRC (main repo); systemd is only in pmOS `extra-repos/systemd`.
- pmOS boot cmdline drops the test images' `tegra_wdt.early_start=1 heartbeat=90` (nothing would feed it).

## Gotchas hit (2026-10-23)

- The test init's DHCP hook writes `nameserver A B` on one line -> no DNS. install-rootfs.sh normalises it.
- `apk.static` (OpenSSL) reads the CA file `/etc/ssl/cert.pem` **relative to `--root`**; `-U` needed on a fresh root.
- `linux-flounder-out` was stale (kernel.release regenerated without a rebuild): build.sh now checks the Image's
  `Linux version` string equals `make kernelrelease`.
- Modules are `.ko.zst` (`MODULE_COMPRESS_ALL`); the installer ramdisk gets uncompressed ones from stage-modules.sh.

## Status

- 11:40 installer `n9pmos-inst` booted (kernel gcfc538ce0338, WiFi 192.168.1.100), rootfs.img created (12 GiB),
  package install running.
- 11:47 first install attempt cut by a watchdog reset at package ~670 (installer image armed the 90 s watchdog;
  most likely the test init's busybox feeder died under load). Installer now: no watchdog cmdline, e2fsck before
  remount, kmsg + memory logs on userdata. Second run: 872 packages, 1.59 GB; only error = postmarketos-mkinitfs
  trigger (no pmOS kernel package; we use our own boot image) — harmless.
- 12:03 **pmOS v26.06 boots** (`fastboot boot n9pmos-boot`): OpenRC up, NetworkManager joined WiFi (192.168.1.109),
  sshd (key only), elogind, bluetooth, zram, root autologin on ttyGS0.
- greetd crashed, two causes, both fixed (baked into finish-rootfs.sh):
  1. `libseat: No backend was able to open a seat` -> `apk add seatd seatd-openrc`, enable seatd, greetd + user in `seat`.
  2. phoc segfaults in the GPU path (Mesa 26.1.6 `tegra` renderer, GLES 3.2, crashes on the first draw; `kmscube -D
     /dev/dri/card0` too; plain `kmscube` picks card1 = nouveau without connectors). Workaround: software rendering via
     `/etc/environment` (greetd gives the greeter a clean PAM env, conf.d exports don't reach it):
     `GBM_ALWAYS_SOFTWARE=1 LIBGL_ALWAYS_SOFTWARE=1 WLR_RENDERER=pixman` (phoc's GLES renderer fails on software GBM
     and falls back to Vulkan -> pixman for the compositor, llvmpipe for apps; kmscube on llvmpipe renders fine).
- 12:13 greetd started, phoc + phrog running -> Phosh lock screen expected on the panel.
- Access: `ssh user@<ip>` and `ssh root@<ip>` with the laptop key only (PermitRootLogin prohibit-password).
- `openssh` in PKGS pulled the non-PAM sshd (pmOS's `UsePAM` policy line then errors, sshd still works): removed from PKGS.
- `n9-modem` service: stopped at boot — not looked at yet.
- 12:25 first boot hung ~2 min after greetd started (mode B: gadget enumerated, no shell, no WiFi); no watchdog in that
  boot -> power cycle. Now: watchdog armed + fed, kernel log in /var/log/kmsg.log (5 s sync), greetd opt-in.
- 12:50 second boot stable. User saw the text console (fbcon works). kmscube (llvmpipe) on card0: **cube visible** —
  KMS scanout works (it quit after <1 s only because its stdin was closed: run it as `sleep 40 | kmscube ...`).
- 12:56 greetd started by hand: phoc + gnome-session (non-systemd fallback) + phosh-osk-stevia + phrog. **The user saw
  the PIN screen, typed 147147 with the touch keyboard and logged in** (slow, software rendering). Phosh session
  c16 on seat0/tty7: phoc, gnome-session --session=phosh, phosh. Touch works. greetd autostart re-enabled.
- The 12:25 hang is unexplained (no log); kmsg.log now keeps evidence if it recurs.

## 2026-10-23 13:00-13:40 — hangs, logging, modem service in pmOS

- 12:57 hang #2, ~8 min after login: watchdog reset (whole machine). Last kernel line `[487.6] rfkill: input handler
  disabled` (Phosh session start), then silence, no oops. WiFi died first in both session hangs.
- 13:09 hang #3: boot without greetd; **watchdog did not fire**, OpenRC never reached `local` (kmsg.log not rotated),
  no ttyGS0 login, no WiFi -> looked like OpenRC blocked in an early stage while the busybox watchdog daemon kept
  feeding. Power cycle by the user. No rfkill state was ever saved (/var/lib/rfkill absent) -> not an rfkill restore.
- Diagnostics added (in the image + repo): `n9-kmsg` OpenRC service in sysinit (kernel log from the start, 5 s
  sync, previous boot = kmsg.log.1), `rc_logger="YES"` (/var/log/rc.log); disabled ModemManager (fights n9-modem)
  and iio-sensor-proxy (no sensors). Boot #4 (13:26) came up cleanly in ~1 min.
- n9-modem in pmOS: (1) mdm-boot.sh hard-coded /bin helpers -> look next to the script; (2) udev autoloads
  `qcserial` for the boot ROM 05c6:9008 -> `sahara: claim interface failed 16` -> blacklisted
  (/etc/modprobe.d/n9-modem.conf); (3) a retry saw the stale 9008 (host never sees the modem reset) -> re-enumerate
  before Sahara. Then: 15 images, STATUS=1, 9048, APN/raw IP/online all error 0, but START_NETWORK error 14 x30:
  **the SIM was out of the tray** (UIM card state 2, camped 530-01 limited). User reinserted it 13:40.
- qmi-probe.py works over SSH on pmOS: `N9SSH=root@192.168.1.109 QMIRAW=/usr/lib/n9-modem/qmiraw`.
- Open: cause of the session hang (rfkill/BT-WiFi combo suspicion, not proven), the 13:09 early-boot block.

## 2026-10-23 14:00-15:20 — GPU on, still unstable after login; diagnostics hardened (user asleep, tablet stuck)

- GPU path works (patched Mesa, notes/gpu.md): login screen + Phosh home on the GK20A. User: "glitchy" — graphics
  corruption right after entering the PIN (greeter -> session hand-off), then the tablet dies within minutes.
- Session hang signature (3x now, software AND GPU rendering): kernel log ends `rfkill: input handler disabled`
  (gnome-settings-daemon at session start), no oops. Attempts this round: GK20A DVFS off + fixed pstate
  (series 0034/0035; NvClkMode is refused because allow_reclock=false), GPU behind the SMMU (0036), cma=256M.
  Corruption remained after the SMMU change (whether the SMMU attach really happened is NOT verified yet).
- Early-boot stalls (13:09, 14:38): turned out to include my own bug — the new boot ramdisk's e2fsck lacked
  libeconf (rc 127) and /init dropped to the rescue shell (no watchdog feeding -> reset). Found via the new synced
  /data/pmos/boot-init.log (readable from Android: `adb root; adb shell cat /data/pmos/boot-init.log`). Fixed:
  libraries resolved recursively, 126/127 never blocks boot.
- Autologin (greetd [initial_session], command from phosh.desktop = `phosh-session`): the user still got the PIN pad
  -> probably the initial session exited at once and greetd fell back to the greeter. Check greetd/phrog logs.
- 15:05 stuck in "mode B": ping OK, sshd refused, serial dead, screen unstable; busybox watchdog kept feeding -> no
  reset for >10 min -> needs a power cycle (user asleep). New: n9-health (feeds only while sshd's banner answers and
  fork/exec works; 30 s health log of memory/load/top processes into the kernel log) — not yet tested.
- Hypotheses still open: (1) memory exhaustion (services dying first, ping alive) — the health log will show it;
  (2) radio/rfkill at session start (BCM4354 WiFi/BT combo); (3) GPU writes to wrong memory (corruption).
- Next (one variable per boot): baseline = software rendering + bluetooth/rfkill services off + n9-health; if
  stable, add GPU; then bluetooth; check SMMU attach (`ls /sys/kernel/iommu_groups`, dmesg) and autologin logs.

## 2026-10-23 17:40 — NEW LEAD: the Palmas PMIC goes silent on I2C (hang at 700 s, also a burst at boot)

kmsg.log of the 15:00 session (it lived ~11 min): session start at 69.6 s fine, then at 700.4 s a burst of
`dummy 4-0059: Failed to read IRQ status: -121` (Palmas interrupt block, i2c-4 0x59, -EREMOTEIO = no ACK) and the
end of the log. 79 such lines in total; the first burst is at boot 11.79 s, in the middle of the simple-framebuffer
handover: `simple-framebuffer ... fb0 registered` -> PMIC I2C errors -> `avdd-dsi-csi: failed to disable: -EREMOTEIO`
-> `WARNING regulator_put` (released while enabled). No kernel lines at all between 69 s and 700 s.
Hypothesis: a display-path rail change (screen blank / DPMS after ~10 min idle; simplefb handover at boot) makes the
PMIC stop answering on I2C; its IRQ handler then storms, starving userspace (ping alive, services dead = "mode B").
The user saw the screen go "black lit / not stable" right before. Earlier session hangs (~2-8 min) may be the
greeter/session idle blank.
Test setup (boot 17:45): baseline (software rendering, bluetooth/rfkill/n9-modem off) + n9-health + regulator
tracepoints streamed into the kernel log (`/etc/local.d/n9-regtrace.start`, tools/pmos/n9-regtrace.start).
Plan: idle-delay 30 s -> force a blank -> look for regulator events + PMIC -121 at that moment.

## 2026-10-23 18:00 — screen blank reproduces the PMIC I2C failure (not memory, not GPU, not BT)

Baseline boot (software rendering, bluetooth/rfkill/n9-modem off, n9-health on, autologin worked: session c1 on
seat0 at boot). dconf `idle-delay=30` -> at 122.7 s DPMS Off (bl_power 4) and at that exact moment a burst of
`dummy 4-0059: Failed to read IRQ status: -121` (~10 ms, 12 lines). n9-health just before: MemAvailable 1079M,
SwapFree 2756M, CmaFree 255M -> NOT memory. This time the system survived (still alive 6 min later); the 700 s
death in the previous session was the same burst. Reproducible trigger = display blank.
- regulator_summary while blanked: panel consumers (54300000.dsi.0-avdd/-iovdd, dsi avdd-dsi-csi) = 0, but
  `ac001000.framebuffer-*` (simple-framebuffer) still hold avdd-lcd / iovdd-lcd / avdd-dsi-csi -> rails never
  switch off; simplefb leaks them on takeover (boot `WARNING regulator_put` + `avdd-dsi-csi: failed to disable:
  -EREMOTEIO` inside the boot-time PMIC burst).
- REA, vendor panel `dsi_j_qxga_8_9_{disable,postpoweron}`: GPIO table lcmio_1v8=130(Q2) avdd_4v=136(R0)
  dcdc_en=245(EE5) panel_rst=61(H5) = our DT. Our flounder driver `panel-jdi-lpm089a128a.c` already reproduces the
  vendor order/delays (off: rst, 1 ms, dcdc, 15 ms, avdd, iovdd, 10 ms; on: iovdd, avdd, 1 ms, dcdc, 15 ms, reset).
  So the panel sequence is not the difference; candidates: leaked rails staying on, backlight, DSI/DC power-down.
- No ftrace regulator events in this kernel (tracefs absent) -> n9-regtrace does nothing; regulator_summary
  snapshots instead.
Next: backlight-only off/on (bl_power) vs DPMS; then drop the simple-framebuffer supplies in the DT.
- 18:10 remote DPMS control works through Phosh's D-Bus (`org.gnome.Mutter.DisplayConfig` PowerSaveMode 3/0 on the
  user's session bus; `wlopm` is refused by phoc). 3 cycles: every DPMS **off** = +20..41 PMIC errors, every **on** = 0.
  Backlight-only off/on (bl_power 4/0) = 0 errors. Waking via the power button = 0 errors. Trigger = display
  power-down path. Next: `panel_jdi_lpm089a128a.keep_power=1` (series 0037) keeps panel rails + DC-DC on at blank.
- 18:30 keep_power test (kernel gda5b5a71ad89, same boot, PowerSaveMode 3/0 via D-Bus):
  keep_power=0: cycles with PMIC errors 2/3 (+36, +30); keep_power=1: 0/3. With simplefb holding avdd/iovdd, the only
  hardware switched at blank is panel reset (H5) + dcdc_en (EE5): one of those trips the PMIC (I2C NAK + IRQ storm).
  Interim fix candidate: `panel_jdi_lpm089a128a.keep_power=1` on the pmOS cmdline. Root cause next: let the rails
  really switch off like Android (drop simple-framebuffer *-supply), then retest keep_power=0.
- 18:35 kernel gae4187faf21b (GK20A slide fallback, series 0038): autologin session at boot, keep_power=Y, GPU Mesa +
  WLR_DRM_NO_MODIFIERS=1 (linear buffers: user "a bit more stable" vs block-linear), no PLL slide warnings yet.
  CPU: schedutil works, 204 MHz..2.499 GHz on mainline; capped at 2.295 GHz (stock max) via local.d n9-cpucap.
