#!/usr/bin/env python3
"""Push a small local file to the tablet over the USB ACM console.

Base64-encodes the file so no shell quoting is needed on the device side.

Usage: serial_put.py <port> <local_file> <remote_path> [chmod]
"""
import base64
import os
import re
import sys
import time

import serial

port, local, remote = sys.argv[1], sys.argv[2], sys.argv[3]
mode = sys.argv[4] if len(sys.argv) > 4 else None
prompt = re.compile(rb"[#$] ")

data = open(local, "rb").read()
b64 = base64.b64encode(data).decode()
chunks = [b64[i : i + 2048] for i in range(0, len(b64), 2048)] or [""]

s = serial.Serial(port, 115200, timeout=0.2)


def wait_prompt(limit=30):
    buf = b""
    end = time.time() + limit
    while time.time() < end:
        d = s.read(4096)
        if d:
            buf += d
            if prompt.search(buf[-8:]):
                break
    return buf


time.sleep(1.0)
s.reset_input_buffer()
s.write(b"\x03")
time.sleep(0.5)
s.reset_input_buffer()

for i, ch in enumerate(chunks):
    redir = ">" if i == 0 else ">>"
    s.write(("printf '%%s' '%s' | base64 -d %s %s\n" % (ch, redir, remote)).encode())
    d = wait_prompt(30)
    if b"not found" in d or b"error" in d.lower():
        print("WARN:", d.decode("utf-8", "replace"))

if mode:
    s.write(("chmod %s %s\n" % (mode, remote)).encode())
    wait_prompt(10)

s.write(b"echo PUSH_DONE\n")
print(wait_prompt(10).decode("utf-8", "replace"))
s.close()
print("pushed %d bytes -> %s" % (len(data), remote))
