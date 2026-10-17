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
notes/     measured evidence, the porting projects, the panel, the display port,
           audio, bluetooth, the ROM's system and vendor partitions, the
           device-tree schema check, and a rehearsed flash plan
```

| Tool | What it does |
|---|---|
| `bootimg-split.py` | parses the legacy `ANDROID!` image; emits kernel / ramdisk / second with sizes and SHA-256s |
| `fdt-scan.py` | finds embedded device trees by the `d00dfeed` magic |
| `fdt-prop.py` | parses the FDT structure block for `compatible`, `model`, `hw-revision` |
| `bootimg-repack.py` | transplants a kernel and DTB into a stock boot image, preserving the wrapper, header and ramdisk |
| `ota-image.py` | replays an OTA's `transfer.list` and `new.dat` into a raw partition image, which is what makes the ROM's system and vendor files readable |

## Building a flashable boot image

The kernel is `yuka/linux`, branch `flounder`, commit `38ff6862` — the fork the
postmarketOS kernel package pins to. It is a **build input, not tracked here**;
see [`SOURCES.md`](SOURCES.md) for its provenance and licence. `setup.sh` clones
it, pins it to that commit, applies `patches/` and installs
`configs/flounder_defconfig`, so this repository reproduces the tree on its own.
It builds with **clang, not GCC**, exactly as that package does:

```sh
./setup.sh                 # creates ./linux-flounder and ./linux-flounder-out

make -C linux-flounder O=$PWD/linux-flounder-out ARCH=arm64 LLVM=1 -j"$(nproc)" dtbs Image

python3 -I tools/bootimg-repack.py \
    --stock ~/Downloads/nexus9/extract-lte/boot.img \
    --image linux-flounder-out/arch/arm64/boot/Image \
    --dtb   linux-flounder-out/arch/arm64/boot/dts/nvidia/tegra132-flounder.dtb \
    --append-cmdline "console=tty0" \
    -o boot-lte.img
```

`configs/flounder_defconfig` is a snapshot of that same postmarketOS config,
kept here so the build does not depend on a URL that can move under it. Refresh
it from the pmaports path recorded in `SOURCES.md` when upstream changes.

Build `dtbs` alone after a device-tree change — it takes seconds, whereas
`Image` rebuilds the kernel.

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
  it. The nearest driver in the tree is a *different* JDI panel. The sequences,
  timings and power order a driver needs are now extracted — see
  [`notes/panel.md`](notes/panel.md) — and `panel-jdi-lpm102a188a.c` is the closest
  template in the tree.
- 3D is the more encouraging part: nouveau does support `nvidia,gk20a`, and all
  eight firmware blobs it needs ship in linux-firmware. But the GPU has no display
  hardware of its own, so nouveau runs as a render node and needs a working DRM
  display to present through.

So the ladder is: get *a* DRM device → write the panel driver for real
mode-setting and backlight → nouveau plus PRIME for hardware 3D.

A panel driver is now written and the whole display stack builds — see
[`notes/display-port.md`](notes/display-port.md) for the driver, the device tree
and kernel config changes it needs, and the two-image arrangement that keeps a
working console available while it is proven. None of it has run on hardware yet.

## Where the work actually stands

1. **The gate is proven, not inferred** — read out of `hboot.img` itself, committed.
2. **The kernel builds and a boot image exists** — `6.19.0-htc-flounder`, built with
   clang, packaged as a boot image carrying the LTE device tree. It has not yet been
   flashed to hardware.
3. **Everything else is out of tree.** Upstream Linux has no Nexus 9 device tree at
   all, so every port lives in a personal fork. See `notes/projects.md`.
4. **Audio is written but unproven.** Two cards, because flounder plays through two
   independent paths: the `rt5677` on `tegra_i2s1` for headphones and mics, and two
   `tfa9895` amplifiers on `tegra_i2s2` for the speakers. The second needed a machine
   driver, since no generic card driver puts two codecs on one link and both bindings
   involved refuse graph nodes. See `notes/audio.md`.
5. **Bluetooth is written but unproven**, and no longer firmware-blocked — the
   firmware turned out to be in the ROM. See `notes/bluetooth.md`.
6. **The device tree now checks against the bindings**, which it did not before: the
   audio, bluetooth, serial and DSI schemas all pass. That check found real errors
   that a clean `dtbs` build had hidden. See `notes/schema-check.md`.

## Where the work is blocked

- **The tablet does not enumerate on USB.** Power arrives — the LED blinks — but
  there is no bus activity at all, which is the signature of a charge-only or
  damaged cable. The test that settles it, using the same cable with a different
  device that needs data, has not been run.
- **Headphones need a driver mainline does not have.** The `rt5506` is the headphone
  output stage, and its tuning lives in `/etc/RT5506` in the ROM — as a plain text
  register table, which makes that driver a transcription job rather than a
  reverse-engineering one.
- **The speaker amplifiers give up their shipped tuning**, which came from the
  Android HAL over ioctl.

## Status

Extraction, comparison and the bootloader analysis are done and reproducible; the
existing porting projects have been surveyed; the kernel builds. The audio and
Bluetooth device trees are written and the whole tree checks against the bindings.
The ROM's system and vendor partitions have been opened, which is where the
Bluetooth firmware and the headphone amplifier's register table turned out to live.

**Nothing has run on hardware.** Every driver described here has been written,
built and audited against its source, and none of it has bound to a device. The one
claim with strong evidence behind it is the boot gate; treat the rest as prepared
experiments.

The next step needs the tablet itself: charge it, boot it, dump its current boot
partition, then flash the built image and see whether the bootloader accepts it.
