# Display bring-up for flounder

What was built, what it took, and what is still unproven. The panel itself —
sequences, timings, power order — is documented separately in `notes/panel.md`.

## What exists now

Two boot images, both built from the same stock LTE image with only the kernel
region replaced (`tools/bootimg-repack.py`):

| Image | Size | Kernel | What the screen does |
|---|---|---|---|
| `boot-lte-6.19.img` | 10,885,376 | 6.19.0, `FB_SIMPLE` only | Framebuffer console from the bootloader's framebuffer. The known-good fallback. |
| `boot-lte-6.19-gfx.img` | 11,327,744 | 6.19.0 + `DRM_TEGRA` + panel driver | Intended: real DRM/KMS on the panel. |

Both carry `compatible = "google,flounder64_lte"`, so both pass the bootloader's
gate. Both keep the stock ramdisk byte-for-byte
(sha256 `8c7e5b8a11f447999f884cb5a4e59be4b40f28b7eafd3c4649cf4ab628142a6b`).

Neither has been flashed to hardware yet.

## The driver

`drivers/gpu/drm/panel/panel-jdi-lpm089a128a.c` — 515 lines. Modelled on the
Pixel C's `panel-jdi-lpm102a188a.c`, which is the same shape: JDI, dual DSI,
gang-linked, DCS backlight.

It does, in `prepare()`:

- powers up in the downstream order — `iovdd` (15 ms), `avdd` (1 ms),
  `dcdc_en` (15 ms), out of reset (15 ms);
- writes the manufacturer page select and the 24-byte `ce[]` table as generic
  packets, then `0xd6`, then page `0x03`;
- DCS exit-sleep, 120 ms, then `0x53`/`0x55`/`0x35`, then display-on.

And in `unprepare()`: brightness to zero, display-off, enter-sleep, three frames,
then the page writes, then power down in reverse.

## Seven bugs found before any hardware was touched

Worth recording because of *where* they came from — only two came from reading
the code against its template.

| # | Bug | Caught by |
|---|---|---|
| 1 | `drm_panel_add()` returns `void` in 6.19, not `int` | compiler |
| 2 | Backlight sent **two** payload bytes for DCS `0x51`; this panel takes **one** | **REA** — hboot's own `jdiDsi_SetBacklightIntensity` |
| 3 | `unprepare()` returned early on link error, leaving both rails enabled with refcounts permanently held | subagent audit |
| 4 | Backlight DCS could be written to an unpowered, in-reset panel — it is a separate device userspace can write at any time | subagent audit |
| 5 | Sent DCS `0x2a`/`0x2b`, command-mode windowing that downstream never sends and video mode does not need | subagent audit |
| 6 | `0xb0`/`0xb1` sent as DCS in suspend; downstream sends them as generic writes | comparison with the downstream macros |
| 7 | `mipi_dsi_dual_dcs_write_seq_multi()` given a runtime value — its initialisers must be compile-time constants | compiler |

Bug 2 is the instructive one: `mipi_dsi_dcs_set_display_brightness_multi()` is
the obvious helper, it compiles, it looks right — and it puts two bytes on the
wire where this panel wants one. Nothing but the artifact could have settled it.
Bug 5 is its mirror: I copied command-mode logic into a video-mode driver.

## Device tree change

`arch/arm64/boot/dts/nvidia/tegra132-flounder.dts` linked its two panels with
`port_b`/`port_a` phandles, but the driver — like every dual-DSI panel driver in
the tree — resolves its second link with `of_parse_phandle(node, "link2", 0)`.
With `port_b` there, probe finds no second link and **registers no panel at all**;
the driver would load and silently do nothing.

`link2 = <&panel_secondary>` on `panel_primary` fixes it, following
`tegra210-smaug.dts`. Verified in the built DTB: `link2` resolves to the
secondary panel's phandle.

## Kernel config: three requirements and one trap

```
CONFIG_ARCH_TEGRA=y               already set
CONFIG_DRM=y                      must be built in — see below
CONFIG_TEGRA_HOST1X=y
CONFIG_DRM_TEGRA=y                selects DRM_MIPI_DSI and DRM_PANEL
CONFIG_DRM_PANEL_JDI_LPM089A128A=y
```

**The trap.** `DRM_MIPI_DSI` is declared `bool` with **no prompt string** — a
hidden symbol. It cannot be set by hand; `scripts/config` writes it,
`olddefconfig` drops it, and nothing complains. It only exists when something
`select`s it, which in practice means `DRM_TEGRA`.

