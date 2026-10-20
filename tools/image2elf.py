#!/usr/bin/env python3
"""Wrap a raw arm64 kernel Image in an ELF64 with a .symtab from kallsyms.

usage: python3 -I image2elf.py Image kallsyms.txt base_hex out.elf [start_hex end_hex]

Used for REA on the running Android kernel: pull LNX + /proc/kallsyms
(kptr_restrict=0), base = _text (0xffffffc000080000 on flounder 3.10),
and pass a window around the functions of interest to keep analysis small.
"""
import struct
import sys

full = open(sys.argv[1], "rb").read()
kbase = int(sys.argv[3], 16)
# optional window: start_hex end_hex (virtual), to keep analysis small
if len(sys.argv) > 6:
    ws, we = int(sys.argv[5], 16), int(sys.argv[6], 16)
    img = full[ws - kbase:we - kbase]
    base = ws
    sys.argv[4] = sys.argv[4]
else:
    img = full
    base = kbase
end = base + len(img)

syms = []
for line in open(sys.argv[2]):
    p = line.split()
    if len(p) < 3:
        continue
    addr = int(p[0], 16)
    if not (base <= addr < end):
        continue
    kind = p[1]
    func = kind in "tTwW"
    glob = kind.isupper()
    syms.append((p[2], addr, func, glob))
syms.sort(key=lambda s: s[1])

# string table
strtab = b"\0"
offs = []
for name, *_ in syms:
    offs.append(len(strtab))
    strtab += name.encode() + b"\0"

shstr = b"\0.text\0.symtab\0.strtab\0.shstrtab\0"
SH_TEXT, SH_SYM, SH_STR, SH_SHSTR = 1, 7, 15, 23

# symbols: null + locals first, then globals (ELF requires locals first)
order = sorted(range(len(syms)), key=lambda i: syms[i][3])
symtab = b"\0" * 24
nlocal = 1
for i in order:
    name, addr, func, glob = syms[i]
    if not glob:
        nlocal += 1
    info = ((1 if glob else 0) << 4) | (2 if func else 1)
    symtab += struct.pack("<IBBHQQ", offs[i], info, 0, 1, addr, 0)

EH = 64
PH = 56
text_off = 0x1000
sym_off = text_off + len(img)
str_off = sym_off + len(symtab)
shs_off = str_off + len(strtab)
sh_off = (shs_off + len(shstr) + 7) & ~7

ehdr = struct.pack(
    "<16sHHIQQQIHHHHHH",
    b"\x7fELF\x02\x01\x01" + b"\0" * 9,
    2, 183, 1, base, EH, sh_off, 0, EH, PH, 1, 64, 5, 4,
)
phdr = struct.pack("<IIQQQQQQ", 1, 7, text_off, base, base, len(img), len(img), 0x1000)


def sh(name, typ, flags, addr, off, size, link=0, info=0, align=1, ent=0):
    return struct.pack("<IIQQQQIIQQ", name, typ, flags, addr, off, size, link, info, align, ent)


shdrs = sh(0, 0, 0, 0, 0, 0)
shdrs += sh(SH_TEXT, 1, 0x7, base, text_off, len(img), align=0x1000)
shdrs += sh(SH_SYM, 2, 0, 0, sym_off, len(symtab), link=3, info=nlocal, align=8, ent=24)
shdrs += sh(SH_STR, 3, 0, 0, str_off, len(strtab))
shdrs += sh(SH_SHSTR, 3, 0, 0, shs_off, len(shstr))

with open(sys.argv[4], "wb") as f:
    f.write(ehdr + phdr)
    f.write(b"\0" * (text_off - EH - PH))
    f.write(img)
    f.write(symtab)
    f.write(strtab)
    f.write(shstr)
    f.write(b"\0" * (sh_off - shs_off - len(shstr)))
    f.write(shdrs)
print(f"{len(syms)} symbols, {len(img)} bytes text -> {sys.argv[4]}")
