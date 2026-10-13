#!/bin/sh
# One root-only OpenWrt configuration and diagnostic snapshot per UTC day.
set -eu
umask 077

BACKUP_DIR=/etc/happvpn/backups
DAY=$(date -u +%Y-%m-%d)
MAX_ARCHIVE_BYTES=98304
MAX_TOTAL_KB=384
MIN_FREE_KB=512

mkdir -p "$BACKUP_DIR"
find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.tar.gz' -mtime +29 -exec rm -f {} \;

work=$(mktemp -d /tmp/happvpn-backup.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/happvpn/profiles" "$work/openwrt"

for name in ss-client.json nodes.json mode expires-at selection-mode active-outbound blocked-macs; do
    [ ! -f "/etc/happvpn/$name" ] || cp "/etc/happvpn/$name" "$work/happvpn/$name"
done
for file in /etc/happvpn/profiles/ss-*.json; do
    [ ! -f "$file" ] || cp "$file" "$work/happvpn/profiles/"
done
for name in network wireless firewall dhcp; do
    [ ! -f "/etc/config/$name" ] || cp "/etc/config/$name" "$work/openwrt/$name"
done

{
    printf 'UTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '\n== Router ==\n'
    ubus call system board 2>/dev/null | grep -E '"(model|release|version)"' | head -n 8 || true
    printf '\n== VPN durumu ==\n'
    printf 'mod: '; cat /etc/happvpn/mode 2>/dev/null || true; printf '\n'
    printf 'secim: '; cat /etc/happvpn/selection-mode 2>/dev/null || true; printf '\n'
    printf 'aktif: '; cat /etc/happvpn/active-outbound 2>/dev/null || true; printf '\n'
    netstat -lnt 2>/dev/null | grep -E ':1080 |:12345 ' || true
    printf '\n== Kaynaklar ==\n'
    cat /proc/uptime
    grep -E 'MemTotal:|MemAvailable:' /proc/meminfo || true
    df -k /overlay
    printf '\n== Ag sayaclari ==\n'
    cat /proc/net/dev
    printf '\n== Son sunucu olcumleri ==\n'
    tail -n 60 /tmp/happvpn/probe-results.tsv 2>/dev/null || true
    printf '\n== Bugunku cihaz kullanimi ==\n'
    tail -n 60 /tmp/happvpn/usage-today.tsv 2>/dev/null || true
    printf '\n== VPN olaylari ==\n'
    logread 2>/dev/null | grep -E 'happvpn|happ-ss|ss-local|ss-redir' | tail -n 80 || true
} > "$work/diagnostics.txt"

tar -czf "$work/snapshot.tar.gz" -C "$work" diagnostics.txt happvpn openwrt
archive_bytes=$(wc -c < "$work/snapshot.tar.gz" | tr -d ' ')
if [ "$archive_bytes" -gt "$MAX_ARCHIVE_BYTES" ]; then
    logger -t happvpn 'diagnostic backup skipped: archive too large'
    exit 1
fi
need_kb=$(( (archive_bytes + 1023) / 1024 + 2 ))

# Prune only our own oldest snapshots before writing to the tiny flash overlay.
while :; do
    set -- "$BACKUP_DIR"/*.tar.gz
    if [ -f "$1" ]; then count=$#; oldest=$1; else count=0; oldest=; fi
    used_kb=$(du -sk "$BACKUP_DIR" | awk '{print $1}')
    free_kb=$(df -k /overlay | awk 'NR == 2 {print $4}')
    if [ "$count" -lt 30 ] && [ $((used_kb + need_kb)) -le "$MAX_TOTAL_KB" ] &&
       [ "$free_kb" -ge $((MIN_FREE_KB + need_kb)) ]; then
        break
    fi
    if [ -z "$oldest" ] || [ "$oldest" = "$BACKUP_DIR/$DAY.tar.gz" ]; then
        logger -t happvpn 'diagnostic backup skipped: overlay has too little free space'
        exit 1
    fi
    rm -f "$oldest"
done

cp "$work/snapshot.tar.gz" "$BACKUP_DIR/.$DAY.new"
chmod 600 "$BACKUP_DIR/.$DAY.new"
mv -f "$BACKUP_DIR/.$DAY.new" "$BACKUP_DIR/$DAY.tar.gz"
logger -t happvpn "diagnostic backup saved: $DAY ($archive_bytes bytes)"
printf '%s %s\n' "$DAY" "$archive_bytes"
