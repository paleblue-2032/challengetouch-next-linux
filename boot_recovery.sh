#!/usr/bin/env bash
# Boot the tablet into our Linux. Linux lives in the RECOVERY slot, so we have to
# ask the bootloader for a recovery boot (a plain reboot boots Android instead).
# Works whether the tablet is currently in Android (adb) or in Linux (ssh).
set -u
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if adb devices 2>/dev/null | grep -qw device; then
	adb reboot recovery
elif "$BASE/work/ssh.sh" true 2>/dev/null; then
	echo "tablet is in Linux; rebooting through Android to reach recovery"
	"$BASE/work/ssh.sh" 'sync; busybox reboot -f' >/dev/null 2>&1 || true
	for i in $(seq 1 60); do
		adb devices 2>/dev/null | grep -qw device && break
		sleep 2
	done
	adb reboot recovery || exit 1
else
	echo "tablet not reachable via adb or ssh"
	exit 1
fi

echo "waiting for our Linux (USB gadget 1d6b:0104 + ssh)..."
for i in $(seq 1 90); do
	if lsusb 2>/dev/null | grep -q 1d6b:0104; then
		bash "$BASE/host_net.sh" >/dev/null 2>&1
		if "$BASE/work/ssh.sh" true 2>/dev/null; then
			echo "Linux is up ($(($i * 3))s)"
			exit 0
		fi
	fi
	sleep 3
done
echo "timed out waiting for Linux"
exit 1
