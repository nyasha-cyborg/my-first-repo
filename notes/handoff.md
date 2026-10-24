# Handoff — Nexus 9 (flounder, Tegra K1 T132) postmarketOS port

Written for an AI agent or person taking over. Read this first, then the topic note for the area you
work on. Kept current by the previous agent at each test cycle (last update: 2026-10-24 ~22:45).

## Goal and current focus

- Target: installed postmarketOS (Phosh) on the Nexus 9 with GPU acceleration and video playback.
- Current focus: **hardware H.264 decode on the VDE through mainline `tegra-vde`**. The end goal is
  4K 30 fps H.264, the K1 VDE's rated limit. YouTube serves 4K only as VP9/AV1, which the VDE cannot
  decode, so the YouTube hardware target is 1080p H.264.
- Order: inter-frame correctness (weighted prediction, B-frames), then a player path (block-linear
  dmabuf to the GPU, zero-copy), then 1080p, then lift the 1920 width cap plus "large picture" mode,
  then 4K.

## Hard rules (from the owner)

- **Use REA (reverse engineering of vendor binaries) for every hardware question before guessing.**
  Vendor blobs are in `/tmp/n9build/vendor-video/` (AVP firmware, libnvmm). The AVP video microcode is
  wrapped as a Thumb ELF with seeded function symbols: `/tmp/n9build/rea-avp/vid_ucode_fn.elf`.
  `llvm-objdump -d --triple=thumbv5te` works on it too.
- Do not flash LNX/boot partitions without the owner's OK. Test kernels are booted with
  `fastboot boot` (nothing written): `tools/pmos/pmboot.sh <img>`.
- Never write or commit modem data (EF1/EF2/RCA/CDR, IMEI), the WiFi PSK or private keys.
- Commit `notes/` + `tools/` + `patches/` to the `nexus9` repo and push (`git push origin nexus9`)
  after scanning the diff for secrets. The kernel tree `~/code/linux-flounder` stays local; export its
  changes as patches into `patches/`.
- Don't wait on the owner when the tablet hangs: it self-recovers (watchdog 180 s); pmboot retries.
- Avoid `pkill -f` patterns that match your own shell.

## Machine / tablet access

- Tablet in pmOS: `ssh root@192.168.1.109` (key auth). Android also boots sometimes (adb works); then
  run `tools/pmos/pmboot.sh ~/Downloads/nexus9/bootimg-build/n9-mainline/n9pmos-boot-vdetest.img`.
- Kernel: `~/code/linux-flounder` (branch `flounder-clean`), build output `~/code/linux-flounder-out`.
  The running test kernel is `6.19.0-htc-flounder-g0fa4171fc82c`. Module-only rebuild:
  ```
  cd ~/code/linux-flounder && make -s -C . O=$HOME/code/linux-flounder-out ARCH=arm64 LLVM=1 -j$(nproc) KERNELRELEASE=6.19.0-htc-flounder-g0fa4171fc82c modules
  llvm-strip --strip-debug -o /tmp/tegra-vde.ko ~/code/linux-flounder-out/drivers/media/platform/nvidia/tegra-vde/tegra-vde.ko
  scp /tmp/tegra-vde.ko root@192.168.1.109:/root/
  ```
- Test and score: `tools/vde-test.sh MASK [clip[:frames]...]` loads `/root/tegra-vde.ko
  t124_mask=MASK`, decodes the clips in the tablet's `/tmp` with GStreamer `v4l2slh264dec`, and compares
  them with `avdec_h264` per plane (`tools/vde-score.py`, detiler `tools/vde-detile.py`).
  Clips: `m_plain`, `m_poc0`, `m_b` (B-frames), `m_wp` (weighted P), `m_cabac` (640x360 x264);
  `v720` (real YouTube 720p, CABAC + WP; first frames are a fade from black; use `v720:12`).

## VDE state (details: notes/vde.md)

- VDE on T124/T132 is at 0x60030000. The output is block-linear (one GOB per plane), detiled in tools/.
- Each T124 change is gated by a bit in the `tegra_vde.t124_mask` module parameter (drivers/media/
  platform/nvidia/tegra-vde/h264.c). Known-good mask: **313344** (bits 11, 14, 15, 18). Bit 20 (T124
  local-memory layout) is also good: same output, no decode errors → use **1361920**.
