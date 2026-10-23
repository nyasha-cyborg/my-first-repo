# VDE (hardware H.264 decode) on Tegra132 — mainline tegra-vde bring-up

Goal: hardware H.264 decode for video/YouTube (CPU software decode: 720p 1.1x realtime, 480p 2.1x; see
notes/gpu.md). Tegra K1 VDE spec: H.264 up to High L5.1 (4K30). Mainline tegra-vde caps T124 at 1920x2032
and lists **no** T124 output formats ("TBD: T124 supports only a non-standard Tegra tiled format").
No mainline Tegra124/132 board has a VDE node.

## State (2026-10-24 02:00, kernel g0fa4171fc82c, linux-flounder WIP commits)

- DT (tegra132.dtsi): `sram@40000000` mmio-sram with `vde_pool` 4 KiB at +0x3f000; `vde@60030000`
  (compatible tegra132-vde, tegra124-vde), regs at **0x60030000** (see below), SPI 9/10/12, clocks
  VDE + BSEV, resets vde/mc/bsev (CAR 61, MC reset VDE, CAR 63), iommus SWGROUP_VDE.
- Driver: optional `bsev` clock + reset (enabled before the VDEC partition power-up, as the stock nvavp
  does: `nvavp_clks_enable` enables bsev + vde, then `nvavp_unpowergate_vde` = partition 4);
  T124 decoded fmt = YUV420M placeholder (bring-up).
- Probes: `/dev/video0`, iommu group 2, GPU unaffected. GStreamer 1.28 `v4l2slh264dec` negotiates.
- **Decodes and writes frames** (base.mp4, Baseline 720p: every byte non-zero), but:
  - output layout is not linear (MAD vs avdec_h264 74; 16x8 tile guess 24.5) — layout TBD;
  - SMMU faults during decode: `vdetper: read @0x114008c0 ... Page fault` (TPE reads unmapped IOVAs).
- CABAC (Main/High as served by YouTube) refused by the driver ("CABAC unsupported by hardware");
  CAVLC Main incl. B-frames accepted. T124 has extra blocks (see map) — maybe hardware CABAC.

## Evidence

- Old map (0x6001a000, T20-T114 layout) on T132: every register reads `0xcacad0d0` even with the VDEC
  partition on, clocks on, resets released; decode "succeeded" with all-zero output and
  `BSEV ICMDQUE flush timeout, INTR_STATUS cacad0d0` each frame.
- REA/vendor (pulled with root adb into /tmp/n9build/vendor-video): `nvavp_vid_ucode_alt.bin` (AVP video
  microcode, 41004 B) has >100 constants in 0x60030000-0x60033cff and none at 0x6001a000+ (the AVP OS
  blobs mention 0x6001a000 twice). Block map from the microcode:
  SXE 0x60030000, BSE-V 0x60031000 (+0x31800 sub-block), MBE 0x60032000, PPE 0x32200, MCE 0x32400,
  TFE 0x32600, VDMA 0x32a00, extra 0x32c00 / 0x32e00, frame-id 0x60033800, extra 0x33a00 / 0x33c00.
  = T20-T114 offsets moved from 0x6001a000 to 0x60030000.
- Stock nvavp clocks (strings via tegra_nvavp_probe): cop, vde, bsev, sclk, emc, bsea, vcp.
- Test clips (ffmpeg/libx264 on the tablet): base.mp4 (Baseline), mainp.mp4 (Main CABAC) fails after
  frame 1, maincavlc.mp4 / mainb.mp4 (Main CAVLC, B-frames) 59/60 frames accepted.

## 2026-10-24 03:15 — bit-exact Baseline/Main; output layout known; B / WP / CABAC open

Patches: `patches/candidates/vde/` (3 WIP commits in linux-flounder, last 5a4d2fdf5). Module parameter
`tegra_vde.t124_mask` gates each T124 change; good set so far = 2048+16384+32768 = **51200**.

