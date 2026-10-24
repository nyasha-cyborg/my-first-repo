# Nexus 9 pmOS — could the vertical lines be a GPU/compositor fault? (host-only analysis)

Date: 2026-10-24. No tablet access, no repo writes.
Sources read: `notes/gpu.md`, `notes/pmos.md`, `notes/display-progress.md` (incl. the
2026-10-25 "vertical lines" section), `notes/panel.md`, `notes/stability-debug.md`,
all project patches (`patches/linux-flounder-series/0034-0043`, candidates,
`patches/mesa/0001`), `tools/pmos/*`, and the kernel tree
`/home/nyasha/code/linux-flounder` (6.19.0, `flounder-clean`).

---

## 1. Short verdict

**Yes, a GPU/compositor fault can produce static, whole-panel vertical lines —
but the current evidence cannot yet exclude a mainline-DSI/DC fault.** The most
likely GPU-side mechanism is *corrupted or wrongly laid-out framebuffer content*
(bytes/stride/tiling), not random GR noise: a regular vertical stripe pattern is
the classic fingerprint of a pitch/tiling/stride mismatch, and once the bad frame
is presented it stays static until the next redraw. Pure GR/FECS failures and EMC
bit-flips normally give missing rendering, blocks, sparkle, or oopses, not a
regular static stripe pattern.

Against DSI timing: the bootloader screen, the simplefb diag image, the kernel
fbcon on tegradrmfb and llvmpipe `kmscube` on card0 were all clean, and the DSI
register dump matches hboot (`notes/display-progress.md` 2026-10-18). DSI timing
faults usually roll/tear/flicker or shift the image, and would corrupt fbcon too.

