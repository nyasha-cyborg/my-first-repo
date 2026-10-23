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
  2. **B-frames drift.** Exact up to frame 3, then 81-92 %.
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

## NEXT TASK — B-frame drift (start here)

Tests A (per-slice SXE 0x60/0x64/0xdc/0x50) and B (MBE bits 22/23) were run on 2026-10-24 and are
dead ends; WP is settled as a hardware limitation. Details in notes/vde.md (22:40).

Baseline `m_b` (Main CAVLC, B-pyramid): Y **91.81 %** (min 81.34), first imperfect frame **4**,
30/30 frames, no faults. Frame 0-3 exact, then 97 % → 81 % by frame 29. I/P frames are exact, so the
problem is B-frame motion compensation: direct mode / co-located picture selection or ref-list order.

Leads to try, in order:
1. **MBE ref-list commands.** Stock `fn_05434` writes `0xC0000000 | 4 ref indices (6 bits each) |
   list<<26 | group<<24` for lists 0/1, then `0xCC000000|ref0` ("first ref") and the `0x30000000`
   pattern. Compare exactly with mainline's `tegra_vde_setup_mbe_frame_idx()`/frame-id tables for a
   B frame; the T124 MBE may want the list-1/co-located entries in a different table slot.
2. **Co-located buffer layout.** Stock `fn_060c8` zeroes/copies a per-MB co-located buffer of
   0x40 bytes/MB per frame index (MBE 0xA reg 8/9 = buffer, mainline points it at
   `dpb_frames[0].aux_addr`). Check whether B frames need the aux of the *colocated_ref_idx* frame
   (per slice), not dpb_frames[0].
3. **SXE 0x40 bits 17-20** = picture structure per frame; stock bits 22/23/24-25 also derive from
   field/entropy flags. Mainline T124 keeps only BIT(21)|BIT(26)|(0xc<<13); stock sets bits 15+16
   (0x18000) and bit 12 conditionally. Low risk to align these with `fn_060c8`/`fn_01a94`.
4. Only after B-frames: output ordering (one duplicated frame at the start), padded plane sizes,
   block-linear V4L2 format + modifier, then the zero-copy player path.

Test how-to (unchanged): edit h264.c, rebuild the module, scp it, `tools/vde-test.sh <mask> m_b`.
After every cycle: update this file and notes/vde.md, export the kernel diff to
`patches/candidates/vde/`, commit and push the nexus9 repo.

## Other open items (see notes/gpu.md)

- Flickering blocks during video (a sync race, not caused by the WC change); backlight unsteady at low
  levels; PMIC -121 NAK bursts at DFLL takeover; LTE in pmOS; Bluetooth.
- Software playback config: `tools/pmos/etc-mpv/mpv.conf` (480p H.264, vo=gpu).
