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

## Other open items (see notes/gpu.md)

- Flickering blocks during video (a sync race, not caused by the WC change); backlight unsteady at low
  levels; PMIC -121 NAK bursts at DFLL takeover; LTE in pmOS; Bluetooth.
- Software playback config: `tools/pmos/etc-mpv/mpv.conf` (480p H.264, vo=gpu).
