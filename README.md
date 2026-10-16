# nexus9 — Nexus 9 (`flounder`) boot-image forensics

The Nexus 9 is one board family sold in two variants:

| Variant | Codename | Android 7.1.1 | Boot image |
|---|---|---|---|
| Wi-Fi | `volantis` | N4F27B | `extract-wifi/boot.img` |
| LTE | `volantisg` | N4F27P | `extract-lte/boot.img` |

Both run the same SoC (Tegra 132, `nvidia,tegra132`) and the same stock kernel
version (`3.10.103`), which is why it looks like one variant's kernel ought to boot
on the other's hardware.

The hypothesis this branch started from: the bootloader picks a device tree by the
board's `compatible` string, so a kernel whose DTS says `google,flounder64` is
rejected on LTE hardware, which wants `google,flounder64_lte`. That is what
`patches/dts-compatible-flounder64-lte.patch` changes.

**The measurements do not support it.** Both stock boot images ship the *same*
device trees — including one that already says `google,flounder64_lte` — so the
device tree is not what distinguishes the variants. The difference is in the
kernel build. See `notes/evidence.md`.

## Layout

```
tools/     read-only extractors for the boot image and its device trees
patches/   the DTS `compatible` hypothesis, kept as a record
notes/     measured evidence taken from the two stock images
```

## Data

The ROMs and extracted trees are ~1.6 GB and are deliberately **not** tracked in
git (see `.gitignore`). They live in `~/Downloads/nexus9`:

| Path | What |
|---|---|
| `roms/volantis-ota-n4f27b.zip` | Wi-Fi OTA, 817 MB |
| `roms/volantisg-ota-n4f27p.zip` | LTE OTA, 847 MB |
| `extract-wifi/`, `extract-lte/` | `boot.img`, `bootloader.img`, split parts, `fdt/` |
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

`bootimg-split.py` parses the legacy `ANDROID!` (header v0) boot image and writes
kernel / ramdisk / second out with sizes and SHA-256s, so two images can be compared
directly. `fdt-scan.py` finds embedded flattened device trees by the `d00dfeed`
magic and prints their early strings, which is where `compatible` and `hw-revision`
live.

## Answering the original question

1. **Diff the two kernel configs.** They are the same version but different commits
   (`gfa7d4389a60` LTE vs `g0a2199e` Wi-Fi) built six months apart. The kernel is
   where the variants diverge, so that is where the LTE/Wi-Fi difference has to be.
2. **Work out what the four DTBs in each image are for.** They are distinct builds
   of slightly different size, the bootloader picks one of them, and the set is
   identical across both variants — which is itself the evidence against the DTS
   patch being the answer.
3. **Only then** decide whether a DTS change is needed at all, and if so for
   *mainline* boot rather than for the stock images.

## Status

Extraction and comparison are done and reproducible. The kernel-config comparison
(step 1) is the next piece of work.
