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
DEV = next((a for a in sys.argv[1:] if a.startswith("/dev/")), "/dev/cdc-wdm0")
txn = [0]


SSH = os.environ.get("N9SSH")          # e.g. N9SSH=root@192.168.1.109 (pmOS); default: serial console via n9sh
QMIRAW = os.environ.get("QMIRAW", "/tmp/qmiraw")


def run(frame, want):
    cmd = "%s %s %s %d; echo flush" % (QMIRAW, DEV, frame.hex(), want)
    argv = ["ssh", "-o", "BatchMode=yes", SSH, cmd] if SSH else [os.path.join(HERE, "n9sh.sh"), cmd, "25"]
    out = subprocess.run(argv, capture_output=True, text=True).stdout
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
(r, t) = req(3, cNAS, 0x24); print("NAS serving system:", r, t.get(1, b"?").hex(), "plmn:", t.get(0x12, b"?").hex(), "all:", {k: v.hex() for k, v in t.items() if k not in (1, 2)})
(r, t) = req(3, cNAS, 0x20); print("NAS signal   :", r, t.get(1, b"?").hex())

if "--online" in sys.argv:
    # switch the radio on (DMS SET_OPERATING_MODE 0 = online) and look again after 15 s
    import time
    (r, t) = req(2, cDMS, 0x2e, bytes([1, 1, 0, 0])); print("set online  :", r)
    time.sleep(15)
    (r, t) = req(2, cDMS, 0x2d); print("oper. mode  :", r, t.get(1, b"?").hex())
    (r, t) = req(3, cNAS, 0x24); print("NAS serving system:", r, t.get(1, b"?").hex())
    (r, t) = req(3, cNAS, 0x20); print("NAS signal   :", r, t.get(1, b"?").hex())

if "--lowpower" in sys.argv:
    (r, t) = req(2, cDMS, 0x2e, bytes([1, 1, 0, 1])); print("set low power:", r)
    (r, t) = req(2, cDMS, 0x2d); print("oper. mode  :", r, t.get(1, b"?").hex())

if "--sysinfo" in sys.argv:
    (r, t) = req(3, cNAS, 0x4d); print("NAS sys info:", r, {hex(k): v.hex() for k, v in t.items() if k != 2})
    (r, t) = req(3, cNAS, 0x34); print("NAS sys sel pref:", r, {hex(k): v.hex() for k, v in t.items() if k != 2})
    (r, t) = req(3, cNAS, 0x31); print("NAS RF band info:", r, {hex(k): v.hex() for k, v in t.items() if k != 2})

if "--setapn" in sys.argv:
    # WDS MODIFY_PROFILE_SETTINGS (0x28) on 3GPP profile 1 (the LTE attach profile): APN + PDP type IPv4.
    # Only the modem's in-RAM EFS changes (efsks never runs, nothing is written to EF1/EF2); a modem restart undoes it.
    apn = sys.argv[sys.argv.index("--setapn") + 1].encode()
    (r, t) = req(1, cWDS, 0x28, bytes([1, 2, 0, 0, 1, 0x14, len(apn), 0]) + apn + bytes([0x11, 1, 0, 0]))
    print("WDS modify profile 1 -> apn %s IPv4:" % apn.decode(), r, {hex(k): v.hex() for k, v in t.items() if k != 2})
    if "--cycle" in sys.argv:     # re-trigger attach on an already online modem (the console stalled after this once)
        (r, t) = req(2, cDMS, 0x2e, bytes([1, 1, 0, 1])); print("set low power:", r)
        import time; time.sleep(3)
        (r, t) = req(2, cDMS, 0x2e, bytes([1, 1, 0, 0])); print("set online  :", r)

