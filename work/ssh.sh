#!/usr/bin/env bash
# SSH into the tablet over the USB RNDIS link (host 10.0.0.1 -> device 10.0.0.2).
# Uses the dedicated cpad key; host key checking is disabled (throwaway host).
exec ssh -i "$HOME/.ssh/cpad_ed25519" \
	-o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null \
	-o LogLevel=ERROR \
	-o ConnectTimeout=6 \
	root@10.0.0.2 "$@"
