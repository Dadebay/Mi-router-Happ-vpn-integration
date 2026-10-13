#!/bin/sh
# Choose the lowest-latency working profile unless the user pinned a server.
set -eu
BASE=/etc/happvpn
LOCK=/tmp/happvpn-switch.lock
PID=/tmp/happvpn-switch-candidate.pid

action=${1:-}
case "$action" in auto|enable-auto|manual) ;; *) echo 'usage: switch-node.sh {auto|enable-auto|manual TAG}' >&2; exit 2;; esac

if ! mkdir "$LOCK" 2>/dev/null; then
    [ "$action" = auto ] && exit 0
    echo 'Sunucu seçimi zaten sürüyor.' >&2
    exit 1
fi
cleanup() {
    if [ -s "$PID" ]; then
        kill "$(cat "$PID")" 2>/dev/null || true
    fi
    rm -f "$PID"
    rmdir "$LOCK" 2>/dev/null || true
}
trap cleanup 0 1 2 15

case "$action" in
    auto|enable-auto)
        # Measurements stay current even while a manual server is selected.
        "$BASE/probe-nodes.lua"
        if [ "$action" = enable-auto ]; then
            printf auto > "$BASE/selection-mode"
        fi
        [ "$(cat "$BASE/selection-mode" 2>/dev/null || echo auto)" = auto ] || exit 0
        [ "$(cat "$BASE/mode" 2>/dev/null || echo vpn)" = vpn ] || exit 0
        expires=$(cat "$BASE/expires-at" 2>/dev/null || echo 0)
        case "$expires" in *[!0-9]*|'') exit 0;; esac
        [ "$(date +%s)" -lt "$expires" ] || exit 0
        ;;
    manual)
        tag=${2:-}
        case "$tag" in ss-*) suffix=${tag#ss-};; *) echo 'Invalid server tag' >&2; exit 2;; esac
        case "$suffix" in ''|*[!0-9]*) echo 'Invalid server tag' >&2; exit 2;; esac
        [ -s "$BASE/profiles/$tag.json" ] || { echo 'Server profile unavailable' >&2; exit 1; }
        ;;
esac

if [ "$action" = manual ]; then
    candidates=$tag
else
    candidates=$(lua5.3 "$BASE/node-helper.lua" rank) || {
        logger -t happvpn 'auto: no reachable saved server'
        exit 1
    }
fi
active=$(cat "$BASE/active-outbound" 2>/dev/null || true)
for tag in $candidates; do
    candidate="$BASE/profiles/$tag.json"
    [ -s "$candidate" ] || continue
    if [ "$tag" = "$active" ]; then
        if lua5.3 "$BASE/node-helper.lua" check 1080 >/dev/null 2>&1; then
            [ "$action" != manual ] || printf manual > "$BASE/selection-mode"
            exit 0
        fi
    fi
    rm -f "$PID"
    if ! ss-local -c "$candidate" -b 127.0.0.1 -l 11082 -f "$PID" \
        >/tmp/happvpn-switch-candidate.log 2>&1; then
        continue
    fi
    sleep 1
    if ! lua5.3 "$BASE/node-helper.lua" check 11082 >/dev/null 2>&1; then
        kill "$(cat "$PID")" 2>/dev/null || true
        rm -f "$PID"
        continue
    fi
    kill "$(cat "$PID")" 2>/dev/null || true
    rm -f "$PID"
    cp "$BASE/ss-client.json" "$BASE/ss-client.json.last-good"
    cp "$candidate" "$BASE/ss-client.json.new"
    chmod 600 "$BASE/ss-client.json.new"
    mv "$BASE/ss-client.json.new" "$BASE/ss-client.json"
    if /etc/init.d/happ-ss restart \
        && lua5.3 "$BASE/node-helper.lua" check 1080 >/dev/null 2>&1; then
        printf '%s' "$tag" > "$BASE/active-outbound"
        if [ "$action" = manual ]; then
            printf manual > "$BASE/selection-mode"
        fi
        logger -t happvpn "server selection: active $tag ($action)"
        exit 0
    fi
    cp "$BASE/ss-client.json.last-good" "$BASE/ss-client.json"
    /etc/init.d/happ-ss restart || true
    logger -t happvpn "auto: $tag failed; previous server restored"
done
logger -t happvpn 'auto: no working replacement; previous server retained'
exit 1
