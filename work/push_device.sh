#!/usr/bin/env bash
# Push work/device/ onto the tablet's SD rootfs (over the RNDIS ssh link).
# Layout inside work/device mirrors the target filesystem, except:
#   usr-local-bin/  ->  /usr/local/bin/
#   root/           ->  /root/
set -euo pipefail
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$BASE/work/device"
SSH="$BASE/work/ssh.sh"

$SSH 'mkdir -p /etc/X11/xorg.conf.d /usr/local/bin /root/.icewm /var/log'

# plain files (path preserved under /)
(cd "$SRC" && find . -type f -not -path './usr-local-bin/*' -not -path './root/*' -printf '%P\n') |
	while read -r f; do
		$SSH "mkdir -p /$(dirname "$f") && cat > /$f" <"$SRC/$f"
		echo "  -> /$f"
	done

# /usr/local/bin
for f in "$SRC"/usr-local-bin/*; do
	b=$(basename "$f")
	$SSH "cat > /usr/local/bin/$b && chmod 755 /usr/local/bin/$b" <"$f"
	echo "  -> /usr/local/bin/$b"
done

# /root
(cd "$SRC/root" && find . -type f -printf '%P\n') |
	while read -r f; do
		$SSH "mkdir -p /root/$(dirname "$f") && cat > /root/$f" <"$SRC/root/$f"
		echo "  -> /root/$f"
	done

$SSH 'chmod 755 /root/.icewm/startup 2>/dev/null; chmod 600 /root/.icewm/preferences 2>/dev/null; true'
echo "sync done"
