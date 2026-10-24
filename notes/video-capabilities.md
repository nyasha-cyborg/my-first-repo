# Video capability research — Nexus 9 / Tegra K1 (T132)

Last updated: 2026-10-25. Research done with subagents (REA of local vendor blobs + web sources);
full reports in /tmp/research-4k/ (tmpfs — copy anything worth keeping here).

## H.264 via the VDE

- 1080p is **bit-exact** through mainline tegra-vde (verified 60/60 frames; the earlier hang was an
  IRAM overrun above 7168 MBs, fixed in patch 0012).
- 4K: vendor advertises `OMX.Nvidia.h264.decode` max size **3840x2176** but a **blocks-per-second
  limit of 783360** = 240*136*24 → formally certifies **4K24**, not 4K30 (4K30 needs 979200 blocks/s,
  +25 %). K1 marketing claims 2160p30; whether 30 fps is reachable depends on VDE/AVP/EMC clocks.
  Owner accepted 4K24 as the target. Large-picture path (>2048 px) still to implement: BSE-V 0x28,
  MBE 0x3c, MCE 0x64, PPE 0x40 = 3, MBE size-command variant, SXE 0x10 bit 29; also lift the driver's
  1920-px cap and >127-MB checks and grow the 8192-MB metadata buffer.

## VP9

- **Not supported by the hardware, at all.** K1 has no VP9 (nor VP8) decoder; NVIDIA added VP9 in
  Tegra X1. No VP9 symbols/code in any nvmm/TVMR blob. Software only (libvpx) — far below realtime at
  4K on two CPU cores. YouTube 4K (VP9/AV1) on this tablet is not a hardware target.

## H.265 / HEVC

- K1 has **no fixed-function HEVC decoder**. Android 9's stack was a **CPU + GPU (CUDA) hybrid**
  (REA: `libnvmmlite_video.so` NvMMLiteOpen prints "H265 CPU+GPU DECODE" for chipid 6/T124, and ships
  five EM_CUDA SASS cubins for scaling/transform, intra, inter, SAO (luma/chroma), deblock
  (luma/chroma); `libnvcompute.so` is a dependency). CPU does parsing/CABAC/parameters; the GPU does
  all pixel reconstruction.
- Mainline cannot reproduce it: no CUDA (nouveau), the SASS cubins cannot be loaded without CUDA, and
  Mesa has no decode backend for nouveau (Clover removed; rusticl/NVK unbuilt/untested on GK20A).
  A GLES-compute reimplementation is possible in principle but projected at ~10–20 fps HEVC 1080p and
  ~1–3 fps at 4K, for 9–18 person-months. Not worthwhile.

## GPU compute on GK20A (for reference)

- Only GLES 3.2 compute is dependable (patched Mesa 26.1.6; Vulkan disabled; OpenCL unavailable).
  1 SM / 192 FP32, no VRAM (GART, shared ~12 GB/s), pinned at 612 MHz, GR init historically fragile.
- Useful role: **detiling + YUV→RGB of the VDE block-linear output** (shader, days–weeks), not video
  decoding.

Sources: AnandTech Tegra K1 review, Hot Chips K1 deck, GHEVC (TMM 2017), Mesa NVK/rusticl docs,
NVIDIA/Collabora GStreamer threads. Details in /tmp/research-4k/*.md.
