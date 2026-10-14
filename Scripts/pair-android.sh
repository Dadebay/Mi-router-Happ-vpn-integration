#!/bin/sh
# Append a public key generated on the phone to the router's SSH allowlist.
set -eu
home="$HOME/.happ-router"
test -s "$home/router_rsa" && test -s "$home/known_hosts" || {
    echo 'Mac router SSH anahtarı bulunamadı.' >&2; exit 1;
}
if [ "$#" -gt 0 ]; then
    key=$(cat "$1")
else
    key=$(cat)
fi
case "$key" in
    'ssh-rsa '*|'ssh-ed25519 '*) ;;
    *) echo 'Açık anahtar biçimi geçersiz.' >&2; exit 1 ;;
esac
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT HUP INT TERM
printf '%s\n' "$key" > "$tmp"
ssh-keygen -lf "$tmp" -E sha256 >/dev/null || {
    echo 'Açık anahtar doğrulanamadı.' >&2; exit 1;
}
ssh -i "$home/router_rsa" -o BatchMode=yes -o StrictHostKeyChecking=yes \
    -o "UserKnownHostsFile=$home/known_hosts" root@192.168.1.1 \
    'umask 077; mkdir -p /etc/dropbear; touch /etc/dropbear/authorized_keys; chmod 600 /etc/dropbear/authorized_keys; read -r key; grep -Fqx "$key" /etc/dropbear/authorized_keys || printf "%s\n" "$key" >> /etc/dropbear/authorized_keys' \
    < "$tmp"
echo 'Telefon anahtarı router üzerinde yetkilendirildi.'
