#!/usr/bin/env python3
"""Fetch a file from the tablet's USB console as base64 and decode it locally.
Usage: serial_getb64.py <port> <remote_path> <local_out>
"""
import sys, time, base64, re, serial

port, remote, out = sys.argv[1], sys.argv[2], sys.argv[3]
s = serial.Serial(port, 115200, timeout=0.5)
time.sleep(1)
s.write(b"\x03"); time.sleep(0.5); s.reset_input_buffer()
s.write(("base64 %s\n" % remote).encode())
time.sleep(2)
d = b""
t = time.time()
while time.time() - t < 8:
    x = s.read(8192)
    if x:
        d += x
        t = time.time()
txt = d.decode("utf-8", "replace")
b64 = "".join(
    l.strip() for l in txt.splitlines()
    if re.fullmatch(r"[A-Za-z0-9+/=]+", l.strip()) and len(l.strip()) > 20
)
open(out, "wb").write(base64.b64decode(b64))
print("wrote", out, "b64chars", len(b64))
s.close()
