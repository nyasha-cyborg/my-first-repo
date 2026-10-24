#!/usr/bin/env python3
"""Recover "addr type name" kallsyms from a raw arm64 kernel Image without a running kernel.

usage: python3 -I kallsyms-decode.py Image out.txt [addr_table_offset count]
  defaults: the LineageOS 16 flounder kernel (boot-backup-lineage16.img): 11312640, 71795 entries
Layout (3.10-era, absolute addresses): kallsyms_addresses[n] u64, kallsyms_num_syms (u64, after
padding), kallsyms_names (len byte + token indexes per symbol; 256-aligned here), kallsyms_markers
(u64 per 256 symbols), kallsyms_token_table (256 NUL-terminated strings), kallsyms_token_index
(256 u16). The first char of each decoded name is the symbol type. Output feeds tools/image2elf.py.
"""
import struct
import sys

img, out = sys.argv[1:3]
off = int(sys.argv[3]) if len(sys.argv) > 3 else 11312640
n = int(sys.argv[4]) if len(sys.argv) > 4 else 71795
d = open(img, "rb").read()
addrs = struct.unpack_from("<%dQ" % n, d, off)
if not all(addrs[i] <= addrs[i + 1] for i in range(n - 1)):
    sys.exit("no sorted address table at %d" % off)

p = off + 8 * n
while struct.unpack_from("<Q", d, p)[0] != n:
    p += 8
    if p > off + 8 * n + 4096:
        sys.exit("kallsyms_num_syms not found")


def walk(s, k):
    for _ in range(k):
        s += 1 + d[s]
    return s


# token_index: 256 increasing u16 starting at 0, a few MB after num_syms
nm = (n + 255) // 256
for q in range(p, p + 4_000_000, 8):
    idx = struct.unpack_from("<256H", d, q)
    if idx[0] == 0 and idx[255] < 8000 and all(idx[i] < idx[i + 1] for i in range(255)):
        e = q
        while d[e - 1] == 0:
            e -= 1
        last = e - (d.rindex(b"\0", 0, e) + 1)
        table = e - last - idx[255]
        if all(d[table + idx[i] - 1] == 0 for i in range(1, 256)):
            break
else:
    sys.exit("kallsyms_token_index not found")
tokens = [d[table + idx[i]:].split(b"\0", 1)[0].decode("latin1") for i in range(256)]

# markers end just before the token table; names start where the markers say
for ms in range(table - 8 * nm - 256, table - 8 * nm + 8, 8):
    markers = struct.unpack_from("<%dQ" % nm, d, ms)
    if markers[0] == 0 and all(markers[i] < markers[i + 1] for i in range(nm - 1)):
        break
else:
    sys.exit("kallsyms_markers not found")
for names in range(p + 8, p + 8 + 4096):
    if d[names] and walk(names, 256) == names + markers[1] and walk(names, 512) == names + markers[2]:
        break
else:
    sys.exit("kallsyms_names not found")

q = names
with open(out, "w") as f:
    for a in addrs:
        ln = d[q]
        s = "".join(tokens[b] for b in d[q + 1:q + 1 + ln])
        q += 1 + ln
        f.write("%016x %s %s\n" % (a, s[0], s[1:]))
print("%d symbols: names %d, markers %d, token table %d" % (n, names, ms, table))