And the port's config had `CONFIG_DRM=m`. A `select` on a bool forces `y`, so
`DRM_TEGRA=m` dragged `DRM_MIPI_DSI` to `y` while `DRM` was still a module — a
built-in symbol inside a module, which cannot exist. `drm_mipi_dsi.c` was never
compiled and every `mipi_dsi_*` export was undefined at modpost. The fix is to
build the DRM stack in (`DRM=y`), which is what a display driver wants anyway.

## DSI mode: sync events, not sync pulses

The driver sets:

```c
dsi->mode_flags = MIPI_DSI_MODE_VIDEO | MIPI_DSI_CLOCK_NON_CONTINUOUS;
```

That was a real risk, because the Tegra DSI host treats `MIPI_DSI_MODE_VIDEO` and
`MIPI_DSI_MODE_VIDEO_SYNC_PULSE` as a two-bit switch selecting *different packet
sequences* (`drivers/gpu/drm/tegra/dsi.c:497-505`), and "non-burst" alone does not
say which.

The downstream driver settles it. It picks its packet sequence from
`video_burst_mode`, and the panel sets `TEGRA_DSI_VIDEO_NONE_BURST_MODE` — the
plain variant, not `_WITH_SYNC_END`:

```c
case TEGRA_DSI_VIDEO_NONE_BURST_MODE_WITH_SYNC_END:
        pkt_seq = dsi_pkt_seq_video_non_burst_syne;
case TEGRA_DSI_VIDEO_NONE_BURST_MODE:
default:
        pkt_seq = dsi_pkt_seq_video_non_burst;      /* ours */
```

Comparing that sequence against both mainline candidates entry by entry:

```
downstream 'non_burst' == mainline 'sync_events' ?  True    (all 13 entries)
downstream 'non_burst' == mainline 'sync_pulses' ?  False
```

`dsi_pkt_seq_video_non_burst` is identical to `pkt_seq_video_non_burst_sync_events`
— `V_SYNC_START + EOT`, then `H_SYNC_START + EOT` pairs, then the
`H_SYNC_START + BLANKING + PIXEL24` and `BLANKING` pair. Mainline selects that
sequence exactly when `SYNC_PULSE` is **clear**.

So `SYNC_PULSE` must stay absent and the flags are correct as written. Two further
notes for anyone changing this later: Tegra has **no burst branch at all**
(`MIPI_DSI_MODE_VIDEO_BURST` has no consumer under `drivers/gpu/drm/tegra/`), and
the `_HSE` / `NO_HFP` / `NO_HBP` / `NO_HSA` flags are likewise no-ops there.

## The risk this carries

`drivers/gpu/drm/tegra/drm.c:1260`:

```c
if (drm->mode_config.num_crtc > 0) {
	err = aperture_remove_all_conflicting_devices(tegra_drm_driver.name);
```

The bootloader's framebuffer is evicted as soon as **any** CRTC registers — and
CRTCs come from the display controllers, which probe from plain device tree
nodes. So the framebuffer console is taken away even if the panel driver fails
to bind. A bug in the panel driver therefore costs the working console and
leaves a black screen.

That is the whole reason for two images: `boot-lte-6.19.img` is the one that
still shows something while `boot-lte-6.19-gfx.img` is being proven.

## Reproducing

```sh
git clone --branch flounder --single-branch --depth 1 \
    https://cyberchaos.dev/yuka/linux.git
cd linux
git apply /path/to/patches/flounder-lte-and-display.patch
curl -o arch/arm64/configs/flounder_defconfig \
    https://gitlab.postmarketos.org/postmarketOS/pmaports/-/raw/main/device/testing/linux-htc-flounder/config-htc-flounder.aarch64
```

then enable the config symbols above and build with `LLVM=1` as the pmOS recipe
does. `bootimg-repack.py` turns the `Image` and the DTB into a boot image.

**Note:** `flounder-lte-and-display.patch` is cumulative from commit
`38ff68627` — it contains the LTE `compatible` change *as well as* the display
work, so it **supersedes** `dts-compatible-flounder64-lte.patch` rather than
being applied alongside it. Applying both will conflict on the DTS hunk.

## Not done

- **Nothing has run on hardware.** Every claim above is from source, build
  output, or the built artifacts. The driver has never bound to the panel.
- **No device tree binding document.** `Documentation/devicetree/bindings/display/panel/jdi,lpm089a128a.yaml`
  does not exist and would be required before this could go upstream. The sibling
  `jdi,lpm102a188a.yaml` is the model.
- **The CMU and smart-dimming tables are not ported.** They are downstream-only
  (`CONFIG_TEGRA_DC_CMU`) with no mainline equivalent, so expect a different
  colour response from Android until that is addressed separately.
- **Sync polarity is unset** in the mode. Downstream does not state it; if the
  image comes up shifted or torn, that is the first thing to question.
