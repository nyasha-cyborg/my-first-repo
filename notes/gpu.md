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

## 2026-10-23 21:45-22:10 — H1 (devfreq race) refuted; REA GR reset; early hang = kernel oops (bad pointer)

- 21:45 boot with the 612 MHz pin from udev: GR failed anyway (`PRIVRING` at 0x137000 + 0x503018, FECS timeout),
  devfreq showed 1 transition (the pin). **H1 refuted.** `NvGrResetWar=1` (50 ms GR reset) on reload: still fails.
- Bad vs good boot: privring enum (0x120074/78 = 1 FBP, 1 GPC), PMC enable, vdd-gpu 910 mV, clocks: same.
  Palmas SMPS registers live on 4-0058 (driver page = base>>8 - 1): SMPS45 CTRL 0x11, VOLTAGE 0x2f (0.91 V),
  FORCE 0xc2 on a good boot. The `4-0059: Failed to read IRQ status: -121` bursts are the interrupt page and happen
  on good boots too (bad: at 1.06 s + `avdd-dsi-csi: failed to disable: -EREMOTEIO`; good: at 13.5 s).
- REA (stock kernel, window ELF `/tmp/n9build/rea/nvgpu.elf` 0xffffffc00046c000-0x492000, 563 symbols):
  - `gk20a_reset_priv_ring` = mainline `gk20a_privring_init` (0x137250 &= ~0x3f, PMC 0x20 reset, 0x12004c = 4,
    0x122204 = 2). Not the difference.
  - `gk20a_init_gr_prepare`: clear 0x400500 bit 0, `gk20a_reset(0x18001000)` (PGRAPH + bits 27/28, 20 us each
    side), 0x400500 = 0x10001. Mainline's gk104 MC reset map has **no GR entry**: GR is never reset at init.
  - `gk20a_init_gr_reset_enable_hw`: 0x400100/0x40013c = ~0; FE_PWR_MODE 0x404170 = 0x12 (wait bit 4), FECS
    ctxsw reset 0x409614 = 0x70, 20 us, 0x770, 20 us; 0x404170 = 0x10; then SCC RAM, sw_nonctx, scrub, ucode.
    Mainline does the 0x404170/0x409614 dance only in grctx generation, after ctxctl init.
  - Candidate kernel change (uncommitted in linux-flounder: `gk20a_gr_reset_hw()` in gr/gk20a.c, chipset 0xea
    only); module built as /tmp/nouveau-grreset-s.ko; `tools/pmos/gr-hunt.sh` loads it on a failing boot. Untested.
- **Early hang caught** (kmsg.log.1 of the 22:00 boot): at 20.7 s `Unable to handle kernel paging request at
  ff80002000006fdf` (between user and kernel ranges, looks bit-flipped), `__set_fixmap <- aarch64_insn_write <-
  jump_label_update <- nf_register_net_hook` (nft). The task died holding the text-patching lock with irqs off ->
  everything that patches code later deadlocks -> no SSH/serial a minute later, watchdog (or not) after.
- H3 (testing): random memory corruption explains GR failures, oopses and the bright flashes at once. Suspect:
  EMC DVFS (tegra30-devfreq actmon: 1684 transitions in one session, 202 in a few minutes) with the mainline
  Tegra132 EMC switch + our DT timing tables. Test image `n9pmos-boot-noemcdvfs.img` = same kernel +
  `initcall_blacklist=tegra_devfreq_driver_init` (EMC stays at the bootloader rate); `gpu-boot-test.sh` x8.
- EMC tables vs stock DT (`/tmp/n9build/emccmp/cmp.py`, android-0.dts, both ram codes, all 13 rates 12.75-924
  MHz): the 143 mainline burst registers equal the vendor's 165-entry `emc-registers` once aligned (mainline
  carries XM2DQSPADCTRL2, ZCAL_INTERVAL, MRS_WAIT_CNT as named properties; vendor entries 146-164 are MC regs).
  Named cfg/cal values equal too. **The timing data is not the difference**; if H3 holds, look at the mainline
  tegra124-emc switch sequence (vs vendor tegra12_emc, REA) or keep EMC fixed.

