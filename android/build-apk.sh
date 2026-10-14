#!/bin/sh
set -eu
cd "$(dirname "$0")"

sdk=${ANDROID_HOME:-"$HOME/Library/Android/sdk"}
test -d "$sdk" || { echo 'Android SDK bulunamadı.' >&2; exit 1; }
printf 'sdk.dir=%s\n' "$sdk" > local.properties

hosts="$HOME/.happ-router/known_hosts"
test -s "$hosts" || { echo 'Router host anahtarı bulunamadı.' >&2; exit 1; }
awk '$1 == "192.168.1.1" && $2 ~ /^ssh-(rsa|ed25519)$/ {print}' "$hosts" \
    > app/src/main/assets/router_known_hosts
test -s app/src/main/assets/router_known_hosts || {
    echo '192.168.1.1 için güvenilir SSH host anahtarı bulunamadı.' >&2; exit 1;
}

secret_dir="$HOME/.happ-router"
mkdir -p "$secret_dir"
chmod 700 "$secret_dir"
signing="$secret_dir/android-signing.properties"
keystore="$secret_dir/android-release.jks"
if [ ! -s "$signing" ]; then
    password=$(openssl rand -hex 24)
    export HAPP_ANDROID_SIGNING_PASSWORD="$password"
    keytool -genkeypair -noprompt -keystore "$keystore" -alias happrouter \
        -keyalg RSA -keysize 3072 -validity 9125 \
        -dname 'CN=HappRouter Android' \
        -storepass:env HAPP_ANDROID_SIGNING_PASSWORD \
        -keypass:env HAPP_ANDROID_SIGNING_PASSWORD >/dev/null
    umask 077
    printf 'storeFile=%s\nstorePassword=%s\nkeyAlias=happrouter\nkeyPassword=%s\n' \
        "$keystore" "$password" "$password" > "$signing"
    unset HAPP_ANDROID_SIGNING_PASSWORD password
fi
cp "$signing" signing.properties
chmod 600 signing.properties

./gradlew :app:assembleRelease
mkdir -p ../dist
cp app/build/outputs/apk/release/app-release.apk ../dist/HappRouter-Android.apk
shasum -a 256 ../dist/HappRouter-Android.apk
