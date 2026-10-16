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

The four entries are different sizes, so they are genuinely four builds rather than
copies; the `hw-revision` values differ between them, so the set looks like per
board-revision device trees that the bootloader picks from. **Which revision maps to
which entry is not yet established.**

The point that matters: an LTE boot image already carries a `google,flounder64_lte`
device tree, and a Wi-Fi boot image carries exactly the same one. Editing a DTS
`compatible` string therefore does not explain why one variant's kernel would refuse
to come up on the other's hardware.

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
