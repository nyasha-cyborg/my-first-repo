#!/usr/bin/env python3
"""Push a file to the tablet's /tmp over the USB-serial console (raw, checksummed).

usage: n9push.py <local-file> <remote-path>
Needs /bin/rxfile in the test image (tools/miniroot/rxfile.c).  The tablet shell must be idle.
"""
import os
import select
import sys
import termios
import time

src, dst = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()
want_sum = sum(data) & 0xFFFFFFFF
dev = os.environ.get("N9TTY", "/dev/ttyACM0")
fd = os.open(dev, os.O_RDWR | os.O_NOCTTY)
a = termios.tcgetattr(fd)
a[0] = a[1] = a[3] = 0
a[2] = (a[2] & ~(termios.CSIZE | termios.PARENB)) | termios.CS8 | termios.CLOCAL | termios.CREAD
a[6][termios.VMIN] = 0
a[6][termios.VTIME] = 0
termios.tcsetattr(fd, termios.TCSANOW, a)


def read_until(token, secs):
    buf = b""
    end = time.time() + secs
    while time.time() < end and token not in buf:
        r, _, _ = select.select([fd], [], [], 0.5)
        if r:
            buf += os.read(fd, 65536)
    return buf


os.write(fd, ("\n/bin/rxfile %s %d\n" % (dst, len(data))).encode())
if b"RXREADY" not in read_until(b"RXREADY", 15):
    sys.exit("receiver did not start")
time.sleep(1.0)                     # let the receiver settle, drop anything stale
termios.tcflush(fd, termios.TCIFLUSH)
t0 = time.time()
BLK = 16384
for pos in range(0, len(data), BLK):
    blk = data[pos:pos + BLK]
    off = 0
    while off < len(blk):
        if select.select([], [fd], [], 5)[1]:
            off += os.write(fd, blk[off:])
    # wait for the tablet's ACK (0x06) before sending the next block
    got = b""
    end = time.time() + 20
    while b"\x06" not in got and time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.5)
        if r:
            got += os.read(fd, 65536)
    if b"\x06" not in got:
        sys.exit("no ACK from the tablet at offset %d" % pos)
res = read_until(b"sum=", 60)
res += read_until(b"\n", 3)            # the hex digits follow "sum="
dt = time.time() - t0
txt = res.decode("utf8", "replace")
print("sent %d bytes in %.1fs; tablet says: %s" % (len(data), dt, txt.strip().splitlines()[-1] if txt.strip() else "<nothing>"))
ok = ("rx ok %x sum=%x" % (len(data), want_sum)) in txt
print("CHECKSUM OK" if ok else "CHECKSUM MISMATCH (want sum=%x)" % want_sum)
sys.exit(0 if ok else 1)
