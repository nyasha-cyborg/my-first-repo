# VDE (hardware H.264 decode) on Tegra132 — mainline tegra-vde bring-up

Goal: hardware H.264 decode for video/YouTube (CPU software decode: 720p 1.1x realtime, 480p 2.1x; see
notes/gpu.md). Tegra K1 VDE spec: H.264 up to High L5.1 (4K30). Mainline tegra-vde caps T124 at 1920x2032
and lists **no** T124 output formats ("TBD: T124 supports only a non-standard Tegra tiled format").
No mainline Tegra124/132 board has a VDE node.

## Bring-up history (conclusions only; details in patches/candidates/vde and git log)

- DT: `vde@60030000` on tegra132 (compatible tegra132-vde/tegra124-vde), SPI 9/10/12, clocks VDE+BSEV,
  resets vde/mc/bsev, iommus SWGROUP_VDE, 4 KiB `vde_pool` in `sram@40000000`. The T20-T114 register
  window (0x6001a000) is dead on T132 (reads 0xcacad0d0); the stock AVP microcode uses 0x60030000.
- Block map: SXE 0x30000, BSE-V 0x31000 (+0x31800), MBE 0x32000, PPE 0x32200, MCE 0x32400,
  TFE 0x32600, VDMA 0x32a00, extra 0x32c00/0x32e00, frame-id 0x33800, extra 0x33a00/0x33c00.
- Output layout (measured, bit-exact): each plane is 1-GOB NVIDIA block-linear,
  off = ((y/8)*(pitch/64)+x/64)*512 + ((x%64)/32)*256 + ((y%8)/2)*64 + ((x%32)/16)*32 + (y%2)*16 + x%16;
  = DRM_FORMAT_MOD_NVIDIA_16BX2_BLOCK(0). Pitch must be a whole number of 64-byte GOBs (width aligned
  to 128). tools/vde-detile.py; planes must be padded (640x360 needs 368 rows).
- REA of the AVP video microcode (`nvavp_vid_ucode_alt.bin`, wrapper /tmp/n9build/rea-avp/
  vid_ucode_fn.elf): fn_03a50 codec init, fn_060c8 per-frame setup (frame-id tables, SXE 0x40/0x44/0x48),
  fn_04828 slice/ref lists + SXE regs, fn_05434 per-slice MBE lists, fn_01a94 authoritative SXE slice setup.
- Fixes found and kept (mask `tegra_vde.t124_mask`; known-good **1361920** = bits 11, 14, 15, 18, 20):
  frame-id luma entry bit 31 for progressive frames; SXE 0x40 bits 17-20 = picture structure; SXE 0x48
  bit 17/18-19 = weighted_pred/bipred; bit 20 + BSE-V 0xA4 bit 0 = CABAC (bit-exact 30/30);
  bit 20 = T124 local-memory layout (slice bitmap/0x1820 scratch/0x3620 lists/MCE 0x1c20/0x38b4).
- Baselines: Baseline 720p 100 %, Main CAVLC 100 %, POC type 0 100 %, CABAC 100 %.
- Dead ends: SXE 0x54/0x58/0x5c/0x70/0x74 values; PPE 0x00/08/0c; codec-init bits 25-27; POC in the
  ref-id low bits (bit 21); per-slice SXE 0x60/0x64/0xdc/0x50 (bits 28-31, patch 0006); MBE final
  0xfc000011 (bit 23, worse); SXE 0x5c=0x3620 faults.
- Test hygiene: references from a complete avdec decode (eos-after=1 emits an extra frame); /tmp on the
  tablet is rootfs; 124 MB dumps fill it. tools/vde-test.sh MASK clip (MASK2 env) + tools/vde-score.py.

## 2026-10-24 22:40 — explicit WP: parsed, not applied (controlled proof); per-slice SXE and bit 22/23 dead ends

Test A from the handoff (per-slice SXE 0x60/0x64/0xdc/0x50) — **dead end**. Kernel now has bits 28-31
for the four registers. Each alone: byte-identical `m_b` (Y 91.81, first<100: 4). All four together:
SMMU faults, `m_b` 5.83 %, `m_wp` no output. Nothing on `m_wp`/`v720:12` either.
Test B — bit 22 (MBE reg 2/3 co-located): no effect (`m_b` 91.81). Bit 23 (MBE final 0xfc000011):
**worse** (87.89 %, 5 faults); bit22+23 88.27 %. Dead ends.

**Controlled WP proof** (new clips `wp2.mp4` / `wp0.mp4` on the tablet; same testsrc2 fade-in, x264
Main, CAVLC, bframes=0, keyint 30, qp 20; only `weightp=2` vs `0` differs):

| clip | frames | Y exact |
|------|--------|---------|
| wp0 (no WP) | 60 | **100.00 %** |
| wp2 (WP) | 60 | 48.82 % (first<100: 1) |

