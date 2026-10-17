#!/usr/bin/env python3
"""Reconstruct a raw partition image from an Android block-OTA payload.

This is what makes a stock OTA's files readable at all. An OTA carries each
partition as `<part>.new.dat` — the file *contents*, concatenated in one order
with no filenames — plus a `<part>.transfer.list` saying where in the partition
each run of blocks belongs. Without replaying that, the payload is an
undifferentiated 1.5 GB blob.

The transfer.list version 4 format is named, one command per line:

    new   <n>, <start>,<end>, <start>,<end>, ...   half-open [start, end) ranges
    zero  <n>, <block>, <block>, ...               individual blocks to zero
    erase <n>, <block>, <block>, ...               ditto

`<n>` is the number of values following the command, so for `new` it is twice
the number of ranges. Data for the `new` ranges is read from the `.new.dat`
strictly sequentially, in the order the ranges are listed — the mapping is
positional, which is why the order matters and why the block numbers are not
necessarily ascending.

The half-open reading of `new` ranges is checked rather than assumed: the counts
are asserted against the payload size, and a mismatch is a hard error. With
[end] treated as inclusive the same payload overshoots by exactly the number of
ranges, so getting this wrong fails loudly.

Usage:
    ota-image.py <part>.transfer.list <part>.new.dat <out.img>

Then read it without mounting, which needs no privileges:

    debugfs -R "ls -l /" <out.img>
    debugfs -R "dump /etc/hosts hosts" <out.img>
"""

import os
import sys

BLOCK = 4096


def parse(transfer_list):
    lines = [l.strip() for l in open(transfer_list) if l.strip()]
    if lines[0] != "4":
        raise SystemExit("unsupported transfer.list version: " + lines[0])
    declared = int(lines[1])
    body = lines[4:]          # 4, total blocks, two further header numbers

    new_ranges, zero_blocks = [], []
    for line in body:
        parts = line.replace(",", " ").split()
        cmd, values = parts[0], [int(v) for v in parts[1:]]
        if not values or values[0] != len(values) - 1:
            raise SystemExit("bad count in: " + line[:60])
        rest = values[1:]

        if cmd == "new":
            if len(rest) % 2:
                raise SystemExit("odd value count in: " + line[:60])
            for i in range(0, len(rest), 2):
                new_ranges.append((rest[i], rest[i + 1]))
        elif cmd in ("zero", "erase"):
            zero_blocks.extend(rest)
        else:
            raise SystemExit("unknown command: " + cmd)

    return declared, new_ranges, zero_blocks


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__.strip().splitlines()[-4])
    transfer_list, new_dat, out_path = sys.argv[1:4]

    declared, new_ranges, zero_blocks = parse(transfer_list)

    highest = max([end for _, end in new_ranges] + zero_blocks)
    size = highest * BLOCK

    produced = sum(e - s for s, e in new_ranges)
    expected = os.path.getsize(new_dat) // BLOCK
    if produced != expected:
        raise SystemExit(
            "range total %d does not match payload %d blocks" % (produced, expected)
        )

    print("blocks declared %d, ranges %d, zero/erase blocks %d"
          % (declared, len(new_ranges), len(zero_blocks)))
    print("image %d blocks = %.1f MB, payload %d blocks"
          % (highest, size / 1e6, expected))

    # Sparse, so the untouched blocks cost no disk before they must.
    with open(new_dat, "rb") as src, open(out_path, "wb") as dst:
        dst.truncate(size)
        for start, end in new_ranges:
            dst.seek(start * BLOCK)
            remaining = (end - start) * BLOCK
            while remaining:
                chunk = src.read(min(1 << 22, remaining))
                if not chunk:
                    raise SystemExit("payload exhausted early")
                dst.write(chunk)
                remaining -= len(chunk)
        if src.read(1):
            raise SystemExit("payload has bytes left over")
        dst.flush()
        os.fsync(dst.fileno())

    print("wrote " + out_path)


if __name__ == "__main__":
    main()
