#!/usr/bin/env bash
# Build the Challenge Touch NEXT kernel with a reliable power-off.
#
# Background: the stock kernel's mt_power_off() reboots instead of powering
# off whenever a charger is connected (mtk_rtc_common.c / mt6358_misc.c call
# arch_reset() in that case). This script applies a small patch that removes
# that branch so `poweroff` really powers the device down.
#
# Prerequisites:
#   - Linux host with Nix
#   - the MediaTek kernel source tree, checked out at
#       a05ba-kernel/build/src/kernel/mediatek/mt8168/4.14
#     (see README.md -> "カーネルから作る" for how to obtain it)
#   - an aarch64 cross toolchain
#
# Usage: kernel/build-kernel.sh
set -euo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K="$BASE/a05ba-kernel/build/src/kernel/mediatek/mt8168/4.14"
[ -d "$K" ] || { echo "kernel tree not found: $K (see README)"; exit 1; }

CC_WRAP="$(mktemp)"
trap 'rm -f "$CC_WRAP"' EXIT

echo "== 1/4 apply the vendor platform patch =="
if [ -f "$BASE/a05ba-kernel/platform_patch.txt" ]; then
	patch -p5 -N -d "$K" -i "$BASE/a05ba-kernel/platform_patch.txt" || true
fi

echo "== 2/4 apply the ct-next power-off patch =="
patch -p1 -N -d "$K" -i "$BASE/kernel/ct-next-kernel.patch" || true

echo "== 3/4 install the compiler wrapper =="
# The vendor Makefiles assume the Android clang/GCC-4.9 toolchain. With a
# modern GCC they need -Wno-error, and several Makefiles rely on Kbuild's
# $(src) being on the include path for their "<local.h>" includes.
cat > "$CC_WRAP" <<'WRAP'
#!/bin/sh
extra=""
prev=""
for a in "$@"; do
	if [ "$prev" = "-o" ]; then
		case "$a" in
		*.o)
			o="$a"
			case "$o" in
			*"/.."*) o="${o%%/..*}" ;;
			*) o="$(dirname "$o")" ;;
			esac
			extra="$extra -I$o"
			;;
		esac
	fi
	prev="$a"
done
exec ${REAL_CC:?REAL_CC not set} "$@" -Wno-error $extra
WRAP
chmod +x "$CC_WRAP"

echo "== 4/4 build =="
nix-shell -p pkgsCross.aarch64-multiplatform.buildPackages.gcc gnumake bc bison \
	flex openssl perl python3 gzip coreutils gawk which --run "
	set -e
	cd '$K'
	export REAL_CC=\$(command -v aarch64-unknown-linux-gnu-gcc)
	export ARCH=arm64 CROSS_COMPILE=aarch64-unknown-linux-gnu-
	FAIL='-fcommon -Wno-array-compare -Wno-array-bounds -Wno-stringop-overflow
	      -Wno-maybe-uninitialized -Wno-address -Wno-dangling-pointer
	      -Wno-alloc-size-larger-than -Wno-free-nonheap-object -Wno-use-after-free
	      -Wno-stringop-truncation -Wno-restrict -Wno-unused-but-set-variable
	      -Wno-misleading-indentation'
	make mrproper >/dev/null 2>&1 || true
	make a05ba_defconfig
	make -j\$(nproc) Image.gz CC='$CC_WRAP' KCFLAGS=\"\$FAIL\"
"

echo
echo "built: $K/arch/arm64/boot/Image.gz"
echo "pack it into a recovery image with: kernel/pack-recovery.py <kernel> <initramfs> <twrp.img> <out.img>"