So WP is the sole variable. Dropping the SXE WP flag bit (mask 1329152) breaks WP streams outright
(`m_wp` no output, `v720` decodes 1 frame), i.e. **the hardware does parse the weight table** — but the
weights are not applied.

REA of the vendor stack (`libnvmmlite_video.so`, `vid_ucode_fn.elf`):
- Host parser `FUN_000478dc`: weights go into the slice struct at +0x9c (luma_log2_denom), +0xa0
  (chroma denom), packed per-ref bytes from +0xa4 (luma, Cb, Cr; stride 3, 16 refs; list1 +0xd5).
- Microcode host interface (`fn_059a4`, `fn_060c8`, `fn_04828`): every host field read is accounted for
  (width/height, slice flags at +0x1e..0x2f, ref lists at +0xb4/+0xd4, ref-marking ops at +0x9c, scaling
  lists at +0x19c). **No weight table is read anywhere, and no `fn_00868` copy writes one to local
  memory.** The 20 MBE 0xA-reg values come from `0xa1`/`0xa5`/`0xa9` commands only.
- Authoritative T124 SXE 0x48 (from `fn_01a94`, the slice setup; matches what we set): bits 0-4
  chroma_qp_offset, 5-9 num_ref_idx_l0, 10-14 l1, 15 flag, **17 weighted_pred, 18-19 weighted_bipred_idc**,
  20 entropy, 21 flag, 22-26 second_chroma_qp_offset. SXE 0x40 stock: bits 0-4 log2_max_frame_num,
  5-6 poc_type, 7-11 log2_max_poc, 15+16 constant (our bit 13 uses `0xc<<13` = bits 14/15 — likely
  should be 0x18000; untested).
- Conclusion: the VDE does not apply explicit weights; there is no place in the stock microcode/params
  where weights could be handed to the MBE. Corroboration: libvdpau-tegra (same VDE author) refuses
  explicit WP outright ("Explicit weighted prediction unimplemented").

## 2026-10-25 00:30 — B frames: IRAM bit 25 is "DPB entry in use", not "!B" (big step)

Controlled clips (all 640x360, testsrc2, Main CAVLC, weightp/weightb off) isolated the B problem:

| clip | params | Y exact |
|------|--------|---------|
| b1ref | bframes=1, ref=1 | 100 % |
| bdirspatial | bframes=2, no pyramid, direct=spatial | 100 % |
| bdirtemporal | bframes=2, no pyramid, direct=temporal | 98.60 % (first<100: 1) |
| bpyrnone | bframes=3, b-pyramid=none | 100 % |
| bpyrnormal | bframes=3, b-pyramid=normal | 93.53 % (first<100: 5) |
| m_b | x264 B-pyramid | 91.81 % (first<100: 4) |

Subagent error-map analysis of m_b's first bad frame: errors concentrate on bi-predicted (75 % of X
MBs bad) and L1-only (41 %) macroblocks, max|d| up to 82; direct-skip MBs are 97.4 % exact, and bad
output sits on the *correct* frame (not a stale reference). So list1/B-reference handling, not direct
prediction or residual. Drift accumulates through references.

REA of stock `fn_04828` IRAM ref-table entries: bits 26-31 = DPB index, bit 25 = `record[0] & 1` =
**DPB entry in use**, bit 24 = `record[6] == 0` = !long_term, low 18 = frame_num (or 0x40000 +
LongTermPicNum). Mainline wrote bit 25 = `!(FLAG_B_FRAME)`, so **every B picture used as a reference
was marked unusable**. Fix: set bit 25 for every T124 ref (`vde->soc->t124_layout`). Results:
`m_b` 91.81 → **97.80 %** (first bad 4 → 24), `bpyrnormal` 93.53 → **99.29 %** (5 → 58),
`bpyrnone` stays 100 %. The bit is one of the two B-only fields (the other, bit 24, was already 1).

Subagent per-MB/MV analysis of the first bad frames found the remaining mechanism: at the first P
slice after frame_num wraps (15 -> 0), `ref_idx 0` resolved to B21 instead of P23 — a swap of the top
two list0 entries. P_Skip MBs matched a bilinear prediction from the wrong picture (SAD 0.00), and the
B frames after it inherited P26's corrupted pixels. Cause: the driver ordered list0 from the default
(PicNum) sort; the stream's `ref_pic_list_modification` (x264 ops [0,1,0,3]) reorders it to put P23
first. The wrap is only when default and modified order diverge, which is why pre-wrap P frames were
exact. IRAM ref IDs as POC (bit 21) made everything much worse (m_b 76.34 %), proving the hardware
uses the driver's list order, not the ID field.

