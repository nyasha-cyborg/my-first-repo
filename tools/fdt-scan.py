#!/usr/bin/env python3
"""Scan an Android boot image for embedded Flattened Device Tree (FDT) blobs.

A DTB starts with the magic d00dfeed; bytes 4-7 are its total size, big-endian.

Usage:  python3 -I nexus9-fdt-scan.py <boot.img> [output-dir]

Extracts each DTB found and prints the early strings (model / compatible),
which is where the bootloader's model gate is decided. Read-only otherwise.
"""

import os
import struct
import sys

FDT_MAGIC = b"\xd0\x0d\xfe\xed"
# bytes that should follow a plausible DTB header: version (0x11+) and
# last_comp_version 0x10, big-endian, at offsets 20 and 24
HEADER_TAIL = 20


def plausible(data, off):
    if len(data) < off + 40:
        return None
    total, = struct.unpack_from(">I", data, off + 4)
    version, = struct.unpack_from(">I", data, off + 20)
    if not (0 < total <= len(data) - off):
        return None
    if not (0x10 <= version <= 0x20):
        return None
    return total


def early_strings(blob, limit=600):
    """Printable runs from the first `limit` bytes: model/compatible live there."""
    out, cur = [], bytearray()
    for byte in blob[:limit]:
        if 32 <= byte < 127:
            cur.append(byte)
        else:
            if len(cur) >= 4:
                out.append(cur.decode("ascii"))
            cur = bytearray()
    if len(cur) >= 4:
        out.append(cur.decode("ascii"))
    return out


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    img = sys.argv[1]
    outdir = sys.argv[2] if len(sys.argv) > 2 else "."
    data = open(img, "rb").read()
    os.makedirs(outdir, exist_ok=True)

    print(f"{img}: {len(data)} bytes")
    found = 0
    start = 0
    while True:
        off = data.find(FDT_MAGIC, start)
        if off < 0:
            break
        start = off + 4
        total = plausible(data, off)
        if total is None:
            print(f"  {off:#x}: magic without a valid header — skipping")
            continue
        found += 1
        blob = data[off:off + total]
        path = os.path.join(outdir, f"fdt-{off:#x}.dtb")
        with open(path, "wb") as fh:
            fh.write(blob)
        print(f"  #{found} offset={off:#x} size={total} → {path}")
        for s in early_strings(blob):
            print(f"        {s}")
    print(f"found {found} DTB candidate(s)")


if __name__ == "__main__":
    main()