- **Output layout (measured, bit-exact):** each plane (Y, Cb, Cr at the YUV420M plane offsets) is NVIDIA
  block-linear with a block height of 1 GOB: offset(x,y) = ((y/8)*(pitch/64) + x/64)*512 +
  ((x%64)/32)*256 + ((y%8)/2)*64 + ((x%32)/16)*32 + (y%2)*16 + x%16, pitch = plane width.
  = DRM_FORMAT_MOD_NVIDIA_16BX2_BLOCK(0) / BLOCK_LINEAR_2D(h=0) per plane. tools/vde-detile.py.
  Planes are padded to whole GOBs/MBs: 640x360 overflows its plane (driver sizes must be padded).
- REA of nvavp_vid_ucode_alt.bin (Thumb; wrapper ELF with seeded `push {..,lr}` function symbols:
  /tmp/n9build/rea-avp/vid_ucode_fn.elf): fn_03a50 codec init, fn_02e84 BSE-V setup (0x60031800 block:
  DMA buffer, 0x804-byte slots — probably CABAC context tables), fn_06b8c bitstream DMA ring
  (0x60032c34/c50), **fn_060c8 = H.264 per-frame setup** (frame-id tables, SXE 0x40/0x44/0x48 layouts,
  MBE 0xA regs 4/5 = 0x60 B/MB buffer, 8/9 = co-located buffer 0x40 B/MB/frame).
- Fixes found from fn_060c8:
  - frame-id luma entry bit 31 for progressive frames (the second plane set 0x380/0x400/0x480 is only for
    the other case) -> rows 12-15 of every MB were wrong and TPE faulted without it; now **100 %**.
  - SXE 0x40 bits 17-20 = picture structure on T124 (mainline puts !baseline at bit 17) -> Main I-frames.
  - SXE 0x48 bit 17 weighted_pred_flag, bits 18-19 weighted_bipred_idc -> WP streams parse.
- Results (hardware vs avdec_h264, frame by frame):
  Baseline 720p 90 frames 100 %; Main plain 100 %; Main POC type 0 100 %;
  Main B-frames 81-92 % (bipred/direct wrong); Main weighted P 86-91 %; CABAC: I-frame only.
- Dead ends: SXE 0x54/0x58/0x5c/0x70/0x74 T124 values (0x5c=0x3620 breaks P-frames, others no effect);
  PPE 0x00/0x08/0x0c values; MBE reg 4/5 buffer (no effect alone); "deblocking line buffer" theory
  (wrong rows matched neither the deblocked nor the undeblocked reference).
- Test hygiene: references must come from a complete avdec decode (identity eos-after=1 emits another
  frame); /tmp on the tablet is on the rootfs; 124 MB dumps fill it fast.

## 2026-10-24 04:30 — CABAC works; real YouTube streams still wrong on inter frames

- **CABAC bit-exact** (Main CABAC clip, 30/30 frames): BSE-V 0xA4 bit 0 = entropy_coding_mode_flag and
  SXE 0x48 bit 20 = the same flag (stock fn_060c8: BSE-V 0xa4 = transform_8x8<<3 | scaling<<2 |
  mono<<1 | entropy). My earlier guess SXE 0x44 bit 1 is wrong (it breaks decoding; likely
  redundant_pic_cnt_present). Good mask now **313344** (bits 11, 14, 15, 18).
- Feature matrix at 640x360 (x264): Main plain 100 %, POC type 0 100 %, CABAC 100 %, B-frames drift
  (frames 0-3 exact, then 97 % -> 81 % by frame 29, B-pyramid references), weighted P 86-91 %.
- **Real YouTube 720p (avc1.4D401F, Main L3.1, CABAC, weighted_pred 1, bipred idc 2, POC 0):** I-frames
  100 %, inter frames almost all wrong (exact ~3 %, MAD ~14). The opening fade (frames 2-6, weights)
  stays dark in hardware -> explicit weights are parsed but **not applied**. The alternative bit order
  for SXE 0x48 17-19 breaks parsing, so the parse flags are right; the weights need something else.
