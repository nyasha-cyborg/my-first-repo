#!/usr/bin/env python3
"""Print a rolling record pulled from the DTB partition.

Record layout (see tools/miniroot/init.c):
    "N9LOG2\\n" | u64 text length | u64 flags | text

`flags` is the /proc/uptime seconds at the last write, so it dates the
snapshot relative to that boot.

Usage: python3 -I read-record.py <record.bin> [last-lines]
"""
import struct
import sys

path = sys.argv[1]
last = int(sys.argv[2]) if len(sys.argv) > 2 else 40

d = open(path, "rb").read()
if d[:7] != b"N9LOG2\n":
    sys.exit(f"{path}: not an N9LOG2 record")

length, flags = struct.unpack_from("<qq", d, 7)
text = d[23 : 23 + length].decode("utf-8", "replace")
lines = text.splitlines()

print(f"record: len={length} uptime_at_write={flags}s lines={len(lines)}")
for line in lines[-last:]:
    print(line[:200])