- Bit-exact: Baseline, Main CAVLC, POC type 0, CABAC.
- Broken:
  1. **Explicit weighted prediction is not applied — hardware limitation (settled 2026-10-24).**
     Controlled pair: same fade, CAVLC, no B-frames, `weightp=0` → 100 %, `weightp=2` → 48.8 %.
     The SXE parses the weight table (removing the WP flag breaks the stream) but never applies it;
     REA shows no weight values anywhere in the host↔microcode interface. Accept as a limitation
     (only fades/crossfades affected). Do not retry register guesses.
  2. **B-frames: main clips bit-exact 2026-10-25.** T124 IRAM ref entry bit 25 is "DPB entry in use"
     (was `!(FLAG_B_FRAME)`), and the driver now applies H.264 ref_pic_list_modification with a small
     in-kernel slice parser. `m_b` is **100.00 %**, all I/P/plain-B/CABAC clips 100 %. Only
     `bpyrnormal` has a late event: display frames 84-89 wrong (first bad 84, Y 91.9-95.6 %), and
     `bdirtemporal` is 98.60 % (temporal-direct issue, separate).
- Ruled out (dead ends):
  - POC in the reference-list low bits (bit 21: worse; the hardware wants frame_num).
  - SXE 0x5c alone (needs the bit-20 list copy).
  - The SXE 0x48 17-19 alternative order.
  - MBE cmd bit 20.
  - bits 25-27, stock codec-init values for H.264 (codec id 5 in `fn_03a50`): SXE 0x08=0x35, MBE
    0x84=0x400, VDMA 0x00=0x4000|0x10, VDMA 0x1c=1. Byte-identical output.
- Not yet tested on B-frames in combination:
  - bit 22: MBE reg 2/3 = co-located buffer of RefPicList1[0] (B).
  - bit 23: MBE final command 0xfc000011.
  - bit 24: second_chroma_qp_index_offset.
- Microcode map: `fn_02040` H.264 frame driver, `fn_060c8` per-frame setup, `fn_04828` slice/ref
  lists + SXE 0x60/0x64/0x4c/0xdc, `fn_03a50` codec init, `fn_00830`/`fn_00868` BSE-V local-memory
  zero/copy commands. Local memory is addressed in words.
- The kernel code for bits 20-27 is committed in `~/code/linux-flounder` (local) and exported as
  `patches/candidates/vde/0005-*.patch`.

## NEXT TASK — finish B frames: reference list modification (start here)

State: `m_b` is **bit-exact 100 %**. The last mechanism was fixed by parsing
`ref_pic_list_modification` from the first slice header in the kernel and reordering list0/list1
(H.264 8.2.4.3). All other test clips are 100 % except:
- `bpyrnormal`: frames 84-89 wrong (99.47 % overall). **Closed as vendor-equivalent**: REA of
  libnvmmlite + libnvtvmr + the microcode shows no NVIDIA layer applies ref_pic_list_modification, so
  stock Android is equally wrong there; our m_b result is better than stock. Do not chase further.
- `bdirtemporal`: 98.60 % (temporal direct; needs the stock 0x30000000/0xAB/0x91 slice commands and
  the per-sequence 0x60 B/MB buffer init). Parked behind the playback path.
- v720/WP clips: expected failures from the weighted-prediction hardware limitation.

Next steps:
1. Re-run the m_b-style per-MB analysis on bpyrnormal display 84 (which picture is predicted from
   where; decode order around the second wrap). Add mask2 bit1 parse logging to confirm the parser
   handles those slices (ops/POC).
2. Temporal direct: find where the co-located picture's MVs come from (MBE reg 8/9 aux base, 0x40 B/MB
   per frame), compare with the stock sequence; the earlier bit22 test used the wrong mechanism.
3. Long-term refs and multi-slice frames are knowably incomplete in the parser (first slice only,
   long-term bails).

Also open (lower value): SXE 0x40 stock sets bits 15+16 (0x18000) where our bit-13 code writes
`0xc<<13` (bits 14/15); align and retest. Then output ordering, padded plane sizes, block-linear V4L2
format + modifier, zero-copy player path.

Test how-to: edit h264.c, rebuild the module, scp it, `tools/vde-test.sh <mask> clip` (mask2 via
`MASK2=n`). After every cycle: update this file and notes/vde.md, export the kernel diff to
`patches/candidates/vde/`, commit and push the nexus9 repo.

