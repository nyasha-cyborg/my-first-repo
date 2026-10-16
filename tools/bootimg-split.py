#!/usr/bin/env python3
"""Split a legacy Android boot image into its kernel / ramdisk / second parts.

Reads the old ("v0") boot image header — magic "ANDROID!", then eight
little-endian uint32s — and writes each component out, printing its size and
hash so two boot images can be compared directly.

Usage:  python3 -I nexus9-bootimg-split.py <boot.img> <output-dir>
"""

import hashlib
import os
import struct
import sys

MAGIC = b"ANDROID!"


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    img, outdir = sys.argv[1], sys.argv[2]
    data = open(img, "rb").read()
    base = data.find(MAGIC)
    if base < 0:
        sys.exit(f"{img}: no ANDROID! boot header found")
    if base:
        print(f"{img}: {base}-byte wrapper before the boot header "
              f"(leading magic {data[:4].hex()}) — skipping it")

    (k_size, k_addr, r_size, r_addr,
     s_size, s_addr, tags, page) = struct.unpack_from("<8I", data, base + 8)

    # the kernel command line sits after the 16-byte product name
    cmdline = (data[base + 64:base + 64 + 512]
               .split(b"\x00")[0].decode("ascii", "ignore"))
    print(f"{img}  ({len(data)} bytes)")
    print(f"  page={page} kernel={k_size} ramdisk={r_size} second={s_size}")
    print(f"  cmdline: {cmdline}")

    os.makedirs(outdir, exist_ok=True)

    def round_up(n):
        return (n + page - 1) // page * page

    offset = base + page               # first page holds the boot header
    for name, size in (("kernel", k_size), ("ramdisk", r_size),
                       ("second", s_size)):
        if size:
            blob = data[offset:offset + size]
            path = os.path.join(outdir, name)
            with open(path, "wb") as fh:
                fh.write(blob)
            print(f"  {name:8} {size:>9} bytes  sha256={hashlib.sha256(blob).hexdigest()}  "
                  f"magic={blob[:4].hex()}")
        offset += round_up(size)


if __name__ == "__main__":
    main()
