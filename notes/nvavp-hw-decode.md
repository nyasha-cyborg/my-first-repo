# nvavp / hardware video decode (LineageOS 16, kernel 3.10.108-secC)

## Plain summary

Video decode in hardware never worked because the kernel driver for the video
co-processor (nvavp) failed to start. It failed because of a name: the device
came up as `60001000.nvavp`, but both the clock table and the memory-mapping
(SMMU) table only recognise the name `nvavp`. So it found no clocks and got no
mapped memory. The fix gives the device the expected name. Without the driver,
`/dev/tegra_avpchannel` doesn't exist, so the NVIDIA OMX plugin registers 0 codecs.

Built, NOT yet tested on the tablet: `~/n9kernel/out/boot-secC-nvavp.img`
(sha256 `72dbb4ae...80f9bc`, kernel `3.10.108-gb9078499b80`, ramdisk and cmdline
the same as secC).

## Root cause

- The DT node `nvavp` (`reg = <0x60001000 0xe200>`, from `arch/arm/boot/dts/tegra124-soc.dtsi`)
  is in all four appended flounder DTBs and also in the stock N4F27P DTBs.
  `flounder_auxdata_lookup` had no entry for it, so it got the default name `60001000.nvavp`.
  (ardbeg and loki do have `OF_DEV_AUXDATA(..., 0x60001000, "nvavp", NULL)`.)
- Clocks: `tegra12_clocks.c` only has lookups for dev_id `tegra-avp` and `nvavp`
  (`CLK_DUPLICATE("vde.cbus","nvavp","vde")` etc.), so `clk_get(dev,"vde")` returned an error and the probe exited with -ENOENT.
- IOVA: with `CONFIG_TEGRA_AVP_KERNEL_ON_SMMU=y`, the probe calls `dma_alloc_at_coherent()` at fixed
  IOVA 0x8ff00000 and then 0x0ff00000. That only works on an SMMU-attached device. The SMMU bus
  notifier (`drivers/iommu/tegra-smmu.c`) finds swgids through `tegra_smmu_fixup_swgids()`
  (`arch/arm/mach-tegra/devices.c`), which matches `strncmp(table name, dev_name)`. The table
  has `"nvavp"` → AVPC|A9AVP, and that does not match `60001000.nvavp`. As a result the
  device had no SMMU and fell back to plain arm64 DMA ops. That fallback produced the warning
  "coherent DMA mask 0xffffffff is smaller than system GFP_DMA mask", the allocation failed,
  and the log showed "allocated IOVA at ffffffffffffffff". The driver also kept going after this error.
- The static legacy `nvavp_device` (name `nvavp`, hard-coded IRQ) was also registered by
  `flounder_panel_init()`. Whether it probed on the tablet is unknown (no captured log). In any case it
  did not produce a working `/dev/tegra_avpchannel` on this build.
- No upstream fix was found. All linckandrea/android_kernel_htc_flounder branches (3.10.108,
  lineage-16.0/17.1, DiverOS-patches, r-*-p/t, android-tegra-3.10, ...) have the same
  board files and no nvavp auxdata. The L4T and shieldtablet trees were not checked: ardbeg/loki in
  this tree already show NVIDIA's pattern (auxdata naming).

## Fix (branch `n9-3.10.108-sec-nvavp` in ~/n9kernel/kernel, on top of secC `bb3052c7115`)

1. `5ebcc85f7b2` ARM: tegra: flounder: name the DT nvavp device "nvavp". This adds the auxdata entry
   in `board-flounder.c` and drops the static `nvavp_device` registration in `board-flounder-panel.c`.
   It fixes the clock lookup and also the SMMU attach.
2. `b9078499b80` media: tegra: nvavp: the probe now fails cleanly when the AVP OS IOVA allocation fails
   (goto error, free a buffer that landed at the wrong address, free the OS buffer on later errors).

Built with GCC 4.9 (`build-108`, log `~/n9kernel/out/build-108-secC-nvavp.log`, no new warnings).
Repacked: secC header, cmdline and ramdisk with the new Image.gz-dtb. Checked with `bootimg-split.py`.

## What to check on the tablet

- `dmesg | grep -i -e nvavp -e avp`: we expect `nvavp nvavp: allocated IOVA at 8ff00000 for AVP os`
  (or 0ff00000), with no "cannot get ... clock" and no `60001000.nvavp`. Optionally check
  `grep nvavp /sys/kernel/debug/*smmu*/*` for the SMMU attach.
- `ls -l /dev/tegra_avpchannel /dev/tegra_audio_avpchannel`: both should exist (mode 0777 from the driver).
- `logcat | grep -i -e OMXMaster -e "OMX plugin" -e Nvidia`: we expect a non-zero component count
  in place of `0x80001001 after registering 0 components`.
- Play an H.264 file: `logcat | grep OMX.Nvidia.h264.decode`, or `dumpsys media.player`
  / `dumpsys media.codec`, should show `OMX.Nvidia.h264.decode`.
- If it still fails: check whether `nvavp_os*.bin` / `nvavp_vid_ucode*.bin` load (request_firmware
  errors), and check the IRQ (DT SPI 4 = mailbox).

## Dead ends / open

- No upstream fix exists in any linckandrea branch (checked 2026-10-26).
- Not tested on hardware yet.