But every genuinely clean comparison except fbcon/kmscube **bypasses mainline's
DSI reconfiguration** (simplefb keeps hboot's DSI state). The clean fbcon/kmscube
data points are older than the artifact and older than the write-combine change.
So the discriminating experiments below are still required; the leading
hypothesis on today's evidence is **GPU/compositor content corruption**, with
the newest memory-attribute change (series 0040, write-combined GART BOs) as the
highest-value single suspect, and the tiled/modifier path as a latent second.

---

## 2. Display pipeline as actually wired

- **Render:** Mesa 26.1.6 patched `tegra` wrapper (`patches/mesa/0001-...`),
  kmsro split: render device = nouveau on GK20A (`card1` / `renderD129`), display
  device = tegra-drm (`card0`). See `notes/gpu.md` 2026-10-23 14:00.
- **Scan-out:** tegra-dc reads the same GEM BO via the SMMU; DSI-A/DSI-B ganged,
  8 lanes, video mode, 1536x2048@60 (247.6 MHz pclk), JDI LPM089A128A panel
  (`notes/panel.md`, `arch/arm64/boot/dts/nvidia/tegra132-flounder.dts`).
- Both GK20A and DC are behind the SMMU (`iommus` in `tegra132.dtsi`; series 0036).
- fbdev is emulated on tegra-drm (`CONFIG_DRM_FBDEV_EMULATION=y`,
  `drivers/gpu/drm/tegra/fbdev.c`); nouveau's fbdev ops exist but card1 has no
  connectors, so the panel is never scanned out by nouveau.
- Consequence: a GPU fault is visible only as *wrong pixels in the BO the DC
  scans*; a DC/DSI fault is visible regardless of who wrote the BO. That is the
  axis every test below tries to separate.

---

## 3. Installed config inventory (installed pmOS)

Kernel: 6.19.0-htc-flounder (tree `/home/nyasha/code/linux-flounder`,
`flounder-clean`, HEAD e0e62c40a). Deployed boot image
`~/Downloads/nexus9/bootimg-build/n9-mainline/n9pmos-boot-stripped.img`
(2026-10-24 01:45) carries exactly:

```
androidboot.hardware=flounder console=tty0 loglevel=6 tegra_wdt.early_start=1
tegra_wdt.heartbeat=180 nouveau.config=NvGk20aDvfs=0 cma=256M
panel_jdi_lpm089a128a.keep_power=1
initcall_blacklist=tegra_devfreq_driver_init watchdog.stop_on_reboot=0
```

- **Compositor:** Greetd autologin → `phosh-session`; Phosh uses **phoc**
  (wlroots). Phoc's renderer is GLES2 on the kmsro stack
  (`GL vendor: NVIDIA`, `notes/gpu.md` 14:00; `tools/pmos/finish-rootfs.sh`
  30-46, 78-97). Not gnome-shell/mutter. Phosh/gnome-session is the session.
- **Mesa:** Alpine v3.24 Mesa 26.1.6, cross-built with
  `-Dgallium-drivers=tegra,nouveau,softpipe -Dllvm=disabled`, installed to
  `/opt/mesa-n9`; `LD_LIBRARY_PATH=/opt/mesa-n9/lib` in `/etc/environment`.
  No desktop libGL, no llvmpipe in this Mesa (`tools/pmos/mesa/build-mesa.sh`).
  System Mesa remains on disk.
- **Display driver:** tegra-dc/DSI (card0) is the KMS/fbdev owner; nouveau is
  render-only. `CONFIG_DRM_NOUVEAU=m`, `CONFIG_DRM_TEGRA=y`,
  `CONFIG_FB_SIMPLE=y` (`arch/arm64/configs/flounder_defconfig`).
- **Project patches affecting memory attributes / clocks / power:**
  - 0034 `NvGk20aDvfs=0` (cmdline) — no PMU DVFS loop.
  - 0038 GPC-PLL timeout → full reprogram fallback.
  - 0036 GK20A behind the SMMU.
  - 0039 heavy-throttle `gpu-throt-level` (thermal cut fixed).
  - **0040 write-combined GART BOs + one-shot cache clean (default on).**
  - **0042 `nouveau.tegra_wc` knob (default 1).**
  - `initcall_blacklist=tegra_devfreq_driver_init` — EMC/actmon off; DRAM held
    at 924 MHz after 8/8 clean boots (`notes/gpu.md` 22:55).
  - `tools/pmos/60-n9-gpufreq.rules` — GPU devfreq pinned min=max=612 MHz.
  - 0037 `panel_jdi_lpm089a128a.keep_power=1` (rails kept on at blank).
  - 0041 i2c CL-DVFS clocks (PMIC burst mitigation).
  - **GR vendor-reset candidate (`patches/candidates/gk20a-gr-vendor-reset.patch`)
    is NOT applied** (`gk20a_gr_reset_hw` absent from the tree), and was
    unnecessary after the EMC fix.
- **No `clk_ignore_unused`** in the cmdline. The postmarketOS Nexus 9 mainline
  wiki lists it as the workaround for a documented "image slowly distorts to
  static" display fault on this exact device.

---

## 4. Why a GPU/compositor fault can look like this (mechanisms, ranked)

1. **Framebuffer layout / stride / tiling mismatch (best fit for regular
   stripes).** If the GPU writes a surface with a pitch, GOB height, sector
   layout or kind differing from what tegra-dc is told, the DC walks rows at the
   wrong stride and the panel shows repeated/shifted columns — a static,
   whole-panel vertical stripe pattern. It is content, so it persists until a
   redraw.
2. **Corrupted CPU→GPU command/constant data.** Series 0040 removed the
   per-validate cache clean for Tegra GART BOs. The new one-shot guard is keyed
   on `ttm_dma->dma_address[0]` (`patches/linux-flounder-series/0040`, added
   field `wc_clean_addr`, default 0). The display bring-up notes prove IOVA 0
   is *legitimately allocated* on this SMMU ("the first DRM GEM object gets
   IOVA 0", `notes/display-progress.md`). A BO with IOVA 0 therefore skips its
   initial clean of the dirty zeroing lines, and the GPU can read stale DRAM
   instead of zeros. Stale/incoherent pushbuf or descriptor data can make the
   GPU use a wrong stride/tiling for a blit — another route to regular stripes.
   The guard is also per-BO, so any first-validation dedup hole matters. This
   is a real code smell, not a proof.
3. **GR/FECS failure** (half of boots before the EMC blacklist): produces no
   rendering / blank / greetd crash, not stripes. The blacklist is on now.
4. **EMC DVFS bit-flip corruption** (confirmed previously): random corruption —
   oopses, GR failures, sparkle. The lines appear *with* the blacklist on, so
   EMC scaling is not sufficient. Still worth an A/B because EMC can also be
   voted via ICC/cpufreq even with actmon blacklisted.
5. **Patched Mesa wrapper bug** would affect all rendering, not one pattern.
6. **Tiling/modifier path (latent).** It is provably inconsistent in this stack
   (see §5); most failure modes would be a modeset/EINVAL error or a fallback to
   linear, not silent stripes — but if tiled scan-out does get through, a
   swizzle/sector-layout mismatch gives exactly regular vertical stripes.

DSI/DC-side mechanisms that remain open: mainline DSI reconfiguration/clock
gating ("distorts to static" + `clk_ignore_unused`), DC FIFO underflow (bandwidth
starvation; documented for T124, but EMC is pinned at 924 MHz), or any stride/
pitch mismatch on the DC side that would also corrupt fbcon. These are exactly
what tests T3/T6 below distinguish.

---

## 5. Known bugs / prior art (task 4)

- **Nouveau GL modifier support is acknowledged broken** — Mesa MR !27672
  "Rip out modifiers support" (commit 851d0328): importing a surface with
  modifiers, *required for compositor use*, is "totally broken";
  `nvc0_resource_from_handle` calls `nv50_resource_from_handle`, pulls the tile
  mode out of the BO and blindly uses it; modifiers appear nowhere in the
  import path. This is precisely the kmsro/Phoc path here.
  https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/27672
- **Mesa/nouveau advertise a modifier form tegra-dc in this kernel cannot
  accept.** `nvc0_query_dmabuf_modifiers` advertises
  `BLOCK_LINEAR_2D(0, s, kind_gen, uc_kind, h)` with `uc_kind = 0xfe` for
  XRGB8888 (`/tmp/n9build/xbuild/mesa-26.1.6/.../nvc0_resource.c:44-82`,
  `nvc0_miptree.c:88-183`; TK1 sets `tegra_sector_layout=true` → s=0,
  `nouveau_screen.c:374-384`). `tegra_fb_get_tiling()` in
  `drivers/gpu/drm/tegra/fb.c:37-98` only matches the legacy
  `DRM_FORMAT_MOD_NVIDIA_16BX2_BLOCK(k)` values (kind 0, bit 12-19 clear); the
  canonicalisation helper `drm_fourcc_canonicalize_nvidia_format_mod()` exists
  in `include/uapi/drm/drm_fourcc.h:1012-1058` but **has no in-tree caller**.
  A canonical kind 0xfe FB therefore returns `-EINVAL` ("unknown format
  modifier"), not stripes. This means the tiled scan-out path is fragile and
  likely falls back to linear; if a tiled modifier ever does get through, the
  DC's interpretation is the prime place to look for stripes.
  Also `supports_sector_layout = false` for tegra124/132
  (`drivers/gpu/drm/tegra/dc.c:2924-2945`).
- **Tegra DC FIFO underflow / bandwidth management** — documented long-standing
  T124 visual corruption when bandwidth is not requested before scan-out
  (Dmitry Osipenko series, v6-v18):
  https://patchwork.kernel.org/project/dri-devel/patch/20210311170606.7543-2-digetx@gmail.com/
  No DC `interconnects` property exists in `tegra132.dtsi`, so this DC makes no
  ICC votes here; EMC is pinned by the blacklist anyway.
- **Nexus 9 mainline display corruption ("image slowly distorts to static"),
  worked around with `clk_ignore_unused`** — postmarketOS wiki, Google Nexus 9
  (htc-flounder):mainline, which links NVIDIA/tegra-nouveau-rootfs#22
  (Shield Tablet: display corruption while fb drivers probe; Thierry Reding:
  tegra-drm takes over and can disturb the bootloader framebuffer; unused
  display clock gating suspected).
  https://wiki.postmarketos.org/wiki/Google_Nexus_9_(htc-flounder):mainline
  https://github.com/NVIDIA/tegra-nouveau-rootfs/issues/22
- **No Tegra124/132-specific nouveau swizzle bug** surfaced in searches, and no
  plausible tegra-dc YUV/RGB mismatch for this symptom: the compositor scans
  XRGB8888, where the DC applies no CSC (CSC is YUV-only,
  `drivers/gpu/drm/tegra/dc.c:470-482`). A YUV/RGB mismatch would show up in
  video playback (the separate "flickering blocks"), not as boot-time RGB
  stripes.

---

## 6. Decisive tests (fastboot boot variants only; nothing flashed)

Record for every run: whether lines are present on (a) the pre-greetd kernel
console, (b) the greeter/home; dmesg for `unknown format modifier`, atomic-check
failures, `gr: init failed`, SMMU faults, DSI underflow `status=0x200`; and
whether the boot was one of the memory-corruption boots.

| # | Variant / action | Lines gone | Lines remain |
|---|---|---|---|
| **T0** | Current image, no change: watch the panel **before greetd/phoc starts** (fbcon on tegra-drm). | Console clean, lines only after Phoc: fault is downstream of KMS (GPU render or buffer content). DSI/DC exonerated. | Lines already on the DRM console: the fault is in the KMS scan-out path (DSI/DC/timing/pitch); the GPU is irrelevant. |
| **T1** | With the compositor running, take a Wayland screenshot (`grim`) and compare with the panel. | Screenshot clean, panel striped: the framebuffer is right and the fault is in scan-out (DC/DSI/tiling interpretation). | Screenshot striped too: the composited content itself is corrupt — GPU/compositor/Mesa/BO path. |
| **T2** | **Software compositor:** `WLR_RENDERER=pixman` (+ `GBM_ALWAYS_SOFTWARE=1 LIBGL_ALWAYS_SOFTWARE=1`; drop `LD_LIBRARY_PATH=/opt/mesa-n9/lib` if llvmpipe is needed), same kernel/DSI/DC. | GPU stack (nouveau/Mesa/kmsro/modifier/WC) is the source; display path fine. | Display/KMS path (DC/DSI/pitch) is the source — pixman uses CPU linear buffers. |
| **T3** | **Compositor stopped:** boot with greetd disabled (`GREETD_AUTOSTART=0` overlay, or `rc-service greetd stop` after SSH) → tegra-drm fbcon stays on screen. | tegra-drm KMS + mainline DSI/DC is fine; fault needs the GPU/compositor. | Mainline DRM scan-out or DSI/DC is faulty, independent of the GPU. |
| **T4** | **`nouveau.tegra_wc=0`** appended to the cmdline (module param, series 0042) — same image otherwise. | Series 0040/0042 (write-combine / one-shot clean / IOVA guard) is the regression. | WC is not the cause; look at the modifier/tiling and DSI paths. Repeat 2-3x (intermittent boots exist). |
| **T5** | **`WLR_DRM_NO_MODIFIERS=1`** in `/etc/environment` with the GPU compositor (force linear scan-out; a previous session was "a bit more stable" with this). | Tiled/modifier/scan-out layout path is implicated (see §5). | Tiling is not involved; focus on rendering/content or DSI. |
| **T6** | **`clk_ignore_unused`** appended to the cmdline (the documented Nexus 9 mainline workaround). | The known display-clock-gating fault is the cause — DSI/clock, not GPU. | That documented fault is not this one. |
| **T7** | **EMC blacklist off:** rebuild the boot image without `initcall_blacklist=tegra_devfreq_driver_init` (keep everything else). | Lines track the memory-corruption boots (oops/GR failure/early hang) → EMC DVFS corruption remains a cause. | EMC DVFS is not necessary for the lines (current evidence already says this). Expect GR/oops noise — do not use for long runs. |
| **T8** | **`nomodeset`** (control): no tegra or nouveau KMS takeover; the panel stays on the bootloader's simplefb; Phoc cannot start. | Expected clean by construction; proves only that the artifact needs DRM takeover. | Would mean the panel itself or hboot state is bad — contradicts the clean bootloader screen; investigate panel/rails. |
| **T9** | **`modprobe.blacklist=nouveau`** (module): no render node; Phoc GLES fails and falls back to pixman. | Same conclusion as T2: the GPU driver is required for the artifact. | Same as T2 remain: display path. (T2 is cheaper and less likely to leave a black screen.) |

Interpretation rules:
- T0/T3 answer **GPU-vs-DSI** directly: if the tegra-drm console is clean, the
  mainline DSI/DC path is producing correct output and the artifact is created
  in the GPU/compositor content.
- T1 separates **content vs transport** without any reboot.
- T2/T3 separate **GPU driver** from **KMS/DSI**.
- T4/T5 are the two regression/bug-specific probes (0040 and tiling).
- T6 is the only test aimed at the known device-specific DSI/clock fault.
- T7 is the memory-corruption control; current evidence predicts "no change",
  which is itself useful (rules EMC out).
- T8/T9 are controls, not discriminators.

Run order (cheapest / most informative first): **T0 → T1 → T2 → T3 → T4 → T5 →
T6 → T7 → T8/T9.** If T0 is conclusive, skip the rest; if T1 contradicts T0,
repeat T0 (the artifact may be intermittent or screen-state dependent).

---

## 7. Single cheapest experiment

**One boot with the software compositor (T2/T3): `WLR_RENDERER=pixman` (plus
`GBM_ALWAYS_SOFTWARE=1 LIBGL_ALWAYS_SOFTWARE=1`), same kernel, same mainline
DSI/DC.** One environment edit and one reboot, no image rebuild, no flashing.
Clean → the GPU/compositor stack is responsible (then run T4/T5 to pick WC vs
tiling). Striped → the display/KMS path is responsible (then run T6 and inspect
DSI underflow/pitch).

Even cheaper, zero-change pre-step: **T0** — on the next normal pmOS boot, watch
whether the kernel/fbcon console is clean before Phoc appears. If it is, the DSI
path is already exonerated.

If a single *fastboot-boot-image token* is preferred over a userspace edit, the
cheapest is **T4: add `nouveau.tegra_wc=0` to the cmdline** (the newest
memory-attribute change, and the only one that can corrupt GPU commands while
the DC scans correctly).

---

## 8. Caveats

- `notes/display-progress.md` says the clean diagnostic image uses **simplefb**,
  so it preserves hboot's DSI configuration; it does not prove mainline DSI
  reconfiguration is clean. Only T0/T3 (tegra-drm console) do.
- The clean `kmscube`/fbcon observations predate the vertical-line report and the
  series-0040 WC change; re-baseline them if the tests are ambiguous.
- The lines are described as static; if they in fact shimmer/roll, weight DSI/
  underflow higher and run T6 early.
- The GR-reset candidate is not in the kernel; a GR init failure gives blank/no
  rendering, not stripes, so it is not a cause of this symptom.
- Do not treat the `dri-debug`/"unknown format modifier" dmesg line as the root
  cause by itself; it would abort the modeset, which is a different failure than
  a running desktop with stripes.