## 2026-10-23 22:55 — H3 confirmed: EMC DVFS corrupts memory; DRAM fixed at 924 MHz = 8/8 clean boots

- `gpu-boot-test.sh` with `initcall_blacklist=tegra_devfreq_driver_init` (EMC stays at the bootloader's 924 MHz,
  actmon absent), 8 boots 22:20-22:53, each checked ~190 s after boot (the old hangs hit at 1-2 min):
  **8/8 gr=ok, oops=0, phoc up**, gpu 612 MHz, smps45 identical every boot (11 02 c2 2f). Before, about half the
  boots had a GR init failure or an oops/early hang. PMIC `-121` bursts (33-92) on every boot, harmless here.
- Now the default: build.sh puts the blacklist on the pmOS cmdline. Cost: DRAM never drops below 924 MHz
  (more idle power); gain: GPU/display bandwidth no longer drops to 102-204 MHz (was likely part of "slow").
- Stock EMC tables = ours (above), so the bug is in the mainline Tegra132 EMC switch path (tegra124-emc
  driver used for T132, or the T132 CAR emc clock). Proper fix later: REA vendor tegra12_emc_set_rate/
  emc_set_clock vs mainline tegra124-emc, then re-enable scaling.
- The REA GR-reset change (`patches/candidates/gk20a-gr-vendor-reset.patch`, stashed in linux-flounder) was
  never needed for this; GR failures were memory corruption. Kept as an untested candidate only.
- WiFi aside: once (22:15) the router stopped forwarding PC<->tablet traffic while both reached the gateway;
  the tablet itself was fine (serial). Test scripts fall back to the serial console.
- Lock screen at boot under autologin: phosh locks at startup unless `GDMSESSION` is set (libphosh
  "started by display manager" check); greetd initial_session now runs `env GDMSESSION=phosh phosh-session`.

## 2026-10-24 00:00-01:10 — video: CPU decode limit; nouveau cache-clean bottleneck fixed; flicker; backlight curve

- yt-dlp 2026.10.21 works (JS challenges via deno). YouTube H.264 (avc1) tops out at 720p for the test video;
  4K is VP9/AV1 only. mpv 0.41 software decode, both Denver cores at 2.295 GHz, `--vo=null --untimed`:
  **720p H.264 1.1x realtime, 480p 2.1x** -> 720p is a slideshow on CPU (258 drops in 13 s).
- 480p still dropped ~430/600 frames: mpv's `vo` thread ~75 % in the kernel. /proc/<tid>/stack sampling:
  `dcache_clean_poc <- __dma_sync_single_for_device <- nouveau_bo_sync_for_device <- nouveau_bo_validate`
  (53/200): on Tegra (no AGP) GART BOs are ttm_cached and the whole BO is cleaned on every pushbuf.
  **Fix (series 0040):** write-combined GART BOs on non-PCI devices; one clean per set of pages, none after;
  no sync_for_cpu. 480p: **430 -> 74-82 drops / 25 s**; vo kernel time ~75 % -> ~40 %. Next cost:
  `nouveau_gem_object_close` (Mesa allocating/freeing BOs per frame). Series 0042: `nouveau.tegra_wc=0` A/B.
- Flicker: "flickering blocks" while video plays. With tegra_wc=0 the user still saw slight flicker (and 491
  drops), so WC is not the cause; likely a sync race (compositor sampling mpv's buffer before the GPU is done,
  or Mesa buffer reuse) that the slower path hid. The kernel already wmb()s before the GPFIFO kick
  (nvif/chan506f.c). Open.
