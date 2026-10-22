#!/usr/bin/env python3
"""Query the LTE modem over QMI via the tablet's /tmp/qmiraw (see tools/miniroot/qmiraw.c).

usage: qmi-probe.py [/dev/cdc-wdm0]      Prints model/revision/operating mode/SIM/network info.
Identifiers (IMEI etc.) are masked.  Needs the tablet shell idle and /tmp/qmiraw present.
"""
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEV = sys.argv[1] if len(sys.argv) > 1 else "/dev/cdc-wdm0"
txn = [0]


def run(frame, want):
    out = subprocess.run([os.path.join(HERE, "n9sh.sh"), "/tmp/qmiraw %s %s %d; echo flush" % (DEV, frame.hex(), want), "25"],
                         capture_output=True, text=True).stdout
    return [bytes.fromhex(l.strip()) for l in out.splitlines() if l.strip() and all(c in "0123456789abcdef" for c in l.strip())]


def tlvs(b):
    d = {}
    while len(b) >= 3:
        t, l = b[0], struct.unpack("<H", b[1:3])[0]
        d[t] = b[3:3 + l]
        b = b[3 + l:]
    return d


def req(svc, cid, msg, payload=b""):
    txn[0] += 1
    if svc == 0:
        sdu = struct.pack("<BBHH", 0, txn[0] & 0xff, msg, len(payload)) + payload
    else:
        sdu = struct.pack("<BHHH", 0, txn[0], msg, len(payload)) + payload
    f = struct.pack("<BHBBB", 1, 5 + len(sdu), 0, svc, cid) + sdu
    for r in run(f, 4):
        if len(r) < 12 or r[4] != svc or r[3] != 0x80:
            continue
        if svc == 0:
            flags, rt, rm, rl = struct.unpack("<BBHH", r[6:12]); body = r[12:12 + rl]
        else:
            flags, rt, rm, rl = struct.unpack("<BHHH", r[6:13]) if False else (r[6], struct.unpack("<H", r[7:9])[0], struct.unpack("<H", r[9:11])[0], struct.unpack("<H", r[11:13])[0]); body = r[13:13 + rl]
        if rm != msg or (flags & (2 if svc == 0 else 4)) or not (flags & (1 if svc == 0 else 2)):
            continue                      # CTL: 1=resp 2=ind; other services: 2=resp 4=ind
        t = tlvs(body)
        res = struct.unpack("<HH", t[2]) if 2 in t else (None, None)
        return res, t
    return (None, None), {}


def alloc(svc):
    (res, _), t = req(0, 0, 0x22, bytes([1, 1, 0, svc]))
    return t[1][1] if 1 in t else None


def txt(t, k=0x01):
    return t[k].decode("ascii", "replace") if k in t else "?"


print("QMI probe on", DEV)
for name, svc in (("DMS", 2), ("NAS", 3), ("UIM", 0x0b), ("WDS", 1)):
    c = alloc(svc)
    print("client", name, c)
    globals()["c" + name] = c
(r, t) = req(2, cDMS, 0x21); print("manufacturer:", r, txt(t))
(r, t) = req(2, cDMS, 0x22); print("model       :", r, txt(t))
(r, t) = req(2, cDMS, 0x23); print("revision    :", r, txt(t))
(r, t) = req(2, cDMS, 0x2d); print("oper. mode  :", r, t.get(1, b"?").hex())
(r, t) = req(2, cDMS, 0x25)
imei = txt(t, 0x11)
print("IDs         :", r, "IMEI %s...%s (masked)" % (imei[:4], imei[-2:]) if imei != "?" else "no IMEI in reply (blank?)")
(r, t) = req(0x0b, cUIM, 0x2f); print("UIM card status:", r, t.get(0x10, b"?").hex()[:60])
(r, t) = req(3, cNAS, 0x24); print("NAS serving system:", r, t.get(1, b"?").hex())
(r, t) = req(3, cNAS, 0x20); print("NAS signal   :", r, t.get(1, b"?").hex())
