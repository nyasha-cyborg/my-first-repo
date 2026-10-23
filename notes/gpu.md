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

## 2026-10-23 14:00 — GPU works in pmOS with a patched Mesa (two tegra wrapper bugs)

- Stock Mesa 26.1.6 (Alpine v3.24) `tegra` renderer: kmscube and phoc segfault. Backtraces (gdb + mesa-dbg):
  1. `nvc0_validate_fb () nvc0_state_validate.c:177 <- nvc0_clear <- st_Clear` — the tegra wrapper forwards
     `set_framebuffer_state` unchanged since surfaces became embedded (`fb->cbufs[i].texture` is a tegra_resource),
     and `clear_render_target`/`clear_depth_stencil` cast caller-owned surfaces to tegra_surface.
  2. phoc (robust context): `0x0 <- st_install_device_reset_callback` — the wrapper advertises every hook; nouveau
     has no `set_device_reset_callback`.
  Same code on Mesa main. Fix: `patches/mesa/0001-gallium-tegra-fix-wrapper-for-mesa-26.patch` (unwrap; drop
  forwarding hooks the GPU driver lacks; 103 hooks guarded). Upstream candidate.
- Build: `tools/pmos/mesa/build-mesa.sh` — rootless aarch64 sysroot (x86_64 apk.static in `unshare -r`, `--no-scripts`),
  Mesa tarball sha512 = Alpine's, clang cross, `-Dgallium-drivers=tegra,nouveau,softpipe -Dllvm=disabled`, Wayland
  only, prefix `/opt/mesa-n9` (system Mesa untouched; `LD_LIBRARY_PATH=/opt/mesa-n9/lib` in /etc/environment).
  Gotcha: Mesa requires build wayland-scanner == target libwayland (1.25 vs host 1.26): wrapper + build-machine .pc.
- Results: kmscube on the GK20A **~29.7 fps at 1536x2048** (llvmpipe ~5 fps), user: "crisp and smooth".
  phoc: `Creating GLES2 renderer, OpenGL ES 3.2 Mesa 26.1.6, GL vendor: NVIDIA`; greetd + phrog start on the GPU.
- Not built: desktop GL `libGL.so` (glx disabled; apps needing desktop GL fall back to the system libGL), llvmpipe.
- Next: Phosh session on the GPU (user login), Firefox/WebRender + mpv video tests.
