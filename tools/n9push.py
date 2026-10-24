#!/usr/bin/env python3
"""Copy a file to the tablet over the USB-serial root shell (no WiFi needed).

usage: n9push.py <local-file> <remote-path>

The tablet side is the raw-mode shell from tools/pmos/n9-usbshell.initd: it is told to
`head -c N > path`, the file's bytes follow on the same line, and the reply carries the
remote md5, which is compared with the local one. Exit 0 only when they match.
"""
import hashlib
import os
import sys
import termios
import time
import uuid

dev = os.environ.get("N9TTY", "/dev/ttyACM0")
src, dst = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()
want = hashlib.md5(data).hexdigest()

fd = os.open(dev, os.O_RDWR | os.O_NOCTTY)
a = termios.tcgetattr(fd)
a[0] = a[1] = a[3] = 0
a[2] = (a[2] & ~(termios.CSIZE | termios.PARENB)) | termios.CS8 | termios.CLOCAL | termios.CREAD
a[6][termios.VMIN] = 0
a[6][termios.VTIME] = 0
termios.tcsetattr(fd, termios.TCSANOW, a)

tag = uuid.uuid4().hex[:8]
cmd = ("\nhead -c %d > %s.part && mv %s.part %s; echo N9P%s\"\"%s $(md5sum < %s | cut -d' ' -f1)\n"
       % (len(data), dst, dst, dst, tag[:4], tag[4:], dst))
os.write(fd, cmd.encode())
time.sleep(0.3)                      # let the shell start head before the payload arrives
t0 = time.time()
view = memoryview(data)
while view:
    n = os.write(fd, view[:65536])
    view = view[n:]
buf = b""
end = time.time() + 60 + len(data) / 200000
marker = ("N9P" + tag).encode()
while time.time() < end and marker not in buf:
    try:
        chunk = os.read(fd, 4096)
    except BlockingIOError:
        chunk = b""
    if chunk:
        buf += chunk
    else:
        time.sleep(0.05)
dt = time.time() - t0
line = buf[buf.find(marker):].split(b"\n")[0].decode(errors="replace") if marker in buf else ""
got = line.split()[-1] if line else ""
print("%s -> %s: %d bytes in %.1f s (%.0f KB/s), md5 %s %s"
      % (src, dst, len(data), dt, len(data) / 1024 / max(dt, 0.01), got or "?",
         "OK" if got == want else "MISMATCH (want %s)" % want))
sys.exit(0 if got == want else 1)
