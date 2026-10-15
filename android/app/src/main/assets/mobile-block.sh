#!/bin/sh
# Update one device rule and roll back if fw4 cannot load it.
set -eu
mac=$1
action=$2
list=/etc/happvpn/blocked-macs
file=/etc/nftables.d/20-happ-router-block.nft
case "$mac" in
  *[!0-9a-f:]*|'') exit 2 ;;
esac
printf '%s\n' "$mac" | grep -Eq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' || exit 2
case "$action" in block|unblock) ;; *) exit 2 ;; esac

old=$(mktemp /tmp/happ-block-old.XXXXXX)
new=$(mktemp /tmp/happ-block-new.XXXXXX)
check=$(mktemp /tmp/happ-block-check.XXXXXX)
had_old=0
[ ! -f "$file" ] || { cp "$file" "$old"; had_old=1; }
success=0
finish() {
  if [ "$success" != 1 ]; then
    if [ "$had_old" = 1 ]; then cp "$old" "$file"; else rm -f "$file"; fi
    /etc/init.d/firewall reload >/dev/null 2>&1 || true
  fi
  rm -f "$old" "$new" "$check" "$file.new" "$list.new"
}
trap finish EXIT HUP INT TERM
umask 077
mkdir -p /etc/happvpn /etc/nftables.d
touch "$list"
grep -v -F -x "$mac" "$list" > "$list.new" || true
[ "$action" != block ] || printf '%s\n' "$mac" >> "$list.new"
sort -u "$list.new" -o "$list.new"

{
  printf 'set happ_router_blocked_macs {\n    type ether_addr;\n'
  values=
  while IFS= read -r item; do
    [ -z "$item" ] || values="${values:+$values, }$item"
  done < "$list.new"
  [ -z "$values" ] || printf '    elements = { %s };\n' "$values"
  printf '}\n'
  printf 'chain happ_router_block_proxy {\n'
  printf '    type filter hook input priority filter - 2; policy accept;\n'
  printf '    iifname "br-lan" ether saddr @happ_router_blocked_macs tcp dport 12345 drop\n}\n'
  printf 'chain happ_router_block_forward {\n'
  printf '    type filter hook forward priority filter - 2; policy accept;\n'
  printf '    iifname "br-lan" ether saddr @happ_router_blocked_macs drop\n}\n'
} > "$file.new"
mv "$file.new" "$file"
fw4 print > "$check"
nft -c -f "$check"
/etc/init.d/firewall reload
nft list chain inet fw4 happ_router_block_forward >/dev/null
nft list chain inet fw4 happ_router_block_proxy >/dev/null
mv "$list.new" "$list"
success=1
