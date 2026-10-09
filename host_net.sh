#!/usr/bin/env bash
# Configure the host for the tablet's USB RNDIS network (host side = 10.0.0.1).
# Re-run after the tablet reboots (the USB interface name can change).
set -u
UP=$(ip route show default 2>/dev/null | awk '/default/{print $5; exit}')
IF=""
for i in /sys/class/net/*; do
	n=$(basename "$i")
	drv=$(readlink -f "$i/device/driver" 2>/dev/null | xargs -r basename)
	case "$drv" in rndis_host|cdc_ether|cdc_ncm) IF="$n" ;; esac
done
if [ -z "$IF" ]; then echo "ERROR: no RNDIS/ethernet gadget interface found"; ip -br link; exit 1; fi
echo "uplink=$UP  rndis=$IF"
# Keep NetworkManager from fighting our manual addressing (it would flush the IP).
command -v nmcli >/dev/null 2>&1 && sudo nmcli dev set "$IF" managed no 2>/dev/null
sudo ip addr add 10.0.0.1/24 dev "$IF" 2>/dev/null
sudo ip link set "$IF" up
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
sudo iptables -I FORWARD 1 -i "$IF" -j ACCEPT
sudo iptables -I FORWARD 1 -o "$IF" -j ACCEPT
sudo iptables -I INPUT 1 -i "$IF" -j ACCEPT
sudo iptables -t nat -C POSTROUTING -o "$UP" -j MASQUERADE 2>/dev/null || sudo iptables -t nat -A POSTROUTING -o "$UP" -j MASQUERADE
echo "--- $IF ---"; ip -br addr show "$IF"
echo "--- test from host: ping device ---"; ping -c 1 -W 2 10.0.0.2 2>&1 | tail -n 2