## Playback path (next milestone after B frames)

`tegra_fill_pixfmt_mp()` now aligns the capture pitch to 64-byte GOBs (width to 128) — common widths
are unchanged and still 100 %. GStreamer's v4l2slh264dec compacts output to tight caps strides in our
test pipeline, so padded-width clips can only be validated through a modifier-aware path. The full
plan (private block-linear fourcc + INTEGER64 DRM modifier control, GStreamer patch, detile fallback)
is in notes/vde.md "Playback path plan". Do not raise the profile control above MAIN until
transform_8x8 and scaling lists work.

## 2026-10-25 — current state (resume here)

- **Decode:** 1080p H.264 is **bit-exact** (Y 100 %, 60/60) after fixing an IRAM overrun above 7168 MBs
  (patch 0012). `m_b` 100 %. Weighted prediction is a hardware limitation; AU84/bpyrnormal closed as
  vendor-equivalent. **4K was abandoned by the owner** (research kept in notes/video-capabilities.md;
  4K24 was feasible, 4K30 +25 % outside the vendor block-rate certification).
- **Driver:** abort/remove/job_abort hardening and the block-linear fourcc + DRM modifier control are
  committed (local kernel tree) but NOT yet hardware-verified end-to-end; the hardened module decoded
  the regression set with faults=0 errs=0 before a transfer failed.
- **Display:** vertical lines were a transient latched state after hard crashes; bootloader, diagnostic
  and normal pmOS boots all render cleanly. If they return: leading lead is the compositor's
  block-linear scanout buffers (see the 2026-10-25 correction in notes/display-progress.md and
  notes/archive/display-2026-10-25/).
- **Boot stability (in progress):** image `/tmp/bootfix/n9bootfix-v2-stripped.img` = watchdog fed from
  the first ramdisk stage, bounded fsck, stage logs to /data, tmpfs /tmp, panel-rail handover fixes,
  LDO5 always-on, and **Palmas IRQ_TYPE_LEVEL_LOW** (the boot-storm root cause; LEVEL_HIGH is wrong).
  Kernel byte-identical; only DTB+cmdline differ. Verify with tools/soak-boot.sh IMG 10.
- **Hardware caveat:** the tablet sometimes hard-hangs during boot (USB silent) and the bootloader
  itself can wedge (enumerates but answers no fastboot command). Only a physical power press recovers
  those; the v2 boot fixes target exactly this.
- Tools added: tools/vde-test-host.sh (host reference decode), tools/soak-boot.sh, tools/pmos/push-small.sh.

## 2026-10-24 (late session, device now powered off) — resume here

Owner stopped work; tablet is off and unstable at a hardware level. Nothing was flashed in this session.

What happened (16:00–16:40):
- `n9bootfix-v2-stripped.img` was booted with `fastboot boot` at 16:24, 16:25, 16:26, 16:27 (retry loop) and
  16:29 (manual). Each fastboot upload succeeded (1.0 s), then the host saw the device back in fastboot within
  ~12 s and never got SSH. The owner saw a console with watchdog "heartbeat" lines — that is v2's own ramdisk log,
  i.e. v2 does run, but userspace never comes up (or is reset before it does).
- `/tmp/n9diag-build/n9diag-stripped.img` was booted at 16:31 and 16:34. It **does** reach its serial shell: the
  CDC-ACM gadget enumerated (`0525:a4a7`, `/dev/ttyACM0`) and `~ #` prompts were captured. With ~20 s of boot the
  device left the USB bus again (no `18d1`/`0525` device afterwards). So kernel + userspace + gadget work; the
  board resets/drops shortly after.
- Observed repeatedly: `usb 1-1: device not accepting address N, error -71` on the host, and unplugging/replugging
  the cable once **powered the tablet off** while it sat at the console.

Evidence pointing away from software:
- hboot: `battery-voltage: 4200mV`, `battery-status: good`, but **`battery-soc-ok: no`** — the fuel gauge cannot
  vouch for the pack.
- Earlier note (notes/pmos.md, 2026-10-23 18:40): the tablet once went "completely off" with Android reporting
  battery 97 % and `bootreason=cold_boot` — a thermal power cut, not a watchdog. Treat that as still unresolved.
- The diag ramdisk spawns a shell respawn loop on ttyGS0; the captured stream contains repeating
  `sh: /: Permission denied` between prompts. Not yet explained — likely the respawn `setsid sh -c ...` losing
  argv[0] under busybox. Cosmetic, but check it before trusting the diag shell.