- Backlight "not steady" on the home screen: user level was 9/255 (~3.5 % duty). CABC is off (0x55 = 0),
  0x53 = 0x24, same as stock. REA `dsi_j_qxga_8_9_bl_notify`: stock maps 0 -> 0, 1..10 -> 7, 11..133 ->
  7..90, 134..255 -> 90..255. Series 0043 uses the same curve. Low-level flicker = panel PWM at low duty.
- PMIC: cold boot (user power-on) stalled 75 s: Palmas IRQ 73 stormed with `4-0059 ... -121` until "nobody
  cared" disabled it at 87 s; DFLL/cpufreq and the regulators waited behind it; that boot also had a GR
  failure. Warm boots: one 11 ms NAK burst ~0.3 s after `cpufreq_policy_online` (DFLL takes over vdd-cpu over
  the shared PWR_I2C). REA `tegra_i2c_probe/xfer`: stock enables `cl_dvfs_ref` + `cl_dvfs_soc` around every
  transfer when `nvidia,require-cldvfs-clock` is set (stock DT has it). Series 0041 does the same in mainline
  i2c-tegra + flounder DT: bursts remain (84, 45 on two boots) -> not sufficient; DFLL handover still open.

## 2026-10-25 13:30-14:10 — 3D "gr: failed to construct context -110": vendor GR reset fixes it so far (2 boots)

- Symptom (handoff item 1): kmscube on NVIDIA failed; dmesg `gr: wait for idle timeout (en: 1, ctxsw: 0, busy: 1)`,
  `gr: init failed, -11/-110`, then `failed to construct context`. EMC blacklist and 612 MHz pin were already in place,
  so this is not the EMC-corruption failure; PGRAPH was simply busy at first use. Reloading nouveau live does not
  recover it and `rmmod nouveau` oopses in `gk20a_devfreq_get_dev_status` (needs a reboot).
- Change: applied the stashed REA candidate (vendor `gk20a_init_gr_prepare` / `reset_enable_hw` order, GK20A only)
  = `patches/candidates/gk20a-gr-vendor-reset.patch`, built as module for release `...g0fa4171fc82c`, installed
  into the rootfs (`nouveau.ko.zst`; original saved as /root/nouveau.ko.zst.orig on the tablet).
- Result: 2 of 2 fresh boots: `kmscube -D /dev/dri/card0 -c 600` rc=0, renderer "tegra", 0 `gr:` errors
  (stop greetd first, else "failed to set mode: Permission denied" = phoc owns DRM master).
  Old failure rate was ~half of boots, so 2/2 is encouraging, not proof. More boots needed.
- Tool: `tools/pmos/gr-cycle-test.sh N [ip]` (reboot + kmscube per boot). It uses pmboot.sh, which reboots the
  tablet itself; do not power-cycle by hand while it runs, and do not `pkill -f` it from the same shell.
- Next: more boots without errors -> commit the kernel patch properly, drop the 3 software-GL variables from
  /etc/environment, restart greetd (phoc should say "Creating GLES2 renderer ... NVIDIA").
- 14:15 desktop switched to the GPU: removed GBM_ALWAYS_SOFTWARE / LIBGL_ALWAYS_SOFTWARE / WLR_RENDERER from
  /etc/environment (backup /root/environment.software.bak on the tablet), restarted greetd. phoc now holds
  /dev/dri/renderD129 (nouveau) open and has no software variables; no `gr:` errors in dmesg. Not yet confirmed
  by the "Creating GLES2 renderer ... NVIDIA" log line or a visual smoothness check; survive-reboot check pending.
- 14:25 owner: PIN lock screen still shown during boot login. Cause: `sm.puri.phosh.lockscreen require-unlock` default
  true. Fix: schema override `/usr/share/glib-2.0/schemas/99_n9-nolock.gschema.override` (copy in tools/pmos/,
  run `glib-compile-schemas`); effective on the next boot/phosh start. Not yet verified on a boot.
