#!/bin/sh
# Runs on the router after Android has uploaded staged Shadowsocks profiles.
set -eu
base=/etc/happvpn
stage="$base/profiles.mobile-stage"
backup="$base/mobile-rollback"
pid=/tmp/happ-mobile-candidate.pid
success=0
switched=0
moved_old=0

cleanup_candidate() {
    if [ -s "$pid" ]; then kill "$(cat "$pid")" 2>/dev/null || true; fi
    rm -f "$pid" /tmp/happ-mobile-candidate.log
}

finish() {
    result=$?
    trap - 0 HUP INT TERM
    set +e
    cleanup_candidate
    if [ "$success" != 1 ]; then
        if [ "$moved_old" = 1 ]; then
            rm -rf "$base/profiles"
            mv "$base/profiles.mobile-old" "$base/profiles" 2>/dev/null || true
        fi
        if [ -d "$backup" ]; then
            if [ -s "$backup/nodes.json" ]; then
                cp "$backup/nodes.json" "$base/nodes.json"
            else
                rm -f "$base/nodes.json"
            fi
            if [ -s "$backup/probes.tsv" ]; then
                cp "$backup/probes.tsv" "$base/probes.tsv"
            else
                rm -f "$base/probes.tsv"
            fi
            if [ "$switched" = 1 ]; then
                cp "$backup/ss-client.json" "$base/ss-client.json" 2>/dev/null || true
                /etc/init.d/happ-ss restart >/dev/null 2>&1 || true
                /etc/happvpn/mode.sh "$previous_mode" >/dev/null 2>&1 || true
            fi
        fi
        printf '%s' "$previous_active" > "$base/active-outbound"
        printf '%s' "$previous_expiry" > "$base/expires-at"
        printf '%s' "$previous_selection" > "$base/selection-mode"
    fi
    rm -rf "$backup" "$stage"
    rm -f "$base/nodes.mobile-stage" "$base/probes.mobile-stage" \
        "$base/selected.mobile-stage" "$base/expires.mobile-stage"
    exit "$result"
}

test -d "$stage" && test -s "$base/nodes.mobile-stage" && test -s "$base/probes.mobile-stage"
tag=$(cat "$base/selected.mobile-stage")
case "$tag" in ss-[0-9][0-9]|ss-[0-9][0-9][0-9]) ;; *) exit 2 ;; esac
test -s "$stage/$tag.json"
expiry=$(cat "$base/expires.mobile-stage")
case "$expiry" in ''|*[!0-9]*) exit 2 ;; esac
test "$expiry" -gt "$(date +%s)"
test -s "$base/ss-client.json" && test -d "$base/profiles"
test -x "$base/node-helper.lua" && test -x "$base/mode.sh"

previous_mode=$(cat "$base/mode" 2>/dev/null || echo vpn)
case "$previous_mode" in vpn|direct) ;; *) previous_mode=vpn ;; esac
previous_selection=$(cat "$base/selection-mode" 2>/dev/null || echo auto)
case "$previous_selection" in auto|manual) ;; *) previous_selection=auto ;; esac
previous_active=$(cat "$base/active-outbound" 2>/dev/null || echo happ-vpn)
previous_expiry=$(cat "$base/expires-at" 2>/dev/null || echo 0)
rm -rf "$backup"
umask 077
mkdir "$backup"
cp "$base/ss-client.json" "$backup/ss-client.json"
cp "$base/nodes.json" "$backup/nodes.json" 2>/dev/null || true
cp "$base/probes.tsv" "$backup/probes.tsv" 2>/dev/null || true
trap 'finish' 0
trap 'exit 1' HUP INT TERM

printf manual > "$base/selection-mode"
ss-local -c "$stage/$tag.json" -b 127.0.0.1 -l 11082 \
    -f "$pid" >/tmp/happ-mobile-candidate.log 2>&1
sleep 1
"$base/node-helper.lua" check 11082 >/dev/null
cleanup_candidate

cp "$stage/$tag.json" "$base/ss-client.json.new"
chmod 600 "$base/ss-client.json.new"
mv "$base/ss-client.json.new" "$base/ss-client.json"
switched=1
/etc/init.d/happ-ss restart >/dev/null
exit_ip=$("$base/node-helper.lua" check 1080)
"$base/mode.sh" vpn >/dev/null

rm -rf "$base/profiles.mobile-old"
mv "$base/profiles" "$base/profiles.mobile-old"
moved_old=1
mv "$stage" "$base/profiles"
mv "$base/nodes.mobile-stage" "$base/nodes.json"
mv "$base/probes.mobile-stage" "$base/probes.tsv"
printf '%s' "$tag" > "$base/active-outbound"
printf '%s' "$expiry" > "$base/expires-at"
printf auto > "$base/selection-mode"
"$base/probe-nodes.lua" >/dev/null 2>&1 || true
rm -rf "$base/profiles.mobile-old"
success=1
printf '%s\n' "$exit_ip"