- Hardware output has one duplicated frame near the start (192 vs 191 frames): output ordering issue.
- Microcode leads not yet read: per-slice H.264 code (weights, ref lists) — fn_03568/fn_034a8/1ff0 are
  other codecs. fn_013a0: BSE-V 0x804-byte slots are bitstream scatter-gather lists (count + 256
  addr/len pairs), not CABAC tables.
- Meanwhile (software): /etc/mpv/mpv.conf in the overlay (tools/pmos/etc-mpv): <=480p H.264, vo=gpu,
  profile=fast, skiploopfilter=nonkey. Streaming 480p from YouTube still drops ~374 frames / 25 s
  (local 480p file: ~80) — network + audio + demux compete for the two cores.

- Dead end 04:45: SXE 0x5c = 0x3620 faults even with a 64 KiB secure_bo (SXE 0x7c), so 0x54-0x74 are
  not offsets into that buffer. Hypothesis for weights: on T124 the AVP/host side programs per-slice
  data (the microcode writes 20 MBE ref-list entries from a host table, +0x1c); weights may need the
  V4L2 slice-based API (V4L2_CID_STATELESS_H264_PRED_WEIGHTS) instead of frame-based decoding.

## 2026-10-24 11:00 — T124 local-memory layout; codec init; WP still not applied

- REA: BSE-V command queue = local-memory DMA engine, word addressed. `fn_00830` zero = 2 words on T124
  (0x84000000|len<<12|addr&0xfff, addr&0x3fff); `fn_00868` copy 0x80000000|len, dst<<16|src>>2.
  T124 layout: slice-group bitmap ends at 0x1000, 0x1020 (BSE-V 0x98/0x9c, 0x60032e00), SXE scratch
  0x1820 (0x400 words), MCE 0x1c20, ref lists 0x3620 (0x100 words; SXE 0x74 = 0x3720), scaling lists
  0x38b4. Mainline T20: 0x150 / 0x54c (0xf0) / MCE 0x63c / lists 0xe34.
  -> mask bit 20 = T124 layout: same pixels, the 4 per-run decode errors disappear. Keep it (1361920).
- `fn_04828` (H.264 slice/ref lists): 4 tables (P list by PicNum, B L0, B L1, DPB order) of
  [idx<<26 | flags | POC(18 bits) or 0x40000+LongTermPicNum, co-located addr]. POC instead of frame_num
  (bit 21) makes decoding worse -> dead end on this path.
- H.264 = codec id 5 in `fn_03a50` (SXE 0x08=0x35, MBE 0x84=0x400, VDMA 0x00=0x4000, VDMA 0x1c=1):
  bits 25-27 give byte-identical output. Dead end.
- WP evidence: YouTube fade -> every HW frame from 3 on equals frame 2 (weights and offsets ignored).
  m_wp errors are small (+-1..3), so x264's weights there are near identity.
- Tools: tools/vde-test.sh MASK clip[:frames] + tools/vde-score.py (per-plane scores).

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

Remaining error starts late and tracks `ref_pic_list_modification` (m_b: 9 slices with mod_l0;
bpyrnormal: 25; no l1 mods). The driver cannot see modified lists: GStreamer's `v4l2slh264dec`
does supply `V4L2_CID_STATELESS_H264_SLICE_PARAMS` (control now registered; mask2 bit 5 logs it) but
the struct is all-zero in frame-based mode, so `ref_pic_list0/1` and per-slice counts are unavailable.
Next option is a kernel-side slice-header parser for ref list modification, or userspace that
populates the control properly.

Dead ends this cycle (all zero effect): MBE list1 `0xC4000000` group commands (t124_mask2 bit 0,
implemented and verified to run); MBE A reg 2/3 colocated aux (t124 bit 22) alone or with the fix;
MBE per-MB buffer (bit 10); unwrapped ref `frame_num` (mask2 bit 3 — hardware masks correctly).
t124_mask2 now: bit0 list1 cmds (dead), bit1 frame log, bit2 force in-use (default on T124), bit3 raw
frame_num (dead), bit5 slice-params log.

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
