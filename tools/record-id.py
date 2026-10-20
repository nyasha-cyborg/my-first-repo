#!/usr/bin/env python3
"""Print an identity for a pulled N9LOG2 record: the build stamp it carries
and a hash of the record text only (not the raw read window, whose tail
can change between reads without a new record being written).

Usage: python3 -I record-id.py <record.bin>
Output: "<build|none> <sha256-prefix>", or "invalid" if not a record.
"""
import hashlib
import re
import struct
import sys

d = open(sys.argv[1], "rb").read()
if d[:7] != b"N9LOG2\n":
    print("invalid")
    sys.exit(0)
length, _flags = struct.unpack_from("<qq", d, 7)
text = d[23:23 + length]
m = re.findall(rb"n9bt: start build (\d+)", text)
build = m[-1].decode() if m else "none"
print(build, hashlib.sha256(text).hexdigest()[:16])
