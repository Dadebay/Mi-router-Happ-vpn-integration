#!/bin/sh
set -eu

PROJECT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP=${1:-"$HOME/Applications/HappRouter.app"}
FONTS=${HAPP_ROUTER_FONTS:-"$HOME/Developer/apps/projects/food_delivery/food_delivery/assets/fonts"}
VALIDATOR="$PROJECT/Tools/xray-validator"

cd "$PROJECT"
swift build -c release
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
cp .build/release/HappRouter "$APP/Contents/MacOS/HappRouter"
cp Scripts/routerctl.py "$APP/Contents/Resources/routerctl.py"
if [ -x "$VALIDATOR" ]; then
  cp "$VALIDATOR" "$APP/Contents/Resources/xray-validator"
fi
for name in Gilroy-Regular.ttf Gilroy-Medium.ttf Gilroy-SemiBold.ttf Gilroy-Bold.ttf Gilroy-Extrabold.ttf QurovaDEMO-Medium.otf; do
  if [ -f "$FONTS/$name" ]; then
    cp "$FONTS/$name" "$APP/Contents/Resources/Fonts/$name"
  fi
done
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>HappRouter</string>
<key>CFBundleExecutable</key><string>HappRouter</string>
<key>CFBundleIdentifier</key><string>local.dadebay.HappRouter</string>
<key>CFBundleName</key><string>HappRouter</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $APP"
