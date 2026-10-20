#!/usr/bin/env python3
"""Replace the ramdisk of a stripped (wrapper-less) legacy Android boot image.

Usage: python3 -I bootimg-swap-ramdisk.py <in.img> <ramdisk.gz> <out.img> [kernel-region]

Keeps header and cmdline; rewrites ramdisk_size (offset 16) and appends the
new ramdisk page-aligned.  With a kernel-region file (gzip(Image)||dtb) the
kernel is replaced too and kernel_size (offset 8) updated.
"""
import struct
import sys

MAGIC = b"ANDROID!"


def main():
    if len(sys.argv) not in (4, 5):
        sys.exit(__doc__)
    src, rd, dst = sys.argv[1:4]
    data = bytearray(open(src, "rb").read())
    if data[:8] != MAGIC:
        sys.exit(f"{src}: not a stripped boot image (starts {data[:4].hex()})")
    ksize, _, rsize, _, _, _, _, page = struct.unpack_from("<8I", data, 8)
    pad = lambda n: -(-n // page) * page
    kern = open(sys.argv[4], "rb").read() if len(sys.argv) == 5 else None
    if kern is None:
        kern = bytes(data[page:page + ksize])
    else:
        struct.pack_into("<I", data, 8, len(kern))
        ksize = len(kern)
    kern += b"\0" * (pad(ksize) - ksize)
    new = open(rd, "rb").read()
    struct.pack_into("<I", data, 16, len(new))
    out = bytes(data[:page]) + kern + new + b"\0" * (pad(len(new)) - len(new))
    open(dst, "wb").write(out)
    print(f"{dst}: ramdisk {rsize} -> {len(new)} bytes, total {len(out)}")


if __name__ == "__main__":
    main()
