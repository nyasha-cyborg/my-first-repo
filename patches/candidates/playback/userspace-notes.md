# GStreamer 1.28 v4l2codecs changes for V4L2_PIX_FMT_YUV420M_TEGRA_BL

Scope: what a zero-copy-capable GStreamer needs so that the private fourcc and
`DRM_FORMAT_MOD_NVIDIA_16BX2_BLOCK(0)` become DMA_DRM caps on the decoder's
src pad. Names below are from the 1.24/1.26 `v4l2codecs` sources; verify the
exact symbols in the 1.28 tree, they have been renamed more than once. Grep
anchors are given where a name may have moved.

The plugin lives in `subprojects/gst-plugins-bad/sys/v4l2codecs/` (installed
as `libgstv4l2codecs.so`); it is a stateless-codec framework, not
`gst-plugins-good`'s `v4l2` plugin.

## 1. The modifier transport problem (read this first)

Linux 6.19 V4L2 has no format-modifier UAPI:

- `struct v4l2_pix_format_mplane` has no `modifier` field, and
  `VIDIOC_ENUM_FMT` / `VIDIOC_G_FMT` / `VIDIOC_S_FMT` / `VIDIOC_TRY_FMT` cannot
  carry one (the "V4L2 format modifiers" RFC is not merged).
- Therefore GStreamer cannot learn the modifier from the format ioctls. The
  only in-kernel channel is the private control added by the driver patch:
  `V4L2_CID_TEGRA_VDE_BL_MODIFIER`, read-only INTEGER64.

Reading it:

1. `VIDIOC_QUERY_EXT_CTRL` with `.id = V4L2_CID_TEGRA_VDE_BL_MODIFIER`
   (`0x00981b41`). If it returns `-EINVAL`, the kernel is too old: fall back to
   the legacy `YUV420M` fourcc (see §4).
2. The 6.19 `struct v4l2_query_ext_ctrl` has **no value field**; the modifier is
   in `.default_value` (also `.minimum`/`.maximum`, all equal). Prefer
   `VIDIOC_G_EXT_CTRL` (`V4L2_CTRL_TYPE_INTEGER64` -> `.value64`) for the value.
3. Never `S_EXT_CTRL` it (READ_ONLY) and never put it in a request; it is a
   descriptor, not a per-frame control.

The value is constant for the private fourcc and equals
`DRM_FORMAT_MOD_NVIDIA_16BX2_BLOCK(0)` = `0x0300000000000010`, so an interim
patch may hard-code it keyed on the fourcc. Do the control lookup anyway: it is
the only forward-compatible transport if other GOB stackings or SoCs appear.

## 2. Format table: V4L2 fourcc -> GstVideoFormat

File: `sys/v4l2codecs/gstv4l2format.c`
Functions: `gst_v4l2_format_to_video_format()`, `gst_v4l2_format_to_video_info()`
and the static `v4l2_formats[]` / `formats[]` table (grep `V4L2_PIX_FMT_YUV420M`).

Add an entry for `V4L2_PIX_FMT_YUV420M_TEGRA_BL`:

- underlying pixel layout: `GST_VIDEO_FORMAT_I420` (3-plane 8-bit 4:2:0, Y then
  Cb then Cr — same plane order the driver writes);
- a new flag/field on the table entry, e.g. `imply_dma_drm_modifier = TRUE` (or
  a per-format `drm_fourcc = DRM_FORMAT_YUV420`), so the caps builder knows this
  fourcc must be advertised as DMA_DRM, not as plain `video/x-raw`.
- Do **not** map it to a linear I420 caps entry with the normal
  `sizeimage = pitch*height` assumption; the whole point is the modifier.

## 3. Caps probing: advertise DMA_DRM + modifier

File: `sys/v4l2codecs/gstv4l2codec.c`
Functions: `gst_v4l2_codec_probe_caps()` (and, depending on version,
`gst_v4l2_decoder_probe_caps()` / the `VIDIOC_ENUM_FMT` loop in
`gst_v4l2_decoder_set_sink_caps()`); grep `VIDIOC_ENUM_FMT`.

For each CAPTURE pixelformat returned by ENUM_FMT:

- if it is the BL fourcc: read the modifier as in §1, then append
  `video/x-raw(memory:DMABuf)` caps with
  `format=(string)DMA_DRM, drm-format=(string)"YU12:0x0300000000000010"`
  (`DRM_FORMAT_YUV420`; the DMA_DRM caps string uses the DRM fourcc name
  `YU12`). Use `gst_video_dma_drm_caps_append()` from
  `gst-libs/gst/video/video-dma-drm.h` if present (>= 1.24); otherwise build
  the structure by hand and convert with
  `gst_video_dma_drm_info_to_video_info()`.
- keep emitting the legacy `video/x-raw, format=I420` caps for the plain
  `YUV420M` fourcc so old pipelines still negotiate the fallback.

Downstream compatibility check: only advertise the DMA_DRM variant when the
`GstCaps` filter (or a capable peer) accepts it, otherwise negotiate the legacy
fourcc. `DMA_DRM` requires downstream to understand the `drm-format` field;
glupload/kmssink in 1.24+ do, older sinks do not.

## 4. Decoder negotiation and GstVideoInfo

