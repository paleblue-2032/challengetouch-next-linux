#!/usr/bin/env bash
# One-shot: flash the Linux (mostly-stock-kernel + initramfs) image into the
# recovery slot and boot it via the normal recovery boot path (avoids the
# MTK "fastboot boot" watchdog reset).
#
#   ./flash_linux_recovery.sh [image]     (default: work/linux_recovery.img)
set -u
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMG="${1:-$BASE/work/linux_recovery.img}"

echo "== image: $IMG =="
ls -l "$IMG"

echo "== reboot to bootloader =="
adb reboot bootloader || exit 1

echo "== wait for fastboot =="
for i in $(seq 1 60); do
	fastboot devices 2>/dev/null | grep -q fastboot && { echo "fastboot at ${i}s"; break; }
	sleep 1
done
fastboot devices || exit 1

echo "== flash recovery =="
fastboot flash recovery "$IMG" || exit 1

echo "== boot recovery (our linux) =="
fastboot oem reboot-recovery || exit 1

echo "== monitor usb (change only) =="
python3 - <<'PY'
import subprocess, time
prev = None
for i in range(90):
    out = subprocess.run(['lsusb'], capture_output=True, text=True).stdout
    ids = ','.join(sorted(l.split('ID ')[1].split()[0]
                          for l in out.splitlines()
                          if '0e8d' in l or '18d1' in l or '1d6b:0104' in l))
    if ids != prev:
        print(f"t={i:3d}s usb=[{ids}]")
        prev = ids
    time.sleep(1)
PY
adb devices -l 2>&1