if "--profiles" in sys.argv:
    # WDS default profile (0x49), profile list (0x2a), settings of each 3GPP profile (0x2b); read only
    (r, t) = req(1, cWDS, 0x49, bytes([1, 2, 0, 0, 0])); print("WDS default 3GPP profile:", r, t.get(1, b"?").hex())
    (r, t) = req(1, cWDS, 0x2a, bytes([0x10, 1, 0, 0])); print("WDS profile list:", r, t.get(1, b"?").hex())
    lst = t.get(1, b"")
    n, p, idxs = (lst[0] if lst else 0), 1, []
    for _ in range(n):
        idxs.append(lst[p + 1]); p += 3 + lst[p + 2]
    for i in idxs:
        (r, t) = req(1, cWDS, 0x2b, bytes([1, 2, 0, 0, i]))
        print("  profile %d:" % i, r, {hex(k): (v.decode("ascii", "replace") if k in (0x10, 0x14) else v.hex()) for k, v in t.items() if k != 2})

if "--wds" in sys.argv:
    apn = (sys.argv[sys.argv.index("--wds") + 1] if len(sys.argv) > sys.argv.index("--wds") + 1 else "internet").encode()
    # TLV 0x14 = APN, TLV 0x19 = IP family preference (4 = IPv4)
    (r, t) = req(1, cWDS, 0x20, bytes([0x14, len(apn), 0]) + apn + bytes([0x19, 1, 0, 4]))
    print("WDS start network (apn %s):" % apn.decode(), r, {hex(k): v.hex() for k, v in t.items() if k != 2})
    (r, t) = req(1, cWDS, 0x22); print("WDS packet status:", r, t.get(1, b"?").hex())

if "--runtime" in sys.argv:
    # WDS GET_RUNTIME_SETTINGS: mask DNS (0x10) | IP (0x100) | gateway+subnet (0x200) | MTU (0x2000)
    (r, t) = req(1, cWDS, 0x2d, bytes([0x10, 4, 0]) + struct.pack("<I", 0x2310))
    ip4 = lambda k: ".".join(str(b) for b in reversed(t[k])) if k in t and len(t[k]) == 4 else "?"
    print("WDS runtime:", r, "ip", ip4(0x1e), "gw", ip4(0x20), "mask", ip4(0x21), "dns", ip4(0x15), ip4(0x16),
          "mtu", struct.unpack("<I", t[0x29])[0] if 0x29 in t else "?")

# release the QMI clients so repeated runs do not exhaust the modem's client ids
if "--stats" in sys.argv:
    # WDS GET_PKT_STATISTICS: mask tx ok 1, rx ok 2, tx err 4, rx err 8, tx ovf 0x10, rx ovf 0x20, tx/rx bytes 0x40/0x80, drops 0x100/0x200
    (r, t) = req(1, cWDS, 0x24, bytes([1, 4, 0]) + struct.pack("<I", 0x3ff))
    print("WDS pkt stats:", r, {hex(k): (struct.unpack("<Q", v)[0] if len(v) == 8 else struct.unpack("<I", v)[0] if len(v) == 4 else v.hex()) for k, v in t.items() if k != 2})

if "--wda" in sys.argv or "--rawip" in sys.argv:
    # WDA (0x1a) data format: TLV 0x11 link layer protocol 1 = 802.3, 2 = raw IP
    cWDA = alloc(0x1a); print("client WDA", cWDA)
    if "--rawip" in sys.argv:
        (r, t) = req(0x1a, cWDA, 0x20, bytes([0x11, 4, 0]) + struct.pack("<I", 2))
        print("WDA set raw IP:", r, {hex(k): v.hex() for k, v in t.items() if k != 2})
    (r, t) = req(0x1a, cWDA, 0x21); print("WDA data format:", r, {hex(k): v.hex() for k, v in t.items() if k != 2})
    if cWDA is not None:
        req(0, 0, 0x23, bytes([1, 2, 0, 0x1a, cWDA]))

# --keep leaves the WDS client allocated: releasing it ends a data call started with --wds
for _svc, _cid in ((2, cDMS), (3, cNAS), (0x0b, cUIM), (1, cWDS)):
    if _svc == 1 and "--keep" in sys.argv:
        print("WDS client %s kept (data call stays up)" % _cid); continue
    if _cid is not None:
        print("release", _svc, _cid, req(0, 0, 0x23, bytes([1, 2, 0, _svc, _cid]))[0])
