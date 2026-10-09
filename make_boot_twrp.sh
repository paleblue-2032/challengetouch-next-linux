#!/usr/bin/env bash
# Build a Linux boot image based on the *working* TWRP image:
#   TWRP kernel + appended DTB + TWRP cmdline (androidboot.selinux=permissive,
#   veritymode=ignore_corruption, ...)  with our own Linux initramfs.
# This avoids whatever made the "stock-kernel + our ramdisk" image reset.
set -euo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; W="$BASE/work"; R="$W/initramfs-root"

mkdir -p "$R/bin" "$R/sbin" "$R/dev" "$R/proc" "$R/sys" "$R/tmp" "$R/run"
cp -f "$W/busybox-aarch64" "$R/bin/busybox"
chmod 755 "$R/bin/busybox" "$R/init" "$R"

( cd "$R" && find . -print0 | cpio --null -o -H newc --owner=0:0 2>/dev/null | gzip -9 > "$W/initramfs.cpio.gz" )

CMDLINE="$(cat "$W/twrp_cmdline.txt")"
echo "cmdline: $CMDLINE"

mkbootimg \
  --kernel "$W/twrp_kernel_with_dtb" \
  --ramdisk "$W/initramfs.cpio.gz" \
  --base 0x40000000 \
  --kernel_offset 0x00080000 \
  --ramdisk_offset 0x15000000 \
  --tags_offset 0x14000000 \
  --pagesize 2048 \
  --header_version 1 \
  --cmdline "$CMDLINE" \
  -o "$W/linux_recovery_v2.img"

# pad to the 16 MiB recovery partition size
truncate -s 16777216 "$W/linux_recovery_v2.img"
ls -l "$W/linux_recovery_v2.img"
python3 - "$W/linux_recovery_v2.img" <<'PY'
import struct,sys
d=open(sys.argv[1],'rb').read(64)
ks,ka,rs,ra,ss,sa,ta,ps=struct.unpack_from("<8I",d,8)
print("magic",d[:8],"ks",ks,"rs",rs,"page",ps,"cmdline",d[64:64+60].split(b'\0')[0])
PY
