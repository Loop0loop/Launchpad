#!/bin/sh
set -eu

swift build

app=".build/Launch.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Resources/MenuBarIcon.png "$app/Contents/Resources/MenuBarIcon.png"
cp .build/debug/Launch "$app/Contents/MacOS/Launch"
chmod +x "$app/Contents/MacOS/Launch"

echo "$app"

