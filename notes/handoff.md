# Handoff — Nexus 9 (flounder, Tegra K1 T132) postmarketOS port

Written for an AI agent or person taking over. Read this first, then the topic note for the area you
work on. Kept current by the previous agent at each test cycle (last update: 2026-10-24 ~11:00).

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
  1. **Explicit weighted prediction is not applied.** On the YouTube fade every hardware frame equals
     frame 2. `m_wp` is 91 %, with small ±1-3 errors.
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

## NEXT TASK — step by step (start here)

### Test A: per-slice SXE registers from `fn_04828` (weighted-prediction lead)

The stock slice code writes four SXE registers that mainline never writes. They are the strongest
remaining lead for "weights parsed but not applied". Decompiled values (frame pictures, no MBAFF):

| reg | stock value |
|-----|-------------|
| SXE 0x60 | `(slicecnt & 0x3f) << 16 | num_ref_idx_l0_active_minus1 << 22 | num_ref_idx_l1_active_minus1 << 27` (`slicecnt` = microcode field param_2[0x39], unknown; try 0) |
| SXE 0x64 | `0x10000` (bit 19 = field pic, bit 20 = param_2[9], bit 21 = param_2[2]; all 0 for progressive) |
| SXE 0xdc | `0x4407500` (constant) |
| SXE 0x50 | `0` |

1. In `drivers/media/platform/nvidia/tegra-vde/h264.c`, `tegra_vde_setup_hw_context()`, right after
   the `tegra_vde_writel(vde, value, vde->sxe, 0x4C);` line, add:
   ```c
   if (vde->soc->t124_layout && (t124_mask & BIT(28))) {
   	/* stock fn_04828: per-slice SXE setup */
   	tegra_vde_writel(vde, ctx->num_ref_idx_l0_active_minus1 << 22 |
   			 ctx->num_ref_idx_l1_active_minus1 << 27, vde->sxe, 0x60);
   	tegra_vde_writel(vde, 0x00010000, vde->sxe, 0x64);
   	tegra_vde_writel(vde, 0x04407500, vde->sxe, 0xDC);
   	tegra_vde_writel(vde, 0x00000000, vde->sxe, 0x50);
   }
   ```
   Also try each register alone (split into bits 28/29/30 if the combined test changes anything).
2. Rebuild the module, strip it and copy it to the tablet (commands above).
3. Run (base mask 1361920 + bit 28 = 1361920 + 268435456 = **269797376**):
   ```
   tools/vde-test.sh 1361920   m_wp m_b v720:12
   tools/vde-test.sh 269797376 m_wp m_b v720:12
   ```
4. Success criterion: `v720_12` luma score rises from 23 % (frames 3-12 at 0 %). Watch `faults=` /
   `errs=` too: a hang or MBE timeout means the value is wrong. If the tablet stops answering, wait up to
   5 min (watchdog), then `tools/pmos/pmboot.sh <vdetest img>`.

### Test B: B-frame bits 22 / 23 (not yet run)

```
tools/vde-test.sh $((1361920 + (1<<22)))            m_b
tools/vde-test.sh $((1361920 + (1<<23)))            m_b
tools/vde-test.sh $((1361920 + (1<<22) + (1<<23))) m_b
```
Baseline `m_b`: Y 91.81 % (min 81.34), first imperfect frame 4. Bit 22 = MBE reg 2/3 = co-located
buffer of RefPicList1[0]; bit 23 = MBE final command `0xfc000011` (stock value for non-High streams).

### If Test A gives nothing (in order)

1. REA: find where the parsed weights land. Local memory: MCE base 0x1c20 (`MCE 0x10 = 0x1c201c20`).
   Search the microcode for reads of BSE-V/MCE registers after slice decode, or writes to 0x60032400-
   0x600324ff in `fn_04828` / `fn_01ff0` / `fn_01754`.
2. Check whether `libnvmm` (host side, in `/tmp/n9build/vendor-video/lib*`) parses pred_weight_table and
   sends weights to the AVP: REA it for "weight"/"luma_log2" strings or a loop over 32 refs x (w, o).
   If the host supplies weights, tegra-vde must use the V4L2 `PRED_WEIGHTS` control and copy the
   weights into local memory with a BSE-V copy command (see `tegra_vde_t124_bsev_lists()`).
3. After every cycle: update this file and notes/vde.md (hypothesis, result, dead ends), export the
   kernel diff to `patches/candidates/vde/`, commit and push the nexus9 repo.

## Other open items (see notes/gpu.md)

- Flickering blocks during video (a sync race, not caused by the WC change); backlight unsteady at low
  levels; PMIC -121 NAK bursts at DFLL takeover; LTE in pmOS; Bluetooth.
- Software playback config: `tools/pmos/etc-mpv/mpv.conf` (480p H.264, vo=gpu).
