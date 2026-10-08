#!/bin/sh
# Switch router forwarding between VPN-only and direct Internet.
set -eu
MODE_FILE=/etc/happvpn/mode
NFT_FILE=/etc/nftables.d/happvpn.nft
NFT_BACKUP=/etc/happvpn/happvpn.nft.vpn
FORWARDING=firewall.@forwarding[0].enabled

case "${1:-}" in
  direct)
    [ "$(cat "$MODE_FILE" 2>/dev/null || true)" = direct ] && exit 0
    [ -s "$NFT_BACKUP" ] || cp "$NFT_FILE" "$NFT_BACKUP"
    printf '%s\n' 'chain happvpn_prerouting { type filter hook prerouting priority mangle; policy accept; }' > "$NFT_FILE"
    uci set "$FORWARDING=1"
    uci commit firewall
    /etc/init.d/firewall reload
    printf direct > "$MODE_FILE"
    logger -t happvpn 'subscription expired: direct WAN sharing enabled'
    ;;
  vpn)
    [ "$(cat "$MODE_FILE" 2>/dev/null || true)" = vpn ] && exit 0
    [ -s "$NFT_BACKUP" ] || { echo 'VPN firewall backup missing' >&2; exit 1; }
    uci set "$FORWARDING=0"
    uci commit firewall
    cp "$NFT_BACKUP" "$NFT_FILE"
    /etc/init.d/firewall reload
    printf vpn > "$MODE_FILE"
    logger -t happvpn 'VPN-only forwarding enabled'
    ;;
  status)
    cat "$MODE_FILE" 2>/dev/null || printf vpn
    ;;
  *)
    echo 'usage: mode.sh {vpn|direct|status}' >&2
    exit 2
    ;;
esac
