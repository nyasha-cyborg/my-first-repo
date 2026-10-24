#!/bin/bash
# Wrap the AVP video microcode (raw Thumb, loaded at 0) as an ELF with fn_XXXXX symbols at every
# Thumb `push {..., lr}` prologue, for REA/Ghidra (and llvm-objdump --triple=thumbv5te).
#   usage: tools/avp-ucode2elf.sh nvavp_vid_ucode_alt.bin out.elf
# Get the blob from the factory vendor image:
#   debugfs -R 'dump /firmware/nvavp_vid_ucode_alt.bin nvavp_vid_ucode_alt.bin' vendor.raw
set -eu
in=$1 out=$2
syms=$(python3 -I - "$in" <<'PY'
import sys
d = open(sys.argv[1], "rb").read()
print(" ".join("--add-symbol=fn_%05x=.data:0x%x,function,global" % (i, i | 1)
               for i in range(0, len(d) - 1, 2) if d[i + 1] == 0xb5))
PY
)
tmp=$(mktemp -d)
llvm-objcopy -I binary -O elf32-littlearm $syms --rename-section .data=.text,code,alloc,load,readonly \
	--strip-symbol=_binary_*_start "$in" "$tmp/u.o"
# link at 0 so Ghidra/REA see an executable with section-relative function symbols
ld.lld -m armelf --image-base=0 --section-start=.text=0 -e 0 --no-dynamic-linker -o "$out" "$tmp/u.o"
rm -rf "$tmp"
echo "$(echo "$syms" | wc -w) functions -> $out"
