#!/usr/bin/env bash
# Build work/initramfs-root/alpine.tar.gz = pristine Alpine minirootfs + this
# repo's work/device/ overlay, so that a freshly-flashed device boots with our
# scripts already in place (network + SSH come up without a serial console).
#
# Usage:
#   work/make_alpine_base.sh [base-minirootfs.tar.gz]
#
# If no base tarball is given it downloads one from the Alpine CDN for
# $ALPINE_VERSION (default 3.24) / $ARCH (default aarch64).
set -euo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV="$BASE/work/device"
OUT="$BASE/work/initramfs-root/alpine.tar.gz"
ALPINE_VERSION="${ALPINE_VERSION:-3.24}"
ARCH="${ARCH:-aarch64}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

base="${1:-}"
if [ -z "$base" ]; then
	dir="$(printf '%s' "$ALPINE_VERSION" | cut -d. -f1,2)"
	url="https://dl-cdn.alpinelinux.org/alpine/v${dir}/releases/${ARCH}/"
	file="$(curl -fsSL "$url" | grep -oE "alpine-minirootfs-${ALPINE_VERSION}\.[0-9]+-${ARCH}\.tar\.gz" | sort -V | tail -1)"
	[ -n "$file" ] || { echo "could not find an Alpine ${ALPINE_VERSION} ${ARCH} minirootfs at $url" >&2; exit 1; }
	echo "downloading $url$file"
	base="$tmp/base.tar.gz"
	curl -fsSL "$url$file" -o "$base"
fi
[ -f "$base" ] || { echo "base tarball not found: $base" >&2; exit 1; }

echo "extracting $base"
mkdir -p "$tmp/root"
tar xzf "$base" -C "$tmp/root" --numeric-owner

echo "overlaying work/device/"
[ -d "$DEV/etc" ] && cp -a "$DEV/etc/." "$tmp/root/etc/"
[ -d "$DEV/root" ] && { mkdir -p "$tmp/root/root"; cp -a "$DEV/root/." "$tmp/root/root/"; }
mkdir -p "$tmp/root/usr/local/bin"
[ -d "$DEV/usr-local-bin" ] && cp -a "$DEV/usr-local-bin/." "$tmp/root/usr/local/bin/"
chmod 755 "$tmp/root/usr/local/bin/"* 2>/dev/null || true

echo "packing $OUT"
( cd "$tmp/root" && tar --owner=0 --group=0 --numeric-owner -czf "$OUT" . )
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
echo
echo "next: rebuild the initramfs + image, e.g."
echo "  nix-shell -p cpio gzip --run 'cd work/initramfs-root && cp -f ../busybox-aarch64 bin/busybox && chmod 755 bin/busybox init && find . -print0 | cpio --null -o -H newc --owner=0:0 2>/dev/null | gzip -9 > ../initramfs_alpine_v9.cpio.gz'"
echo "  bash build_linux_img.sh work/initramfs_alpine_v9.cpio.gz twrp/a05ba-tate.img work/linux_v9.img"
