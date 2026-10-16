# nexus9 — Nexus 9 (`flounder`) boot-image forensics

The Nexus 9 is one board family sold in two variants:

| Variant | Codename | Android 7.1.1 | Boot image |
|---|---|---|---|
| Wi-Fi | `volantis` | N4F27B | `extract-wifi/boot.img` |
| LTE | `volantisg` | N4F27P | `extract-lte/boot.img` |

Both run the same SoC (Tegra 132, `nvidia,tegra132`) and the same stock kernel
version (`3.10.103`), which is why it looks like one variant's kernel ought to boot
on the other's hardware.

## The question, and the answer

**Why won't Linux boot on an LTE Nexus 9?** Because `hboot`, the bootloader, walks
the device trees inside `boot.img` and accepts only one whose root `compatible`
property matches the board. An LTE unit wants `google,flounder64_lte`; the mainline
fork's tree says `google,flounder64`, so the bootloader finds nothing acceptable and
the kernel never starts. It prints `Can not find a compatible dtb image` and gives up.

The fix is one line, in `patches/dts-compatible-flounder64-lte.patch`.

Two things make that answer solid rather than a guess:

- Each stock boot image carries the *same four* device trees, byte-for-byte, one per
  board **revision** — including the LTE one. So the set of trees cannot be what
  distinguishes the variants; the bootloader must be choosing between them.
- The choosing logic was then read directly out of `hboot.img`, decompiled from the
  bootloader package. It corroborates the above in its own strings, including both
  compatible values. See `notes/evidence.md` for the measurements.

**What is deliberately not done.** The gate tests `hw-revision` *only when that
property is present*, so a tree that omits it is accepted on `compatible` alone.
Porting the downstream LTE board file would *add* `hw-revision` and thereby arm a
second test that can fail. The minimal patch is both sufficient and safer.

## Layout

```
tools/     boot-image and device-tree tools
patches/   the DTS `compatible` change, and the file it was made against
notes/     measured evidence, and the state of the existing porting projects
```

| Tool | What it does |
|---|---|
| `bootimg-split.py` | parses the legacy `ANDROID!` image; emits kernel / ramdisk / second with sizes and SHA-256s |
| `fdt-scan.py` | finds embedded device trees by the `d00dfeed` magic |
| `fdt-prop.py` | parses the FDT structure block for `compatible`, `model`, `hw-revision` |
| `bootimg-repack.py` | transplants a kernel and DTB into a stock boot image, preserving the wrapper, header and ramdisk |

## Building a flashable boot image

The kernel is `yuka/linux`, branch `flounder`, commit `38ff6862` — the fork the
postmarketOS kernel package pins to. It builds with **clang, not GCC**, exactly as
that package does:

```sh
git clone --branch flounder --single-branch --depth 1 https://cyberchaos.dev/yuka/linux.git
# the port's own config, as arch/arm64/configs/flounder_defconfig:
curl -o arch/arm64/configs/flounder_defconfig \
  https://gitlab.postmarketos.org/postmarketOS/pmaports/-/raw/main/device/testing/linux-htc-flounder/config-htc-flounder.aarch64

make O=out ARCH=arm64 LLVM=1 -j8 flounder_defconfig
make O=out ARCH=arm64 LLVM=1 -j8 dtbs Image

python3 -I tools/bootimg-repack.py \
    --stock ~/Downloads/nexus9/extract-lte/boot.img \
    --image out/arch/arm64/boot/Image \
    --dtb   out/arch/arm64/boot/dts/nvidia/tegra132-flounder.dtb \
    --append-cmdline "console=tty0" \
    -o boot-lte.img
```

The image format is the **legacy HTC layout, not modern AOSP**: the command line
sits at `+0x40` rather than `+0x50`, there is a 256-byte `78 56 34 12` wrapper
before the `ANDROID!` header, and the device trees are appended *inside*
`kernel_size`, after the gzip stream. A modern `mkbootimg` would emit a header
`hboot` parses differently, which is why the stock image is patched rather than
rebuilt from scratch.

