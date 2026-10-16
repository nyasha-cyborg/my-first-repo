#!/usr/bin/env python3
"""Read a named property out of a flattened device tree (DTB).

`fdt-scan.py` prints printable runs from a blob, which is enough to spot strings by
eye but misses short values: the Nexus 9's `hw-revision` is `xc` on one board, two
characters, so `strings` never shows it. This parses the structure block properly.

Usage:  python3 -I tools/fdt-prop.py <file.dtb> [property]

With no property name it reads `compatible`, `model` and `hw-revision`, which is
what identifies a Nexus 9 board file.
"""

import struct
import sys

FDT_BEGIN_NODE, FDT_END_NODE, FDT_PROP, FDT_NOP, FDT_END = 1, 2, 3, 4, 9
WANTED = ("compatible", "model", "hw-revision", "chassis")


def read_properties(data):
    """Walk the structure block, yielding (node path, name, raw value)."""
    (magic, _total, off_struct, off_strings, _off_rsvmap, _ver, _last,
     _boot, _size_str, _size_struct) = struct.unpack_from(">10I", data, 0)
    if magic != 0xD00DFEED:
        raise ValueError("not a device tree (bad magic)")

    def cstr(off):
        end = data.index(b"\0", off)
        return data[off:end].decode("ascii", "replace")

    path, offset = [], off_struct
    while True:
        token, = struct.unpack_from(">I", data, offset)
        offset += 4
        if token == FDT_BEGIN_NODE:
            name = cstr(offset)
            offset += (len(name) + 1 + 3) & ~3
            path.append(name)
        elif token == FDT_END_NODE:
            path.pop()
        elif token == FDT_PROP:
            length, nameoff = struct.unpack_from(">II", data, offset)
            offset += 8
            raw = data[offset:offset + length]
            offset += (length + 3) & ~3
            yield "/".join(p for p in path if p), cstr(off_strings + nameoff), raw
        elif token == FDT_END:
            return


def show(raw):
    """Property values are NUL-separated strings, or big-endian cells."""
    if raw and raw[-1] == 0 and all(32 <= b < 127 or b == 0 for b in raw):
        return " ".join(p.decode() for p in raw.split(b"\0") if p)
    count = len(raw) // 4
    if count and count * 4 == len(raw):
        return "<" + " ".join(f"0x{c:x}" for c in struct.unpack(f">{count}I", raw)) + ">"
    return raw.hex()


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    data = open(sys.argv[1], "rb").read()
    wanted = sys.argv[2:] or WANTED
    found = 0
    for node, name, raw in read_properties(data):
        if name in wanted:
            found += 1
            print(f"  {'/' + node if node else '/'}\t{name} = {show(raw)}")
    if not found:
        print(f"  no {', '.join(wanted)} properties found")


if __name__ == "__main__":
    main()