Android: no flash was ever done on LNX/mmcblk0p16 in this session, so the installed boot image is unchanged; if
LNX still holds Lineage's boot, plain `fastboot reboot` boots Android. Verify before promising it.

Next actions when the tablet is back:
1. Let it charge off a wall charger (not a PC port), untouched, 30+ min. A dying pack explains brown-outs,
   `-71` enumerations and the power-off on replug better than any kernel change.
2. Put it in fastboot and read `fastboot getvar battery-voltage battery-soc-ok`. If `soc-ok` stays `no` after a
   long charge, stop software work and treat the battery/PMIC as the fault.
3. Boot the stock/Lineage image (`fastboot boot ~/Downloads/nexus9/bootimg-build/boot-stock-lte-N4F27P.img` or
   `boot-backup-lineage16.img`) to confirm the board is healthy in Android before any further pmOS test.
4. Only then retry `n9bootfix-v2-stripped.img` and `tools/soak-boot.sh`.
5. If the diag shell is needed again: start a persistent reader (`cat /dev/ttyACM0 > file`) **before** booting;
   the ~20 s window is too short to attach afterwards.

## 2026-10-24 evening — pmOS reinstalled and flashed to the boot partition (resume here)

Owner wiped the tablet and asked for a clean pmOS install, then for it to be permanent.

Done, in order:
1. **hboot was lying about the battery.** `fastboot flash boot` failed with `remote: 'battery low'` while hboot also
   reported `battery-voltage: 4200mV`, `battery-status: good`, `battery-soc-ok: no`. TWRP reported the pack at
   **97 %** at the same time. The state the bootloader reads the gauge in is unreliable; do not plan around
   `battery-soc-ok`. This also retires the "dying pack" hypothesis from the previous section.
2. **`/data` was destroyed by a bad format, then repaired.** I ran `make_ext4fs -s ...`, and `-s` writes a *sparse*
   image, not a raw filesystem → `EXT4-fs (mmcblk0p31): VFS: Can't find ext4 filesystem` from both TWRP and the
   installer kernel. Repaired in TWRP over adb:
   `mke2fs -t ext4 -F -m 0 /dev/block/platform/sdhci-tegra.3/by-name/UDA` (mounts cleanly, 25.1 GB).
   Never use `make_ext4fs -s` on a block device.
3. **Partition map confirmed on-device** (`/dev/block/platform/sdhci-tegra.3/by-name/`): `LNX`=boot=mmcblk0p16
   (32 MiB), `SOS`=recovery=mmcblk0p15 (32 MiB), `APP`=system=mmcblk0p29 (2654 MiB), `VNR`=vendor=mmcblk0p24
   (256 MiB), `CAC`=cache=mmcblk0p30 (256 MiB), `UDA`=userdata=mmcblk0p31 (26228 MiB), `DTB`=mmcblk0p5.
4. **Fresh pmOS rootfs built on the tablet**: booted `n9pmos-inst-stripped.img` with `fastboot boot`, brought WiFi
   up by hand (`wpa_supplicant` was running but no lease → `udhcpc -i wlan0`), ran `/bin/install-rootfs.sh`
   (867 packages, 1580 MiB, the usual harmless mkinitfs trigger error), then `tools/pmos/finish-rootfs.sh` and
   `tools/pmos/push-overlay.sh` from the host. Result: `/data/pmos/rootfs.img` 12 GiB, `user`/147147, sshd
   key-only, WiFi NM profile from the installer's `wpa_supplicant.conf`, seatd present (`/usr/bin/seatd`),
   greetd/n9-health/n9-modem enabled.
5. **pmOS boot image flashed permanently to LNX** (`mmcblk0p16`), done by streaming the image over WiFi into the
   installer's `/tmp` (socat → `nc -l -p 5001`) and `dd if=/tmp/n9pmos-boot.img of=/dev/mmcblk0p16 bs=1M conv=fsync`.
   Read-back md5 of the first 11286528 bytes equals the host image `dad73ff0d179e78f62c81bd29f4ee2aa`. **Android is
   no longer the default boot**; its boot image is still in `~/Downloads/nexus9/boot-backup-lineage16.img`
   (md5 `7296c3e1b14ad7f9abe7eb69ea8a82e2`, restore with `dd ... of=/dev/mmcblk0p16` or `fastboot flash boot`).

