#!/usr/bin/env python3
"""Run one command on the tablet's USB-serial shell and print its output.

usage: n9sh.py '<command>' [max-seconds]

Each request is wrapped in a unique start/end marker pair and the reader
stops as soon as the matching end marker arrives (or at max-seconds), so
output of earlier, slower commands can never be mistaken for this one's.
The console must be the piped non-interactive shell (/etc/n9-plainsh).
Exit status: 0 on success, 3 if the end marker never arrived.
"""
import os
import select
import sys
import termios
import time
import uuid

dev = os.environ.get("N9TTY", "/dev/ttyACM0")
cmd = sys.argv[1]
limit = float(sys.argv[2]) if len(sys.argv) > 2 else 5.0

fd = os.open(dev, os.O_RDWR | os.O_NOCTTY)
a = termios.tcgetattr(fd)
a[0] = a[1] = a[3] = 0                      # raw: no echo, no translation
a[2] = (a[2] & ~(termios.CSIZE | termios.PARENB)) | termios.CS8 | termios.CLOCAL | termios.CREAD
a[6][termios.VMIN] = 0
a[6][termios.VTIME] = 0
termios.tcsetattr(fd, termios.TCSANOW, a)

tag = uuid.uuid4().hex[:8]
start = "N9S" + tag
end = "N9E" + tag
# build the markers from two halves so the tty's echo of the command line
# never contains them contiguously
payload = ("\necho N9S%s\"\"%s\n%s\necho N9E%s\"\"%s\n"
           % (tag[:4], tag[4:], cmd, tag[:4], tag[4:]))
os.write(fd, payload.encode())

buf = b""
deadline = time.time() + limit
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        buf += os.read(fd, 4096)
    if ("\n" + end + "\n").encode() in buf.replace(b"\r", b""):
        break
text = buf.replace(b"\r", b"").decode(errors="replace")
s = text.find("\n" + start + "\n")
e = text.find("\n" + end + "\n")
if s < 0 or e < 0:
    sys.stderr.write("n9sh: no reply (%d bytes seen)\n" % len(buf))
    sys.exit(3)
sys.stdout.write(text[s + len(start) + 2:e + 1])
