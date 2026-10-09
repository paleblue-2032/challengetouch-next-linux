#!/usr/bin/env bash
# Pack a Linux-bootable boot.img for the Challenge Touch NEXT:
#   stock (working) kernel + appended Next DTB  +  custom Linux initramfs.
# Non-destructive test:  fastboot boot work/boot_linux_test.img
set -euo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$BASE/work"
R="$W/initramfs-root"

mkdir -p "$R/bin" "$R/sbin" "$R/dev" "$R/proc" "$R/sys" "$R/tmp" "$R/run"
cp -f "$W/busybox-aarch64" "$R/bin/busybox"
chmod 755 "$R/bin/busybox" "$R/init"
chmod 755 "$R"

# initramfs cpio (newc) + gzip
( cd "$R" && find . -print0 | cpio --null -o -H newc --owner=0:0 2>/dev/null | gzip -9 > "$W/initramfs.cpio.gz" )

# kernel blob = Image.gz (no dtb) + appended DTB  -> equals stock kernel_size
cat "$BASE/kernel_Image.gz" "$BASE/next_appended.dtb" > "$W/kernel_with_dtb"

mkbootimg \
  --kernel "$W/kernel_with_dtb" \
  --ramdisk "$W/initramfs.cpio.gz" \
  --base 0x40000000 \
  --kernel_offset 0x00080000 \
  --ramdisk_offset 0x15000000 \
  --tags_offset 0x14000000 \
  --pagesize 2048 \
  --header_version 1 \
  --os_version 9.0.0 \
  --os_patch_level 2021-06 \
  --cmdline "bootopt=64S3,32N2,64N2 buildvariant=user" \
  -o "$W/boot_linux_test.img"

echo "--- sizes ---"
ls -l "$W/initramfs.cpio.gz" "$W/kernel_with_dtb" "$W/boot_linux_test.img"
echo "--- header check ---"
python3 - "$W/boot_linux_test.img" <<'PY'
import struct,sys
d=open(sys.argv[1],'rb').read()
ks,ka,rs,ra,ss,sa,ta,ps=struct.unpack_from("<8I",d,8)
hv,osv=struct.unpack_from("<2I",d,40)
print("magic",d[:8],"kernel_size",ks,"ramdisk_size",rs,"page",ps,"hdr_ver",hv)
print("cmdline",d[64:64+64].split(b'\0')[0])
PY
