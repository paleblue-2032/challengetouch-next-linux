#!/usr/bin/env bash
# Try to switch the MTK preloader into FASTBOOT mode via its serial port.
# Requires /dev/ttyACM0 to be readable (the user chmod loop must be running).
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$BASE/work/mtk-bootseq.py"

for attempt in $(seq 1 80); do
	timeout 6 python3 "$SCRIPT" FASTBOOT /dev/ttyACM0 2>&1 | tr '\n' ' '
	echo " (attempt $attempt)"
	if fastboot devices 2>/dev/null | grep -q fastboot; then
		echo "FASTBOOT_OK"
		fastboot devices
		exit 0
	fi
	sleep 1
done
echo "FASTBOOT_FAILED"
exit 1
