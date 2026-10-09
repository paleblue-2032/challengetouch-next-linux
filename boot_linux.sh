#!/usr/bin/env bash
# Build and boot Linux on the Challenge Pad NEXT (a05ba).
# Achieves: Linux 4.14 boots, root shell over the USB ACM console (/dev/ttyACM0).
set -u
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd "$BASE"

echo "== (re)build initramfs + linux image (original-structure swap) =="
nix-shell -p cpio gzip --run 'mkdir -p work/initramfs-root/bin; cp -f work/busybox-aarch64 work/initramfs-root/bin/busybox; chmod 755 work/initramfs-root/bin/busybox work/initramfs-root/init; cd work/initramfs-root && find . -print0 | cpio --null -o -H newc --owner=0:0 2>/dev/null | gzip -9 > ../initramfs.cpio.gz'
bash build_linux_img.sh work/initramfs.cpio.gz twrp/a05ba-tate.img work/linux_v5.img || exit 1

echo "== enter fastboot =="
if adb devices 2>/dev/null | grep -q device; then
	adb reboot bootloader
else
	nix-shell -p python3 python3Packages.pyserial --run 'bash work/enter_fastboot.sh'
fi
for i in $(seq 1 60); do fastboot devices 2>/dev/null | grep -q fastboot && { echo "fastboot ${i}s"; break; }; sleep 1; done

echo "== flash recovery + boot Linux =="
fastboot flash recovery work/linux_v5.img || exit 1
fastboot oem reboot-recovery

echo "== wait for USB ACM console (1d6b:0104 -> /dev/ttyACM0) =="
for i in $(seq 1 90); do lsusb | grep -q 1d6b:0104 && { echo "console up at ${i}s"; break; }; sleep 1; done
ls -l /dev/ttyACM* 2>&1
cat <<'EOF'

Connect:
  nix-shell -p python3 python3Packages.pyserial --run \
    'python3 work/serial_cmd.py /dev/ttyACM0 "uname -a" "id" "ls /"'
  # or interactively:  screen /dev/ttyACM0 115200

Notes:
  - The init has a 600s safety watchdog, after which it reboots to Android.
  - To restore stock recovery:  fastboot flash recovery REDACTED/Next/files/imgs/recovery.img
  - boot partition (Android) is never touched by this script.
EOF
