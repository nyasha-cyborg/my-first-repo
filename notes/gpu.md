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

## 2026-10-23 14:20 — "glitchy" + hang: GK20A DVFS PLL slide timeout (REA: vendor slide identical)

- User: Phosh on the GPU is glitchy. Then the tablet died (watchdog reset). Last kernel lines (live kmsg stream):
  `WARNING ... pc : gk20a_pllg_slide+0x184 [nouveau]` x0 = -110, `<- gk20a_clk_prog <- nvkm_pstate_work`:
  the GPC PLL dynamic ramp to a new NDIV did not report DYNRAMP_DONE within 500 us.
- Why it reclocks: `gk20a_pmu_init` arms a 100 ms load-driven DVFS alarm (`nvkm_clk_astate`); on GK20A the clk
  `func->init` path returns before the generic `pstate = -1` reset, so the loop really programs states (there is no
  stock knob to stop it).
- REA (stock Android kernel, `tools/kallsyms-fix.py` rebuilt the hidden kallsyms: 71795/71795; window ELF via
  image2elf): vendor `clk_slide_gpc_pll` = same sequence as mainline (STEPA 0x2b / STEPB 0x0b — vendor writes them
  on every slide, mainline once at init — slowdown bit 22, NDIV, DYNRAMP bit 31, poll 0x1328a0 bit 24 for 500 x
  1 us, -110 on timeout). Vendor `gpu_cvb_dvfs_table` (Tegra132) = mainline `gk20a_cvb_coef` for 72..852 MHz
  (vendor adds 900..1008), header max 1200 mV, speedo scale 100, voltage scale 1000. Vendor DT `smps457` (vdd-gpu):
  0.7-1.4 V, init 1.0 V, boot-on, no ramp delay — same as ours. So neither the slide code nor the voltages differ;
  the difference is how often mainline reclocks (every 100 ms, PLL slide + Palmas I2C voltage change).
- Fix: kernel option `NvGk20aDvfs=0` (linux-flounder 36a7c2ac9, series 0034) + `NvClkMode=8` (pstate id = index+1;
  8 = 540 MHz) on the pmOS cmdline: one slide at init, none afterwards.
- Open: whether STEPA/STEPB must be rewritten before every slide after GPU rail-gating (vendor does it), which
  would allow DVFS again; higher pinned clocks.

## 2026-10-23 19:30 — random GR init failure; the real reclocker is devfreq, not the PMU

- Symptom (kernel g178dd2c295d4, one boot in three seen): no Phosh, greetd crashed. dmesg:
  `bus: MMIO read of 00000000 FAULT at 137000 [ PRIVRING ]` then `timeout`, `WARNING gf100.c:967
  gf100_gr_init_ctxctl` (`gr: init failed, -110`) on phoc's first GR use. FECS starts (0x409800 bit 0) but never
  answers method 0x10 (discover image size). Stuck for the whole boot: rmmod/modprobe nouveau, 540 MHz cap and
  clearing the soctherm heavy GPU throttle (0x700e2468 -> 0x40000000 via /dev/mem) all still fail.
- Not the series-0039 GPU throttle level: the next boot of the same image started GR fine (status In, no breach).
- Found on the way: **`NvGk20aPstate` / fixed astate never held.** Mainline has `gk20a_devfreq` (simple_ondemand,
  50 ms polling, the only governor built): its target sets `ustate_ac/dc`, which override `astate`. debugfs pstate
  showed 852 MHz (failed boot, 1 transition) and 40 transitions in 3 min on a good boot. `NvGk20aDvfs=0` only stops
  the PMU's own alarm. Every devfreq transition = a GPC PLL slide (the step that timed out and hung the SoC; series
  0038 falls back to a full reprogram). 0x137000 = GPCPLL_CFG, read by devfreq `get_cur_freq` every poll.
- Hypothesis (H1, testing): a devfreq reclock racing GR/FECS init leaves FECS hung; reclocks may also be the
  "bright flashes".
- Change: udev rule `tools/pmos/60-n9-gpufreq.rules` pins min = max = 612 MHz when the devfreq device appears
  (before greetd): verified live, 0 transitions. `NvGk20aPstate=7` dropped from the cmdline (no effect).
- Separate: two early resets after `fastboot boot`; boot-init.log.1 shows rootfs mounted only at 32 s (userdata at
  24 s) on one of them, inside `tegra_wdt.heartbeat=60` that nothing pets before OpenRC's boot runlevel. Cmdline now
  `heartbeat=180` (busybox watchdog sets 60 s once it starts).
- 19:25-19:41 `tools/pmos/gpu-boot-test.sh 4` (rule + heartbeat=180): cycles 1-2 GR ok, 0 PRIVRING, 612 MHz,
  1 transition (the pin), greetd started (the `pgrep -x phoc` check said down: unverified, check the process
  name). Cycles 3-4: pmOS answered SSH, then went silent within 90 s (no ping, serial gadget enumerated but
  mute) -> watchdog reset to Android at 19:44. Next pmOS boot: SSH up for a moment, then gone; from ~19:50 the
  tablet is absent from USB entirely (no adb/fastboot/gadget) -> power cycle needed (or battery empty).
  Early hangs now 4 of the last 8 pmOS boots; their kmsg logs were lost to rotation. Next: stream `dmesg -w`
  from the first SSH second (the 20:03 attempt found no tablet), and keep kmsg.log.2+ (rotation keeps only 1).
