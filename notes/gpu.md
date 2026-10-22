# GPU (GK20A, Tegra K1) — nouveau

## 2026-10-23 11:25 — nouveau probes the GK20A on mainline

- Kernel tree already had it: `gpu@57000000` (`nvidia,gk20a`) enabled in the flounder DT with `vdd-supply = <&vdd_gpu>`,
  `CONFIG_DRM_NOUVEAU=m`, `CONFIG_NOUVEAU_PLATFORM_DRIVER=y`, `CONFIG_DRM_TEGRA=y`. Firmware = linux-firmware
  `nvidia/gk20a/{fecs,gpccs}_{inst,data}.bin`, `sw_{bundle_init,ctx,method_init,nonctx}.bin` (staged decompressed).
- Image `n9gpuA` (n9hsicI2 ramdisk, modules restaged + nouveau, gk20a firmware in /lib/firmware). `modprobe nouveau`:
  ```
  nouveau 57000000.gpu: NVIDIA GK20A (0ea000a1)
  nouveau 57000000.gpu: imem: using DMA API
  nouveau 57000000.gpu: drm: VRAM: 0 MiB / GART: 1048576 MiB
  [drm] Initialized nouveau 1.4.1 for 57000000.gpu on minor 1      -> /dev/dri/card1 + renderD129
  ```
  tegra-drm stays card0 (display), nouveau card1/renderD129 (render) = the split Mesa's `tegra` + `nouveau` gallium
  drivers expect (kmsro). No errors. GR firmware is only loaded on the first channel/context: the real test needs Mesa.
- Pmos wiki says "3D not working" for the archived port; nobody seems to have tried nouveau on this tree.
- Gotcha found: `linux-flounder-out` binaries were still the 01:48 build (`gcb8985407c88`) while `kernel.release` said
  `gcfc538ce0338` (three commits at 11:02 regenerated it without a rebuild) -> staged module dir name != `uname -r`.
  Probe worked via a symlink. Rebuild the kernel before packaging for pmOS.

## Next
- In pmOS: `mesa-dri-gallium` (tegra + nouveau), `kmscube`, `glmark2` (drm/wayland), then Phosh/Plasma Mobile
  compositing, then video (mpv + yt-dlp 720p, browser).
- Hardware video decode: check `tegra-vde` (H.264 only) for Tegra132; low priority.
