# Evidence — stock Nexus 9 boot images

All numbers below are measured from the two Android 7.1.1 OTAs with
`tools/bootimg-split.py` and `tools/fdt-scan.py`. Nothing here is inferred except
where a paragraph says so.

## Boot image header (legacy `ANDROID!`, header v0)

| | LTE (`volantisg`, N4F27P) | Wi-Fi (`volantis`, N4F27B) |
|---|---|---|
| file size | 8,829,440 | 8,843,776 |
| wrapper before header | 256 bytes, first 4 bytes `12 34 56 78` | same |
| page size | 2048 | 2048 |
| kernel | 7,169,138 (`1f8b0800` = gzip) | 7,182,550 (gzip) |
| ramdisk | 1,655,254 (gzip) | 1,655,250 (gzip) |
| second | 0 | 0 |
| kernel sha256 | `622c98a9bc0174ec90755cb7b78ca21fef0cfad6da4985a2bea16498cabbd83d` | `3289d197f77bd2b469a480dff90db71f8a43637b5c108581649f7ea92737b4e2` |
| ramdisk sha256 | `8c7e5b8a11f447999f884cb5a4e59be4b40f28b7eafd3c4649cf4ab628142a6b` | `2eba1f7dd80cb92a837e1c5f8f83b3e61fd5bdc2ed6c0078f3095f26a1ec1e0e` |

The kernel command line is byte-identical in both:

```
androidboot.hardware=flounder buildvariant=user
```

Note the hardware name is plain `flounder` even on the LTE build — the variant is
not in the command line either.

## Kernels (decompressed `Image`)

| | LTE | Wi-Fi |
|---|---|---|
| file | `kernel-lte.raw`, 16,383,576 B | `kernel-wifi.raw`, 16,416,600 B |
| sha256 | `3440a3e2f79482cc299e133c752f7c2c9caf6013696980ce8b7afb68f08eb175` | `23ba9f0398e729d13fb288156013132d5347a75eaa9d1bf84b16d33ec0e6e6b9` |
| banner | `Linux version 3.10.103-gfa7d4389a60` | `Linux version 3.10.103-g0a2199e` |
| built | `#1 SMP PREEMPT Wed Aug 30 19:58:00 UTC 2017` | `#1 SMP PREEMPT Fri Mar 24 23:42:12 UTC 2017` |
| build host | `android-build@wprf4.hot.corp.google.com` | `android-build@kpfk7.cbf.corp.google.com` |

Same version number, **different source commit** — so these are two different builds
of the 3.10 tree, not one binary relabelled.

## Device trees

Four DTBs per image. The four blobs are **byte-identical between the two variants**;
only their offsets move, and the shift is exactly the kernel size difference
(7,182,550 − 7,169,138 = 13,412 = `0x3464`):

| size | sha256 | at (LTE) | at (Wi-Fi) | `compatible` | `hw-revision` contains |
|---|---|---|---|---|---|
| 107,788 | `99426d106590c7cac9bf77cedbd1c17067ad6734ff839aed38ebbc5892ef241b` | `0x66d8d2` | `0x670d36` | `google,flounder64` | — |
| 107,784 | `2766715a18fdd1c73093ef1b5c9acb70d58aa61ea19988fc21ec5c828bd5cdf5` | `0x687dde` | `0x68b242` | `google,flounder64` | — |
| 107,842 | `52d18069409495f895a7761945583ae22693afd445ceb5c35871c34ab9a4d3c9` | `0x6a22e6` | `0x6a574a` | `google,flounder64` | `xd,xe,pvt` |
| 107,850 | `bc9141a42e98948d1851ed9690f01b40abbe11cebf208d2a3513e3f76b0fbf11` | `0x6bc828` | `0x6bfc8c` | `google,flounder64_lte` | `xa,xb,xc,xd,pvt` |

The four entries are different sizes and carry different `hw-revision` values, so
they are four distinct builds. Reading the `hw-revision` property out of each blob
(this needs a real parse — `xc` is too short for `strings` to show) identifies them
exactly, and they match the four board files in the downstream Android kernel:

| blob size | `compatible` | `hw-revision` | downstream source file |
|---|---|---|---|
| 107,788 | `google,flounder64` | `xa,xb` | `tegra132-flounder-xaxb.dts` |
| 107,784 | `google,flounder64` | `xc` | `tegra132-flounder-xc.dts` |
| 107,842 | `google,flounder64` | `xd,xe,pvt` | `tegra132-flounder-xdxepvt.dts` |
| 107,850 | `google,flounder64_lte` | `xa,xb,xc,xd,pvt` | `tegra132-flounder_lte-xaxbxcxdpvt.dts` |

Those sources are in the Android 3.10 tree (e.g.
`CaptainThrowback/kernel_android-tegra-flounder-3.10`, branch `BeyondStock-M-MR1`,
`arch/arm64/boot/dts/`), and each one just sets `compatible` plus `hw-revision` on
top of the shared `tegra132-flounder-generic.dtsi`.