## Data

The ROMs and extracted trees are ~1.6 GB and are deliberately **not** tracked in
git (see `.gitignore`). They live in `~/Downloads/nexus9`:

| Path | What |
|---|---|
| `roms/volantis-ota-n4f27b.zip` | Wi-Fi OTA, 817 MB |
| `roms/volantisg-ota-n4f27p.zip` | LTE OTA, 847 MB |
| `extract-wifi/`, `extract-lte/` | `boot.img`, `bootloader.img`, split parts, `fdt/` |
| `hboot-payload/extracted/` | the bootloader package: `hboot.img`, `nvtboot.img`, `tos.img`, `pt_*.img`, `gp1.img` |
| `bootimg-build/` | built boot images, and a stock one kept as the way back |
| `rd-wifi/`, `rd-lte/` | unpacked ramdisks |
| `kernel-wifi.raw`, `kernel-lte.raw` | decompressed 3.10.103 ARM64 kernels |

Keeping derived blobs next to the checkout is fine for a local experiment, but the
point of this branch is that the *method* and the *findings* are what need
versioning, not the megabytes.

## Reproduce

```sh
python3 -I tools/bootimg-split.py ~/Downloads/nexus9/extract-lte/boot.img /tmp/parts-lte
python3 -I tools/fdt-scan.py      ~/Downloads/nexus9/extract-lte/boot.img /tmp/fdt-lte
```

`bootimg-split.py` parses the legacy `ANDROID!` (header v0) image and writes
kernel / ramdisk / second out with sizes and SHA-256s, so two images can be compared
directly. `fdt-scan.py` finds embedded flattened device trees by the `d00dfeed`
magic and prints their early strings, which is where `compatible` and `hw-revision`
live.

The bootloader package is a ZIP behind a 256-byte wrapper, so it needs unwrapping
before its contents are readable at all — a plain `strings` pass over
`bootloader.img` finds nothing, which is what makes the gate look invisible:

```sh
tail -c +257 ~/Downloads/nexus9/extract-lte/bootloader.img > payload.zip
unzip payload.zip -d ~/Downloads/nexus9/hboot-payload/extracted
```

## Graphics: what actually stands in the way

For a tablet that is pleasant to use, display matters more than booting, and here
the position is mixed rather than bad.

- The port builds **no DRM display path whatsoever** — not `TEGRA_HOST1X`, not
  `DRM_TEGRA`, not even `DRM_SIMPLEDRM`. The screen is driven by the legacy fbdev
  driver (`FB_SIMPLE`) painting the framebuffer the bootloader happens to leave.
- **No driver in the tree matches the panel.** The device tree declares
  `compatible = "jdi,lpm089a128a"` on two ganged DSI panel nodes; nothing binds to
  it. The nearest driver in the tree is a *different* JDI panel.
- 3D is the more encouraging part: nouveau does support `nvidia,gk20a`, and all
  eight firmware blobs it needs ship in linux-firmware. But the GPU has no display
  hardware of its own, so nouveau runs as a render node and needs a working DRM
  display to present through.

So the ladder is: get *a* DRM device (`DRM_SIMPLEDRM` is a one-line start, and enough
for a compositor with software rendering) → write the panel driver for real
mode-setting and backlight → nouveau plus PRIME for hardware 3D.

## Where the work actually stands

1. **The gate is proven, not inferred** — read out of `hboot.img` itself, committed.
2. **The kernel builds and a boot image exists** — `6.19.0-htc-flounder`, built with
   clang, packaged as a boot image carrying the LTE device tree. It has not yet been
   flashed to hardware.
3. **Everything else is out of tree.** Upstream Linux has no Nexus 9 device tree at
   all, so every port lives in a personal fork. See `notes/projects.md`.

## Status

Extraction, comparison and the bootloader analysis are done and reproducible; the
existing porting projects have been surveyed; the kernel builds. The next step needs
the tablet itself: charge it, boot it, dump its current boot partition, then flash
the built image and see whether the bootloader accepts it.
