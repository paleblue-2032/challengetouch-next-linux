#!/usr/bin/env python3
# Repack a recovery image with OUR kernel and initramfs, reusing a known-good
# base image (TWRP) for the parts this device's LK requires: the page layout,
# the recovery_dtbo and the AVB struct/footer.
#
# Only the kernel and the ramdisk are replaced; everything from the dtbo
# onwards sits at a fixed offset and is copied verbatim. Because the dtbo
# offset is fixed, the new kernel+ramdisk must fit before it (default kernel
# region is 8 MiB, ramdisk region ~7.8 MiB).
#
# usage: pack-recovery.py <kernel_blob> <initramfs.cpio.gz> <base.img> <out.img>
#
# <kernel_blob> is "Image.gz" with the board DTB appended, i.e.
#   cat arch/arm64/boot/Image.gz next_appended.dtb > kernel_with_dtb
import struct
import sys

if len(sys.argv) != 5:
    sys.exit(__doc__ or "usage: pack-recovery.py kernel initramfs base out")

kernel = open(sys.argv[1], "rb").read()
ram = open(sys.argv[2], "rb").read()
base = sys.argv[3]
out = sys.argv[4]

d = bytearray(open(base, "rb").read())
ks, ka, rs, ra, ss, sa, ta, ps = struct.unpack_from("<8I", d, 8)
ds, do = struct.unpack_from("<2I", d, 1632)   # recovery_dtbo (header v1)

ko = ps
ro = ps + ((len(kernel) + ps - 1) // ps) * ps
assert ro + len(ram) <= do, (
    f"kernel+ramdisk too big: end={ro + len(ram)} > dtbo@{do}"
)

for i in range(ko, do):
    d[i] = 0
d[ko : ko + len(kernel)] = kernel
d[ro : ro + len(ram)] = ram
struct.pack_into("<I", d, 8, len(kernel))   # kernel_size
struct.pack_into("<I", d, 16, len(ram))     # ramdisk_size
open(out, "wb").write(bytes(d))

print(f"wrote {out}")
print(f"  kernel : {len(kernel)} bytes at {ko}")
print(f"  ramdisk: {len(ram)} bytes at {ro}")
print(f"  dtbo   : {ds} bytes at {do} (kept)")
print(f"  base   : old kernel {ks}, old ramdisk {rs}, page {ps}")
