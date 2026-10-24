# Tegra132 VDE block-linear output: driver patch draft

Status: design draft, host-only. `driver.patch` is a unified diff against
`/home/nyasha/code/linux-flounder` (6.19.0, branch `flounder-clean`) and passes
`git apply --check`. It has **not** been compiled or booted.

## What it adds

1. `V4L2_PIX_FMT_YUV420M_TEGRA_BL` (`'T','B','L','4'`), a private fourcc in the
   T124/T132 `tegra124_decoded_fmts[]` list, describing the real block-linear
   output layout.
2. `V4L2_CID_TEGRA_VDE_BL_MODIFIER`, a driver-private read-only
   `V4L2_CTRL_TYPE_INTEGER64` control carrying
   `DRM_FORMAT_MOD_NVIDIA_16BX2_BLOCK(0)` = `0x0300000000000010`, the modifier
   measured for the T124/T132 output (`notes/vde.md`).
3. Padded plane geometry in `tegra_fill_pixfmt_mp()` for both `YUV420M`,
   `YVU420M` and the new fourcc:
   - luma pitch = `ALIGN(width, 128)`, luma rows = `ALIGN(height, 16)`;
   - chroma pitch = `pitch / 2`, chroma rows = `ALIGN(height / 2, 8)`.
4. Padded/GOB validation in the H.264 path
   (`tegra_vde_h264_setup_frame()`), which previously sized planes from the
   coded pixel count (`w_mbs*16 * h_mbs*16`) and ignored the actual stride.
5. `YUV420M`/`YVU420M` stay first in the format list, so they remain the default
   and the existing test/playback path keeps negotiating exactly as before
   (only `sizeimage` grows to cover padded rows).

## Insertion points (all hunks in `driver.patch`)

| file | hunk |
| --- | --- |
| `include/uapi/linux/videodev2.h` | private fourcc, after `V4L2_PIX_FMT_YUV420M` |
| `include/uapi/linux/v4l2-controls.h` | `V4L2_CID_USER_TEGRA_VDE_BASE` (0x1240, unused) + modifier CID, after the Mali-C55 base |
| `drivers/media/platform/nvidia/tegra-vde/vde.c` | add private fourcc to `tegra124_decoded_fmts[]` (second, YUV420M stays default) |
| `drivers/media/platform/nvidia/tegra-vde/v4l2.c` | include `<drm/drm_fourcc.h>`; control in `ctrl_cfgs[]`; rewrite `tegra_fill_pixfmt_mp()`; GOB guard in `tegra_try_decoded_fmt()`; NULL-safe lookup in `tegra_vde_prepare_control_data()`; SOC-gated registration in `tegra_init_ctrls()` |
| `drivers/media/platform/nvidia/tegra-vde/h264.c` | `tegra_vde_h264_setup_frame()`: padded sizes, stride/atom checks, strict BL pitch check |

No struct or function signature changes. No Kconfig change.

## Build / UAPI notes

- The two UAPI header hunks are **required**: without them the driver does not
  compile and userspace has no stable numeric values. `V4L2_CID_USER_BASE +
  0x1240` was free in 6.19 (0x1230 is Mali-C55); keep it stable once shipped.
- `v4l2.c` includes `<drm/drm_fourcc.h>` to spell the modifier symbolically.
  That header is header-only (`include/drm/drm_fourcc.h` +
  `include/uapi/drm/drm_fourcc.h`) and does not require `CONFIG_DRM`, but if a
  minimal/odd build complains, replace the three macro uses in `ctrl_cfgs[]`
  with the literal `0x0300000000000010ULL`.
- The control is gated on `ctx->vde->soc->t124_layout`: T20/T30 output is
  linear, so the modifier must not be advertised there. The skipped slot stays
  NULL and `tegra_vde_prepare_control_data()` now skips NULL entries (both
  changes are in the patch); without the skip, decoding on T20/T30 would
  dereference NULL.
- `V4L2_CTRL_TYPE_INTEGER64` requires `step != 0` (`check_range()`), hence
  `.step = 1` with `min == max == def`. `V4L2_CTRL_FLAG_READ_ONLY` makes
  `v4l2_ctrl_handler_setup()` skip it and prevents userspace writes.

## How the modifier is exposed (important)