Operational lessons from this session (they cost hours):
- **`fastboot boot` uploads and all fastboot writes drop the device on this unit** (`Write to device failed`,
  `Status read failed (No such device)`, `error -71`). The USB link is only reliable for fastboot *commands*
  (getvar, boot of ~11 MB sometimes). Prefer: TWRP or the installer + `adb`/WiFi + `dd`.
- The installer ramdisk has **no applets on PATH**: run `/bin/busybox --install -s /bin` first, then
  `export PATH=/bin:/sbin`. `tools/n9sh.sh '<cmd>'` is the host→serial helper; `tools/n9sh.py` needs absolute paths
  (`/bin/sh: grep: not found` otherwise).
- The installer does **not** auto-run `install-rootfs.sh`; start it manually, log to `/tmp/inst.log`.
- `reboot` from the installer works (`reboot -f`); `reboot bootloader` does not.

State at hand-off (19:55): **pmOS is running from flash and Phosh is up.**

- The tablet came up on a **new DHCP lease, `192.168.1.111`** (not the old .109) — do not conclude "network dead"
  from a failed ping to .109; check the ARP table for the MAC `b4:ce:f6:df:17:d3` and sweep the /24 first.
- `ssh user@192.168.1.111` (key auth) works; root is `sudo` (password 147147, the pmbootstrap default).
- Boot-time failure seen on the first flash boot: **greetd crashed, `phoc: failed to create server: could not
  create renderer`**. Two fixes were needed and are now applied in the rootfs:
  1. `seatd` was enabled but **not started** (`rc-service seatd start`); greetd needs it for the session seat.
  2. `/etc/environment` only had `LD_LIBRARY_PATH=/opt/mesa-n9/lib`. Appended
     `GBM_ALWAYS_SOFTWARE=1`, `LIBGL_ALWAYS_SOFTWARE=1`, `WLR_RENDERER=pixman` (the known phoc-on-tegra
     fallback from notes/pmos.md) and restarted greetd → phoc + gnome-session stay up.
  Both are persisted in the rootfs, so a reboot should keep working — verify on the next boot.
- `n9-health` is logging temperatures/memory to the kernel log every 30 s; battery ~37 °C, CPU 2.5 GHz cap.

If pmOS still does not bring the network up: boot `n9pmos-inst-stripped.img` again (fastboot may need several
tries), `mount /dev/mmcblk0p31 /data`, `mount -o loop /data/pmos/rootfs.img /mnt/pmos`, and inspect
`/mnt/pmos/etc/NetworkManager/system-connections/wifi-home.nmconnection` and the `finish-rootfs.sh` assumptions.

## 2026-10-24 20:30 — CORRECTION: the battery is really low; mainline froze the gauge (see notes/charging.md)

- pmOS `capacity` 11 % vs `charge_now` 96 %: mainline's max17042 probe (no `maxim,rsns-microohm` in
  DT) zeroes CGAIN, which kills the coulomb counter in the gauge itself and freezes RepSOC — the
  register stock Android/TWRP display (REA). The real charge is ~11 % (VFOCV 3.69 V).
- So hboot's `battery low` was **right**, and "TWRP 97 %" was the frozen RepSOC. Low charge on a
  500 mA laptop port is a plausible contributor to the hangs/brown-outs below.
- DT fix exported (`patches/candidates/flounder-max17050-rsns.patch`), not booted. Gauge register
  restore pending owner OK. Charge the tablet powered off on a wall charger first.

## 2026-10-24 ~21:00 final state — pmOS running, bootloader wedge understood (resume here)

Owner asked for this note and then to stop work. The tablet is **up and usable in pmOS**.

Live state, verified over SSH at the end of the session:
- `ssh user@192.168.1.111` (DHCP lease moves between boot; **sweep 192.168.1.100-125**, do not assume .109).
  `sudo` password 147147 (pmbootstrap default, change it). Kernel `6.19.0-htc-flounder-g0fa4171fc82c`.
- `greetd` started, phoc/gnome-session running (software rendering), `networkmanager` started.
  `seatd` shows **stopped** in `rc-status` yet the phoc session came up; seatd was started by hand earlier.
  If phoc ever fails with `could not create renderer`: start seatd, and confirm `/etc/environment` still has
  `LD_LIBRARY_PATH=/opt/mesa-n9/lib`, `GBM_ALWAYS_SOFTWARE=1`, `LIBGL_ALWAYS_SOFTWARE=1`, `WLR_RENDERER=pixman`.
