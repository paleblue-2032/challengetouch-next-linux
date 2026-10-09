#!/usr/bin/env bash
# Build a bootable recovery image for a05ba that RUNS OUR OWN initramfs.
#
# WHY: this device's LK refuses images produced by plain mkbootimg (they lack
# the dtbo + AVB0/AVBf footer structure). It accepts the stock/TWRP image
# structure. So we take a known-good image and swap only the ramdisk, keeping
# the header layout, the recovery_dtbo and the AVB footer intact.
#
# Usage: build_linux_img.sh <initramfs.cpio.gz> [base.img] [out.img]
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INITRAMFS="${1:?initramfs.cpio.gz required}"
BASE_IMG="${2:-$BASE_DIR/twrp/a05ba-tate.img}"
OUT="${3:-$BASE_DIR/work/linux_v3.img}"

python3 - "$INITRAMFS" "$BASE_IMG" "$OUT" <<'PY'
import struct, sys
ram = open(sys.argv[1], 'rb').read()
d = bytearray(open(sys.argv[2], 'rb').read())
ks, ka, rs, ra, ss, sa, ta, ps = struct.unpack_from('<8I', d, 8)
ro = ps + ((ks + ps - 1) // ps) * ps
dtbo_sz, dtbo_off = struct.unpack_from('<2I', d, 1632)
assert dtbo_off > ro, "unexpected: no recovery_dtbo after kernel"
maxram = dtbo_off - ro
assert len(ram) <= maxram, f"initramfs too big: {len(ram)} > {maxram}"
struct.pack_into('<I', d, 16, len(ram))            # ramdisk_size
d[ro:dtbo_off] = ram + b'\0' * (maxram - len(ram))  # keep dtbo/AVB after it
open(sys.argv[3], 'wb').write(bytes(d))
print(f"wrote {sys.argv[3]}: ramdisk={len(ram)} (max {maxram}), dtbo@{dtbo_off}, kept AVB footer")
PY
