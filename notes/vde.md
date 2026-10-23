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

## Next

1. Layout: decode an all-intra random-noise clip, locate unique 16-byte runs of the avdec reference in
   the hardware output -> tile geometry (luma, chroma).
2. SMMU faults: find which buffer the TPE reads (aux/colocated buffers?), compare the microcode setup.
3. Detile (CPU, or a V4L2 tiled format + userspace) -> real playback.
4. CABAC: REA the microcode for use of the extra blocks.

Reboots: pmboot now sets PMC SCRATCH0 bit 30 and resets via SysRq (the normal shutdown path hung the
tablet for 3-10+ min three times); cmdline also has `watchdog.stop_on_reboot=0`.
