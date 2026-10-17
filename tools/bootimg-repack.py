#!/usr/bin/env python3
"""Transplant a kernel (and appended DTB) into a stock Nexus 9 boot image.

The flounder boot image is NOT the modern AOSP format. Its header is the older
layout, where the 32-byte `id` field was still `name[16]` and the command line
sits at +0x40 instead of +0x50. Modern mkbootimg emits the new layout, which
hboot would parse differently -- so instead of building a header from scratch
we keep the stock one verbatim and replace only the kernel region.

Stock layout (measured, see notes/evidence.md):

    0x000  HTC wrapper, 256 bytes, magic 78 56 34 12
    0x100  ANDROID! header, one page (page_size, 2048)
    0x900  kernel region, kernel_size bytes =
               gzip(Image) || dtb [|| dtb ...]      <- "appended FDT"
           page-aligned
           ramdisk, ramdisk_size bytes

hboot finds the device tree by scanning the kernel region for the FDT magic
0xd00dfeed, so the DTB must be appended inside kernel_size -- not in the
header's dt_size area (which is 0 here).
"""

import argparse
import gzip
import os
import struct
import sys

FDT_MAGIC = b"\xd0\x0d\xfe\xed"
ANDROID_MAGIC = b"ANDROID!"
HTC_WRAPPER_MAGIC = b"\x78\x56\x34\x12"


def round_up(value, align):
    return (value + align - 1) // align * align


def parse_stock(path):
    blob = open(path, "rb").read()

    if blob[:4] == HTC_WRAPPER_MAGIC:
        wrapper_len = 0x100
    else:
        wrapper_len = 0
        print("warning: no HTC wrapper found; assuming a bare ANDROID! image")

    header_off = wrapper_len
    if blob[header_off : header_off + 8] != ANDROID_MAGIC:
        sys.exit(f"error: no ANDROID! magic at 0x{header_off:x}")

    kernel_size = struct.unpack_from("<I", blob, header_off + 0x08)[0]
    ramdisk_size = struct.unpack_from("<I", blob, header_off + 0x10)[0]
    page_size = struct.unpack_from("<I", blob, header_off + 0x24)[0]
    dt_size = struct.unpack_from("<I", blob, header_off + 0x28)[0]
    cmdline = (
        blob[header_off + 0x40 : header_off + 0x40 + 512].split(b"\0")[0].decode()
    )

    kernel_off = header_off + page_size
    ramdisk_off = kernel_off + round_up(kernel_size, page_size)

    return {
        "blob": blob,
        "wrapper_len": wrapper_len,
        "header_off": header_off,
        "page_size": page_size,
        "kernel_size": kernel_size,
        "kernel_off": kernel_off,
        "ramdisk_off": ramdisk_off,
        "ramdisk_size": ramdisk_size,
        "dt_size": dt_size,
        "cmdline": cmdline,
    }