**Fix (2026-10-25): apply ref_pic_list_modification in the kernel.** A minimal slice-header parser
(Annex-B scan, exp-Golomb, fields up to the modification lists) runs on the first slice of each frame
and reorders list0/list1 per H.264 8.2.4.3 (short-term refs; long-term/multi-slice are best effort).
Default on T124, mask2 bit 7 can force/disable it; mask2 bit 1 logs parse results. Results:
`m_b` 97.80 → **100.00 %**, `bpyrnormal` 99.29 → **99.47 %** (first bad 58 → 84), everything else
unchanged. `bdirtemporal` is still 98.60 % (separate temporal-direct issue).

Remaining: one independent failure in bpyrnormal (display 87, decode #84; later frames propagate).
Per-MB/MV analysis: the slice is the first P after a frame_num wrap with three list0 modifications
(expected [83,81,79]), but the hardware used the *base* order [81,83,79] — a clean top-two swap; every
other modified slice in the clip is honoured, including a post-wrap P at decode #88 with base != spec.
Host emulation of `n9_h264_parse_slice`/`n9_apply_mods` on that exact AU returns the correct list, so
the runtime parse must have failed for that AU. Leading cause: an emulation-prevention 0x03 inside the
slice header (not stripped) → fixed by copying the header with EPBs removed before bit parsing
(2026-10-25, unverified — tablet died before the test). A log with the parsed fn/poc/ops per frame is
available (t124_mask2 bit 1). GStreamer still cannot supply SLICE_PARAMS lists in frame-based mode;
the in-kernel parser is the workaround (multi-slice/long-term remain best effort).

Dead ends: MBE list1 `0xC4000000` group commands (mask2 bit 0, verified to run, no effect); MBE A reg
2/3 colocated aux (t124 bit 22); MBE per-MB buffer (bit 10); unwrapped ref `frame_num` (mask2 bit 3);
POC in IRAM IDs (bit 21). t124_mask2: bit0 list1 cmds (dead), bit1 logs, bit2 force in-use (default on
T124), bit3 raw frame_num (dead), bit5 slice-params log, bit6 fmt log, bit7 force modification parse.

## Playback path plan (2026-10-25, read-only audit)

- Capture geometry (driver-only, first step): `tegra_fill_pixfmt_mp()` in v4l2.c now uses a 64-byte-GOB
  pitch (`ALIGN(width,128)`; chroma half). Verified via a fmt log: 848x480 -> bpl 896, 640x360 -> 640x368,
  bpl 640. Gotcha: GStreamer's v4l2slh264dec in this path compacts the output to the caps width/height
  (tight stride), so a 896-pitch hardware output cannot be scored through `! video/x-raw ! filesink`
  (w848 scores 20 % while all 128-multiple widths stay 100 %). Every common width (640/1280/1920/3840)
  is already a multiple of 128, so playback is unaffected; validating padded widths needs the
  modifier-aware path below. 1080p needs the coded 1088-row allocation (SPS dims drive h264 validation).
- No V4L2 modifier UAPI in 6.19: a tiled decoder must expose a private fourcc (e.g.
  V4L2_PIX_FMT_YUV420M_TEGRA_BL) plus a private INTEGER64 control carrying
  DRM_FORMAT_MOD_NVIDIA_16BX2_BLOCK(0); GStreamer 1.28 needs a small patch to map it to DMA_DRM
  caps. Tegra DRM scanout only accepts block-linear on RGB primaries, and GL import of block-linear
  YUV on GK20A is unproven — a detile/convert fallback may be needed for the player.
- Output ordering: driver emits decode order, one CAPTURE buffer per job; GStreamer reorders by POC.
  The duplicated frame near the start is still unexplained.
- Do not raise the H.264 profile control above MAIN until transform_8x8/scaling lists work.

## Next

0. ~~Weighted prediction~~ — hardware does not apply it (2026-10-24). Accept as a limitation; only
   fades/crossfades (x264 weightp, YouTube) are affected. Then **B-frame drift**
   (direct/co-located), output ordering, V4L2 format + modifier for the block-linear output, padded plane
   sizes, then a GStreamer/mpv playback path.
0b. B-frames (direct/co-located: MBE reg 8/9 buffer layout 0x40 B/MB per frame index, SXE 0x40 bits 22-23),
   weighted prediction values, CABAC (BSE-V 0x31800 block + context tables from fn_02e84/fn_013a0).
1. Layout: decode an all-intra random-noise clip, locate unique 16-byte runs of the avdec reference in
   the hardware output -> tile geometry (luma, chroma).
2. SMMU faults: find which buffer the TPE reads (aux/colocated buffers?), compare the microcode setup.
3. Detile (CPU, or a V4L2 tiled format + userspace) -> real playback.
4. CABAC: REA the microcode for use of the extra blocks.

Reboots: pmboot now sets PMC SCRATCH0 bit 30 and resets via SysRq (the normal shutdown path hung the
tablet for 3-10+ min three times); cmdline also has `watchdog.stop_on_reboot=0`.
