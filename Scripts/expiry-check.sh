#!/bin/sh
# Cron calls this every five minutes; ignore unset clocks after a power loss.
set -eu
EXPIRES=/etc/happvpn/expires-at
[ -r "$EXPIRES" ] || exit 0
expires=$(cat "$EXPIRES")
case "$expires" in *[!0-9]*|'') exit 0;; esac
now=$(date +%s)
[ "$now" -gt 1760000000 ] || exit 0
if [ "$now" -ge "$expires" ]; then
    /etc/happvpn/mode.sh direct
fi