**What this means.** The DTB set is per board *revision*, not per variant, and both
stock images carry the complete set — including the LTE blob. So the set does not
distinguish Wi-Fi from LTE; the bootloader does, by matching `compatible` and
`hw-revision`, which is why an LTE boot image is happy to contain a Wi-Fi blob it
will never choose. Building a kernel from the Wi-Fi board file alone produces a
single DTB that the LTE bootloader has no reason to accept. The `compatible` change
in `patches/dts-compatible-flounder64-lte.patch` is therefore the right kind of fix,
and corresponds exactly to the two stock DTBs that Google built for these boards.

## Ramdisks

`diff -rq rd-lte rd-wifi` reports differences in:

- `default.prop` — build date and fingerprint only
  (`google/volantisg/flounder_lte:7.1.1/N4F27P/4333386:user/release-keys` vs
  `google/volantis/flounder:7.1.1/N4F27B/3853226:user/release-keys`)
- `selinux_version`, `sepolicy`, `property_contexts`, `service_contexts`
- `sbin/`: `adbd`, `healthd`, `slideshow`, `ueventd`, `watchdogd`
- `init`

That is build metadata, SELinux policy and a handful of binaries — no board
description, no kernel configuration.

## Provenance of the patched file

`patches/flounder.dts.orig` is byte-identical (sha256
`578f10226fb341e32961a3fe853ed106e6f91957370f0feeaef16187ab556371`) to
`arch/arm64/boot/dts/nvidia/tegra132-flounder.dts` in **`yuka/linux`** at commit
`38ff68627120b204b30d030e5f4dd7d1ee33acc3` — the fork postmarketOS's kernel package
pins. So the patch is not against upstream, which has no such file.

That fork's tree is the surviving flounder device tree, and it is written for the
Wi-Fi board: `compatible = "google,flounder64"`. It carries no `hw-revision`
property and no `chassis`, and it includes the downstream-style
`tegra132-flounder-emc.dtsi` (195 KB of EMC timings) alongside the upstream-named
`tegra132.dtsi`.

## The bootloader's DTB gate (measured in `hboot.img`, 2026-10-16)

The gate was previously inferred from the fact that both stock images carry all
four DTBs. It is now read out of the bootloader itself.

- `bootloader.img` is a **256-byte HTC wrapper followed by a ZIP** — first local
  file header at offset 256, central directory at 2,970,021, end-of-central-dir at
  2,970,755. The compressed body is why a naive `strings` pass finds nothing.
- The ZIP holds the whole Tegra boot chain: `hboot.img` (1,045,984), `nvtboot.img`
  (125,072), `nvtbootwb0.bin` (2,048), `rawbct.img` (8,704), `tos.img` (2,663,168),
  `sp1.nb0` (6,291,456), `mts_preboot_prod`, `mts_prod`, `gp1.img` (a GPT),
  `pt_16g.img` / `pt_32g.img` / `pt_64g.img`, and `_android-info.txt` (`board=flounder`).
- `hboot.img` is raw **ARM 32-bit** (begins `07 00 00 ea`, an ARM branch table) with
  no ELF wrapper, so it needs
  `llvm-objcopy -I binary -O elf32-littlearm --binary-architecture=arm` before a
  disassembler will take it. REA/Ghidra 12.1.4 then decompiles it.
- The gate function is `FUN_00081ac0`, and it carries these strings — which are the
  entire argument, in hboot's own words:

  | string | role |
  |---|---|
  | `Checking appended FDT at offset 0x%08x\n` | progress, per candidate |
  | `kernel_has_appended_dtb` | the mechanism it is looking for |
  | `%s: Invalid fdt header. err: %s\n` | header validation failure |
  | `%s: FDT size larger than boot image\n` | bounds failure |
  | `hw-revision` | the second, conditional test |
  | `Found compatible dtb image at offset 0x%08x, kernel size 0x%08x\r\n` | success |
  | `Can not find a compatible dtb image\r\n` | the failure we were chasing |

  It also contains both `google,flounder64` and `google,flounder64_lte`.

- Decoded logic — ordinary libfdt use, for each DTB appended in the kernel region:
  1. read the 40-byte FDT header and validate the magic (`0x28` is the length passed);
  2. take `totalsize` from header offset 4 and byte-swap it from big-endian;
  3. bounds-check the DTB against the image size;
  4. `fdt_path_offset(fdt, "/")` — the `/` literal in the pool;
  5. `fdt_node_check_compatible(fdt, root, required_compatible)` must return 0;
  6. `fdt_get_property(fdt, root, "hw-revision")` — **if the property is absent the
     DTB is accepted immediately**; only if it is present must it match the board.
- The board revision is a **single letter `a`–`h`**: the comparison path ends in a
  nine-case switch over one-character strings. That explains the stock values —
  `"xa,xb"`, `"xc"`, `"xd,xe,pvt"` and `"xa,xb,xc,xd,pvt"` are token lists over
  those revision letters, not opaque blobs.

