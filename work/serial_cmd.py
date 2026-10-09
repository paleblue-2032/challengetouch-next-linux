#!/usr/bin/env python3
"""Open the Challenge Touch Linux USB ACM console and run shell commands.

Waits for the shell prompt after each command so that slow commands
(apk update/add, network fetches) are captured reliably.

Usage: serial_cmd.py [port] "cmd1" "cmd2" ...
Env:   SERIAL_TIMEOUT  per-command max seconds (default 180)
       SERIAL_PROMPT   prompt regex bytes (default b"[#$] ")
"""
import os
import re
import sys
import time

import serial

port = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyACM0"
cmds = sys.argv[2:] or ["uname -a"]
timeout = float(os.environ.get("SERIAL_TIMEOUT", "180"))
prompt = re.compile(os.environ.get("SERIAL_PROMPT", r"[#$] ").encode())

try:
    s = serial.Serial(port, 115200, timeout=0.2)
except Exception as e:
    print("OPEN FAIL:", e)
    sys.exit(2)


def drain(seconds):
    end = time.time() + seconds
    while time.time() < end:
        if not s.read(4096):
            break


def wait_prompt(limit):
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
s.write(b"\x03")  # abort anything half-typed
drain(1.0)

out = []
for c in cmds:
    s.write((c + "\n").encode())
    d = wait_prompt(timeout)
    out.append(d.decode("utf-8", "replace"))
    drain(0.3)

s.close()
print("".join(out))