def build_kernel_region(image_path, dtb_paths, level=9):
    """gzip(Image), then the DTBs appended -- the layout hboot scans for."""
    raw = open(image_path, "rb").read()
    if raw[:2] != b"\x1f\x8b":
        # a bare arm64 Image; gzip it with mtime=0 so the output is reproducible
        gz = gzip.compress(raw, compresslevel=level, mtime=0)
    else:
        gz = raw
        print("note: kernel input is already gzip-compressed; using as-is")

    region = bytearray(gz)
    for dtb_path in dtb_paths:
        dtb = open(dtb_path, "rb").read()
        if dtb[:4] != FDT_MAGIC:
            sys.exit(f"error: {dtb_path} does not start with the FDT magic")
        region += dtb
    return bytes(region), len(gz)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--stock", required=True, help="stock boot.img to transplant into")
    ap.add_argument("--image", required=True, help="kernel Image (raw or already gzipped)")
    ap.add_argument("--dtb", action="append", default=[], help="DTB to append (repeatable)")
    ap.add_argument("--append-cmdline", default="", help="extra cmdline tokens")
    ap.add_argument("--ramdisk",
                    help="replacement ramdisk; default is to keep the stock one")
    ap.add_argument("-o", "--output", required=True)
    args = ap.parse_args()

    st = parse_stock(args.stock)
    page = st["page_size"]
    if page not in (2048, 4096, 8192, 16384):
        sys.exit(f"error: unexpected page_size {page}")

    print(f"stock : {args.stock}")
    print(f"  wrapper      : {st['wrapper_len']} bytes")
    print(f"  page_size    : {page}")
    print(f"  kernel_size  : {st['kernel_size']:,}")
    print(f"  ramdisk_size : {st['ramdisk_size']:,}")
    print(f"  dt_size      : {st['dt_size']}  (0 = DTBs live in the kernel region)")
    print(f"  cmdline      : {st['cmdline']!r}")

    region, gz_len = build_kernel_region(args.image, args.dtb)
    print(f"\nnew kernel region: gzip {gz_len:,} + dtbs "
          f"{len(region) - gz_len:,} = {len(region):,} bytes")

    # ---- rebuild: wrapper + header + new kernel region + untouched ramdisk ----
    out = bytearray()
    out += st["blob"][: st["header_off"]]                    # HTC wrapper
    header = bytearray(st["blob"][st["header_off"] : st["header_off"] + page])
    struct.pack_into("<I", header, 0x08, len(region))        # kernel_size

    if args.append_cmdline:
        new_cmd = (st["cmdline"] + " " + args.append_cmdline).strip()
        enc = new_cmd.encode()
        if len(enc) > 511:
            sys.exit("error: cmdline does not fit in 512 bytes")
        header[0x40 : 0x40 + 512] = b"\0" * 512
        header[0x40 : 0x40 + len(enc)] = enc
        print(f"cmdline      : {new_cmd!r}")

    # Read the replacement ramdisk *before* assembling the image. An earlier
    # version patched ramdisk_size into the header afterwards using
    # `len(out) - len(header)` as the offset, which by then pointed at the last
    # 2048 bytes of the appended DTB rather than at the header. That silently
    # overwrote the DTB's string table with the boot header -- properties such
    # as bus-width and #nvidia,mipi-calibrate-cells disappeared, nodes came out
    # duplicated, and DSI failed to probe. The header is now final before it is
    # appended, so there is nothing to patch in place.
    if args.ramdisk:
        with open(args.ramdisk, "rb") as fh:
            rd = fh.read()
        struct.pack_into("<I", header, 0x10, len(rd))         # ramdisk_size
        print(f"ramdisk      : {len(rd):,} bytes from {args.ramdisk}")
    else:
        rd = st["blob"][st["ramdisk_off"] : st["ramdisk_off"] + st["ramdisk_size"]]
        if len(rd) != st["ramdisk_size"]:
            sys.exit("error: stock ramdisk is truncated")

    out += header

    out += region
    out += b"\0" * (round_up(len(region), page) - len(region))

    out += rd
    out += b"\0" * (round_up(len(rd), page) - len(rd))

    # sanity: every DTB must survive inside kernel_size
    if out.count(FDT_MAGIC) < len(args.dtb) and args.dtb:
        sys.exit("error: appended DTB missing from the rebuilt image")

    with open(args.output, "wb") as fh:
        fh.write(out)
    print(f"\nwrote {args.output} ({len(out):,} bytes)")

    # Every DTB must be present byte-for-byte. Counting FDT magics is not
    # enough -- the bug that motivated this check replaced a DTB's tail with
    # the boot header and left the magic perfectly intact.
    for dtb_path in args.dtb:
        with open(dtb_path, "rb") as fh:
            src = fh.read()
        if src not in out:
            sys.exit(f"error: {dtb_path} did not survive the rebuild intact")

    # round-trip check through the same parser the project already uses
    chk = parse_stock(args.output)
    print(f"reparse: kernel_size={chk['kernel_size']:,} "
          f"ramdisk_off=0x{chk['ramdisk_off']:x} "
          f"file={os.path.getsize(args.output):,}")


if __name__ == "__main__":
    main()
