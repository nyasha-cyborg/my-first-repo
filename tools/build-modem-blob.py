#!/usr/bin/env python3
"""Build the modem's per-unit Sahara files (EFS + HTC NV) the way the stock `qcks` does, but
entirely on the host and read-only: no partition is written.

Inputs (private, NEVER commit): ~/Downloads/nexus9/modem-private/{ef1,ef2,rca,cdr}.raw  (dd copies of
the tablet's EF1/EF2/RCA/CDR partitions) and the stock image dir (stubs, rcdata_*.img).
Output (same private dir): mdata.bin (concatenated files) and sahara-args.txt (id:path@offset:size).
Recipe (REA of qcks FUN_00402284/FUN_00402e44): efsN.bin = first 3 MiB of EFN; htcNN.bin = 40-byte
stub + 1 MiB of the partition at a KiB offset; the carrier CNV slots first overlay rcdata_<x>.img
at RCA offset 7168 KiB (done here in memory), then read 1 MiB from there.
"""
import os
import sys

P = os.path.expanduser("~/Downloads/nexus9/modem-private")
IMG = os.path.expanduser("~/Downloads/nexus9/google-volantisg-n4f27p/vendor-files/mdm/image")
REMOTE = "/tmp/mdata.bin"
MiB = 1 << 20


def rd(name):
    return open(os.path.join(P, name), "rb").read()


ef1, ef2, rca, cdr = rd("ef1.raw"), rd("ef2.raw"), rd("rca.raw"), rd("cdr.raw")


def stub(n):
    d = open(os.path.join(IMG, n), "rb").read()
    assert len(d) == 40, n
    return d


def cnv(rcdata):
    part = bytearray(rca)
    if rcdata:
        r = open(os.path.join(IMG, rcdata), "rb").read()
        part[7168 * 1024:7168 * 1024 + len(r)] = r
    return bytes(part[7168 * 1024:7168 * 1024 + MiB])


files = [
    (16, ef1[:3 * MiB]),
    (17, ef2[:3 * MiB]),
    (40, stub("htcssmem.mbn") + rca[0x000 * 1024:0x000 * 1024 + MiB]),
    (42, stub("htcnvmfg.mbn") + rca[0x400 * 1024:0x400 * 1024 + MiB]),
    (43, stub("htcrfnv.mbn") + rca[0xc00 * 1024:0xc00 * 1024 + MiB]),
    (45, stub("htcuserd.mbn") + rca[0x800 * 1024:0x800 * 1024 + MiB]),
    (46, stub("htccdma.mbn") + cdr[:MiB]),
    (44, stub("htccnv_a.mbn") + cnv("rcdata_att.img")),
    (47, stub("htccnv_t.mbn") + cnv("rcdata_tmo.img")),
    (48, stub("htccnv_v.mbn") + cnv("rcdata_vzw.img")),
    (49, stub("htccnv_s.mbn") + cnv(None)),          # rcdata_spcs.img is not in the image
    (55, stub("htccnv_u.mbn") + cnv("rcdata_ul.img")),
    (56, stub("htccnv_o.mbn") + cnv("rcdata_o2.img")),
]
blob = b""
args = []
for i, data in files:
    args.append("%d:%s@%d" % (i, REMOTE, len(blob)))
    blob += data
open(os.path.join(P, "mdata.bin"), "wb").write(blob)
os.chmod(os.path.join(P, "mdata.bin"), 0o600)
open(os.path.join(P, "sahara-args.txt"), "w").write(" ".join(args) + "\n")
print("blob %d bytes; %d files; args: %s" % (len(blob), len(files), " ".join(args)))