**Consequence.** The one-line `compatible` change is *sufficient* — the Wi-Fi DTS
carries no `hw-revision`, so step 6 accepts it without a revision test — and it is
*safer* than porting the downstream LTE board file, which would add
`hw-revision = "xa,xb,xc,xd,pvt"` and thereby arm a second check that can fail. The
stock LTE DTB covers revisions a–d only; ours, by omitting the property, is
revision-agnostic and strictly more permissive than Google's own.

Not yet verified: which compatible string the caller (`FUN_0007e084`) passes on LTE
hardware. hboot holds both strings, so the choice is made at runtime.

Address note: REA reports Ghidra addresses as raw image offset + `0x10000`, and the
wrapped copy shifts `.data` by a further `0x174`, so an REA address maps to file
offset `addr - 0x10000 + 0x174`.

## Boot image container (measured)

- The header is the **legacy HTC layout, not modern AOSP**: `name[16]` at `+0x30`
  and `cmdline[512]` at `+0x40`. Modern `mkbootimg` writes a 32-byte `id` there and
  puts the cmdline at `+0x50`, so a rebuilt header would parse differently. The
  stock header must be reused verbatim.
- Header fields: page_size 2,048 · dt_size 0 · kernel_addr `0x10008000` ·
  ramdisk_addr `0x11000000` · second_addr `0x10f00000` · tags_addr `0x10000100` ·
  cmdline `androidboot.hardware=flounder buildvariant=user`.
- The kernel region is `gzip(Image) || DTB || DTB || DTB || DTB` with **no padding
  gap** — the last DTB ends exactly where `kernel_size` ends. The DTBs live inside
  `kernel_size`, which is precisely what hboot scans for.
- `tools/bootimg-repack.py` performs the transplant: it parses the stock header,
  rebuilds the kernel region from a supplied `Image` plus DTBs, rewrites
  `kernel_size`, and leaves the wrapper, header and ramdisk untouched.

## Local 6.19 build (2026-10-16)

- Source `yuka/linux`, branch `flounder`, commit `38ff6862` (shallow clone).
- Built exactly as the pmOS recipe does — `make ARCH=arm64 LLVM=1` with clang 23.1.1
  and LLD — using the port's own `config-htc-flounder.aarch64` as
  `arch/arm64/configs/flounder_defconfig`.
- Result: `Image` 20,371,464 bytes, banner
  `Linux version 6.19.0-htc-flounder-g38ff68627120-dirty`, 2,480 objects.
- Packaged as `boot-lte-6.19.img` (10,885,376 bytes) — stock wrapper, stock header,
  stock ramdisk (sha256 unchanged), gzip kernel + the LTE DTB at `0x8ba03a`.
- The built DTB was verified to carry `google,flounder64_lte` and to have **no**
  `hw-revision` at the root, which is what makes the gate accept it.

## Display and GPU: what the port's config actually does

Measured from the current `config-htc-flounder.aarch64` (220 KB, 6.19-era):

- `# CONFIG_TEGRA_HOST1X is not set` — the display controller stack is not built.
- `# CONFIG_DRM_TEGRA is not set` — the Tegra DRM driver is not built.
- `# CONFIG_DRM_SIMPLEDRM is not set` — not even DRM over the bootloader framebuffer.
- `CONFIG_FB_SIMPLE=y` with `CONFIG_FRAMEBUFFER_CONSOLE=y` — the screen is driven by
  the *legacy* fbdev path over the `simple-framebuffer` the bootloader leaves behind.
- `CONFIG_DRM_NOUVEAU=m` — the 3D driver **is** built, but as a module, so it is
  absent from an `Image`-only build.

So "screen: partial" is a configuration choice plus a missing driver, not a hardware
limit. There is no DRM/KMS display path at all, and therefore no DRM device for
nouveau's PRIME to present through.

- The device tree already declares the hardware: `nvidia,tegra132-dsi` on both DSI
  controllers in ganged mode, two `panel@0` nodes with
  `compatible = "jdi,lpm089a128a"`, `nvidia,tegra124-dc`, and `nvidia,gk20a`.
- **No driver anywhere in the tree matches `jdi,lpm089a128a`.** The nearest is
  `panel-jdi-lpm102a188a.c`, a different JDI panel. Counted across the whole 6.19
  tree, the string `lpm089` appears only in the flounder DTS.
- nouveau does support GK20A — `nvkm/engine/gr/gk20a.c`, `ctxgk20a.c`, `gk20a_fifo`,
  `gk20a_clk`, `gk20a_devfreq`, and a `nvidia,gk20a` platform binding.
- All eight firmware blobs it needs are present in linux-firmware on this machine:
  `nvidia/gk20a/{fecs,gpccs}_{data,inst}.bin`, `sw_bundle_init.bin`, `sw_ctx.bin`,
  `sw_method_init.bin`, `sw_nonctx.bin`.