- **The PMIC fix is NOT active.** `/proc/interrupts` still shows `LIC 86 **Edge** palmas` and dmesg has ~44
  `4-0059` PMIC/I2C error lines. The boot partition currently holds **`n9pmos-boot-stripped.img`** (the
  known-good, un-fixed image), restored with `fastboot flash boot` on a freshly power-cycled bootloader.

What was learned about the bootloader (this cost most of the session):
- **hboot wedges after a while in fastboot.** Symptoms, in order: `getvar` hangs (`< waiting for any device >`
  while `fastboot devices` still lists it), `fastboot boot` prints `Booting OKAY` but the device drops straight
  back to fastboot, `fastboot flash` hangs with no `Sending` line, and finally the device leaves the USB bus
  (`usb 1-1: device not accepting address N, error -71`). **A physical power cycle restores it**, and on a fresh
  hboot the first commands — `fastboot flash boot` included — work reliably.
- Therefore: **do the write you need immediately after power-on**, before issuing getvar/queried commands.
- `battery-soc-ok: no` / `remote: 'battery low'` from hboot is **stale garbage** (TWRP showed 97 % at the same
  time). Do not plan around it; when a write is refused with it, power-cycle and retry.
- A `fastboot boot` failure is **not** evidence that the image is bad — both the fixed and the known-good image
  failed to boot while hboot was wedged, and the known-good one booted fine after a power cycle.

Images and how to rebuild:
- `~/Downloads/nexus9/bootimg-build/n9-mainline/n9pmos-boot-stripped.img` — known-good pmOS boot image, currently
  in LNX (`mmcblk0p16`). Its ramdisk is `tools/pmos/init` (basic: mount UDA, loop-mount rootfs, switch_root).
- `/tmp/bootfix/n9bootfix-v2-stripped.img` (md5 `81e6dbf867feb36dc6c9f9f76a54067f`) — same kernel plus the
  **hardened init** (watchdog feeder from the first second, bounded fsck, stage log to `/data/pmos/boot-init.log`,
  tmpfs `/tmp`, `/data` moved to `/android-data`) and the **Palmas `IRQ_TYPE_LEVEL_LOW` DTB**. Never confirmed on
  hardware; it was written to LNX once, then the tablet would not boot — but that was during a bootloader wedge,
  so **the image itself is not implicated**. Test it with `fastboot boot` right after a power cycle, and only
  flash it once it demonstrably boots.
- Android's original boot image: `~/Downloads/nexus9/boot-backup-lineage16.img` (md5
  `7296c3e1b14ad7f9abe7eb69ea8a82e2`), restorable with `dd of=/dev/mmcblk0p16` or `fastboot flash boot`.

Rootfs layout (fresh install done this session): `/data/pmos/rootfs.img` (12 GiB ext4 image inside UDA
`mmcblk0p31`), 867 packages, user `user`, key-only sshd, WiFi NM profile, seatd/greetd/n9-health/n9-modem
enabled. Note that Android's own `/data` tree also exists on UDA — both coexist; do not "clean" either.

Next actions, in order:
1. Power-cycle to fastboot and immediately `fastboot boot /tmp/bootfix/n9bootfix-v2-stripped.img`.
2. On that boot check `grep palmas /proc/interrupts` → must show `Level` (not `Edge`), and
   `dmesg | grep -c 4-0059` → should drop to ~0. Read `/data/pmos/boot-init.log` for the stage log.
3. If good, flash the same image to LNX (`fastboot flash boot`) on a fresh bootloader, then run
   `tools/soak-boot.sh` for 10 boots to prove the hangs are gone.
4. Then the real work resumes: compositor/GPU path, LTE (`n9-modem`), Bluetooth, and the VDE H.264 playback
   path (notes/vde.md — 1080p decode is already bit-exact).

## Other open items (see notes/gpu.md)

- Flickering blocks during video (a sync race, not caused by the WC change); backlight unsteady at low
  levels; PMIC -121 NAK bursts at DFLL takeover; LTE in pmOS; Bluetooth.
- Software playback config: `tools/pmos/etc-mpv/mpv.conf` (480p H.264, vo=gpu).