`struct v4l2_query_ext_ctrl` in 6.19 has **no value field**. `VIDIOC_QUERY_EXT_CTRL`
therefore carries the modifier in `minimum`/`maximum`/`default_value` (all equal
because min == max == def); `VIDIOC_G_EXT_CTRL` returns it in
`v4l2_ext_control.value64`. Reporting it via QUERY_EXT_CTRL is thus satisfied,
but userspace should prefer G_EXT_CTRL for the actual value. The control exists
for both fourccs (the hardware always emits BL; the legacy YUV420M description
is simply not the truth).

## Geometry contract

For `width`/`height` = the CAPTURE format size (coded dims rounded to the
frmsize step):

```
pitch        = ALIGN(width, 128)                 # whole 64-byte GOBs
plane[0]     = pitch          * ALIGN(height, 16)     # luma
plane[1..2]  = (pitch / 2)    * ALIGN(height / 2, 8)  # Cb, Cr
```

Example: 640x360 -> pitch 640, luma 640*368, chroma 320*184 (this matches the
"640x360 needs 368 rows" measurement). 1920x1080 -> pitch 1920, luma 1920*1088,
chroma 960*544.

The H.264 validation now derives its minimum plane sizes from these strides and
padded row counts, so it protects the real hardware write footprint. The strict
BL check requires `lstride == ALIGN(pic_width_in_mbs * 16, 128)` and
`cstride == lstride / 2`. If a stream ever yields a CAPTURE width different from
the coded width in a way that crosses a 128-byte boundary, relax the equality to
`lstride >= ypitch && lstride % 64 == 0` (a larger GOB-aligned pitch is still a
valid block-linear surface; the importer reads the stride from GstVideoMeta).

## Why YUV420M is also padded

The hardware writes padded rows regardless of the declared format, and the old
`sizeimage = pitch * height` under-allocated for heights not a multiple of 16
(640x360: 230400 vs the 235520 actually written). The new geometry fixes that
latent overrun for the fallback format too. Consumers that allocate from the
sizeimage returned by S_FMT are unaffected; consumers that hard-code a tight
size will now see `-EINVAL` from `queue_setup` (it requires
`size >= sizeimage`) rather than silent corruption.

## Conceptual compile check (no build was run)

Verified against this tree by reading the callees:

- `v4l2_ctrl_new_custom()` (`v4l2-ctrls-core.c`) accepts an explicit
  `type`/`name`/`min`/`max`/`step`/`def`/`flags`; `name != NULL` skips
  `v4l2_ctrl_fill()` for the private ID; `check_range()` for INTEGER64 needs
  `step != 0` and `min <= def <= max` (satisfied); the ID is far below
  `V4L2_CID_PRIVATE_BASE`, so it is accepted.
- `v4l2_query_ext_ctrl()` copies `minimum`/`maximum`/`default_value` verbatim,
  hence the QUERY_EXT_CTRL exposure above.
- `v4l2_format_info()` returns NULL for the private fourcc; the rewritten
  `tegra_fill_pixfmt_mp()` no longer calls it, and no other in-driver or
  v4l2-core try/s_fmt path calls it for this fourcc.
- `tegra_vde_h264_setup_frame()`'s `dev` local, `lstride`/`cstride` types
  (`unsigned int`) and `tegra_vde_validate_vb_size()` signature are unchanged.
- `tegra_buffer_init()` allocates the aux BO from plane 1's size (now the
  padded chroma size), so the `aux->size >= csize` check in setup_frame holds.
- `tegra_fill_pixfmt_mp()` is called from `tegra_reset_decoded_fmt()` and
  `tegra_try_decoded_fmt()`; S_FMT copies the TRY result, so the padded
  geometry is enforced on both.

## Test / follow-up suggestions

- `v4l2-ctl --list-formats-out`/`--list-formats-ext` should show both fourccs;
  `v4l2-ctl -L`/`--query-ext-ctrl` should show the modifier (read-only,
  INTEGER64).
- Keep `tools/vde-test.sh` on YUV420M to confirm no regression from the padded
  sizeimages before touching userspace.
- Optional: add the fourcc to `v4l2_format_info()` in
  `drivers/media/v4l2-core/v4l2-common.c` (3 mem planes, 3 comp planes, 8 bpp,
  hdiv/vdiv 1/1/2, 2/2/2) if generic helpers or libv4l must understand it.
