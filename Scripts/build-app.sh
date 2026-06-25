#!/bin/sh
set -eu

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/clang-module-cache}"

xcrun swift build \
  --build-system xcode \
  --disable-sandbox \
  --cache-path .build/swiftpm-cache \
  --config-path .build/swiftpm-config \
  --security-path .build/swiftpm-security

app=".build/Launch.app"
binary=".build/apple/Products/Debug/Launch"

test -x "$binary"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"
if [ -f .env ]; then
  sparkle_feed_url="$(sed -n 's/^SPARKLE_FEED_URL=["'\'']\{0,1\}\([^"'\'']*\)["'\'']\{0,1\}$/\1/p' .env | head -n 1)"
  sparkle_public_key="$(sed -n 's/^SPARKLE_PUBLIC_ED_KEY=["'\'']\{0,1\}\([^"'\'']*\)["'\'']\{0,1\}$/\1/p' .env | head -n 1)"
  if [ -n "$sparkle_feed_url" ]; then
    /usr/libexec/PlistBuddy -c "Set :SUFeedURL $sparkle_feed_url" "$app/Contents/Info.plist"
  fi
  if [ -n "$sparkle_public_key" ]; then
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $sparkle_public_key" "$app/Contents/Info.plist"
  fi
fi
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Resources/MenuBarIcon.png "$app/Contents/Resources/MenuBarIcon.png"
cp Resources/AppIconColor.png "$app/Contents/Resources/AppIconColor.png"
cp Resources/AppIconMono.png "$app/Contents/Resources/AppIconMono.png"
if [ -d ".build/apple/Products/Debug/Frameworks" ]; then
  cp -R ".build/apple/Products/Debug/Frameworks" "$app/Contents/lib"
fi
cp "$binary" "$app/Contents/MacOS/Launch"
chmod +x "$app/Contents/MacOS/Launch"

echo "$app"
