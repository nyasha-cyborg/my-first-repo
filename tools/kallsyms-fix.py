#!/usr/bin/env python3
"""Rebuild real symbol addresses for the stock Android kernel (kptr_restrict hides them in /proc/kallsyms).

usage: python3 -I kallsyms-fix.py Image proc-kallsyms.txt out.txt [table_offset] [count]
  Image             raw arm64 kernel (gunzip of the boot image's kernel region; trailing DTB is ignored)
  proc-kallsyms.txt `adb shell cat /proc/kallsyms` from the running Android kernel (addresses zeroed)
  table_offset/count: the kernel's kallsyms_addresses table in the Image (defaults: the LineageOS 16
                    flounder kernel, sha256 b26351cb... boot image: 11312640, 71795 entries; notes/stability-debug.md)
The i-th core-kernel line of /proc/kallsyms (module symbols excluded) gets the i-th u64 of the table.
Output: "addr type name" lines usable by tools/image2elf.py.
"""
import struct
import sys

img, kall, out = sys.argv[1:4]
off = int(sys.argv[4]) if len(sys.argv) > 4 else 11312640
n = int(sys.argv[5]) if len(sys.argv) > 5 else 71795
data = open(img, "rb").read()
addrs = struct.unpack_from("<%dQ" % n, data, off)
if not all(addrs[i] <= addrs[i + 1] for i in range(n - 1)) or not (addrs[0] >> 40) == 0xffffff:
    sys.exit("no sorted kernel address table at offset %d" % off)
lines = [l.split() for l in open(kall, errors="replace") if l.strip()]
core = [l for l in lines if len(l) >= 3 and not (len(l) > 3 and l[3].startswith("["))]
if len(core) != n:
    print("warning: %d core symbols in /proc/kallsyms vs %d table entries" % (len(core), n), file=sys.stderr)
with open(out, "w") as f:
    for a, l in zip(addrs, core):
        f.write("%016x %s %s\n" % (a, l[1], l[2]))
print("%d symbols, %016x .. %016x" % (min(n, len(core)), addrs[0], addrs[-1]))