File: `sys/v4l2codecs/gstv4l2decoder.c`
Functions: `gst_v4l2_decoder_decide_allocation()`,
`gst_v4l2_decoder_set_output_state()` / `gst_v4l2_decoder_negotiate()`
(grep `gst_video_info_set_format` and `VIDIOC_S_FMT`).

- When the chosen src caps are the DMA_DRM variant, build `GstVideoInfo` from
  the CAPTURE S_FMT planes: `width`/`height` from the format, `stride[0] =
  plane_fmt[0].bytesperline`, `stride[1..2] = plane_fmt[1..2].bytesperline`,
  `offset[0] = 0`, `offset[1] = plane_fmt[0].sizeimage`, `offset[2] =
  plane_fmt[0].sizeimage + plane_fmt[1].sizeimage`, `size = sum of all
  sizeimage`, `n_planes = 3`. Do not recompute from
  `GST_VIDEO_INFO_PLANE_STRIDE` defaults: the padded values from the driver are
  mandatory.
- Map the selected V4L2 fourcc back through the format table; the DMA_DRM
  `GstVideoInfo` must still report `GST_VIDEO_FORMAT_I420` internally (or
  `GST_VIDEO_FORMAT_DMA_DRM` with the `drm-format` field, depending on how
  1.28 models it), so that `GstVideoMeta` and downstream caps agree.
- The decoder's output state must not compact/shrink the height to the display
  crop: the buffers are `ALIGN(height,16)` rows (and `ALIGN(height/2,8)` chroma
  rows). Keep the padding in the meta even if the caps describe the visible
  size.

## 5. Buffer pool / allocator

Files: `sys/v4l2codecs/gstv4l2allocator.c`, `gstv4l2bufferpool.c`
Functions: `gst_v4l2_allocator_alloc()`, the `VIDIOC_EXPBUF` path, and the
`memory:DMABuf` wrapping (`gst_v4l2_allocator_get_dmabuf_fd`-style helpers).

- The CAPTURE queue is MPLANE with 3 planes, each a separate vb2 allocation, so
  `VIDIOC_EXPBUF` yields **three dmabuf fds**, one per plane. A DRM single-buffer
  format (`DRM_FORMAT_YUV420`) expects **one dmabuf with three offsets**. Two
  options:
  a. teach the pool to wrap the three fds as three `GstMemory`s of one
     `GstBuffer` and make the importer accept multi-memory DMA_DRM (glupload's
     DMABuf path and kmssink generally do not);
  b. allocate/import one dmabuf for the whole surface and use
     `V4L2_MEMORY_DMABUF` on CAPTURE, passing the same fd three times with
     `data_offset` = 0 / luma_size / luma_size+chroma_size. The driver supports
     this (`tegra_buf_init()` maps each plane's dmabuf; `tegra_buf_prepare()`
     adds `data_offset`), and it is the layout DRM/KMS/GL importers want.
     `GstV4l2Allocator` needs an optional "single dmabuf, split by offset"
     mode for this.
- Ensure the buffer pool asks for at least `sizeimage` per plane; the driver's
  `tegra_queue_setup()` rejects smaller buffers.
- `GstVideoMeta` must be attached with the strides/offsets from S_FMT (§4),
  otherwise the modifier is meaningless to importers.

## 6. Fallback / legacy path

- When the control is absent, or the peer does not take DMA_DRM caps: keep the
  current `YUV420M` negotiation. Note that the legacy fourcc lies about the
  layout (the bytes are still block-linear); it is only usable by a consumer
  that detiles/converts (the current score tools via `tools/vde-detile.py`, or
  a future `videdetile`/`glcolorconvert`-style element). Never feed plain
  `video/x-raw, format=I420` from this hardware to a DRM sink without detiling.
- The fallback must not lose the padded `sizeimage` (the driver enforces it);
  the meta should still describe the padded strides for the detiler.

## 7. Verification

- `gst-inspect-1.0 v4l2slh264dec` (or `v4l2h264dec`) shows the src caps; the
  private fourcc should appear as `video/x-raw(memory:DMABuf),
  format=(string)DMA_DRM, drm-format=(string)YU12:0x0300000000000010`.
- `GST_DEBUG=v4l2*:6` and `V4L2_DEBUG` traces confirm ENUM_FMT/QUERY_EXT_CTRL
  values and the chosen S_FMT plane geometry.
- Pipe to `kmssink` and to `glupload ! glcolorconvert` as separate checks (see
  risk notes); a `filesink`/`fakesink` tone does not exercise the modifier.
- Keep a YUV420M-only pipeline as the regression baseline.

## Version caveat

1.28 renamed several v4l2codecs symbols and moved caps construction between
`gstv4l2codec.c` and `gstv4l2decoder.c` more than once. The durable anchors are:
the `VIDIOC_ENUM_FMT` loop that builds src caps, the fourcc table in
`gstv4l2format.c`, `gst_video_dma_drm_caps_append()` /
`gst_video_dma_drm_info_to_video_info()` in gst-plugins-base, and the EXPBUF
path in the allocator. If `gst_video_dma_drm_*` is unavailable, the same caps
can be built manually (`format=DMA_DRM` plus a `drm-format` string field) and
`GstVideoMeta` filled from the S_FMT planes.
