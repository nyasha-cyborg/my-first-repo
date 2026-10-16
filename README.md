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

**That looks right, and it is what the patch does.** Each stock boot image carries
the *same set of four* device trees — one per board revision, including an LTE one
that already says `google,flounder64_lte` — so the set itself does not tell the two
variants apart; the bootloader picks from it by `compatible` and `hw-revision`. A
kernel built from the Wi-Fi tree alone therefore has nothing the LTE bootloader will
accept. See `notes/evidence.md` for the measurements and `notes/projects.md` for
who else has been down this road and where they stopped.

## Layout

```
tools/     read-only extractors for the boot image and its device trees
patches/   the DTS `compatible` change, and the file it was made against
notes/     measured evidence, and the state of the existing porting projects
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

## Where the work actually stands

1. **The four DTBs are now identified.** They are the four downstream board files —
   `xa,xb`, `xc`, `xd,xe,pvt`, and the LTE `xa,xb,xc,xd,pvt` — and both stock images
   ship all four. So the question is not "which DTB" but "does the tree you build
   from carry an LTE-compatible board file".
2. **The DTS change is already known to be necessary, but not sufficient on its own
   terms.** The postmarketOS wiki records the same finding, and the commit it cites
   is a one-line probe by `dcambie` (2023-04-14) that says "Ugly hack — just to check
   if this is really the issue" — the same one-line change as
   `patches/dts-compatible-flounder64-lte.patch`. Nobody followed it up.
3. **Everything else is out of tree.** Upstream Linux has no Nexus 9 device tree at
   all, so any port lives in a personal fork. See `notes/projects.md`.

## Status

Extraction and comparison are done and reproducible, and the existing projects have
been surveyed. The next useful step is to decide whether to carry the LTE fix
locally, or to push it into the fork postmarketOS builds — see `notes/projects.md`
for why that fork is the one that matters.
