#!/bin/sh
# build.sh: DJ Mantra Ableton Remote.app, swiftc straight, no Xcode, signed "Mantra Apps" (MANTRA_MANIFEST
# mac-app-signing.md, swift-apps.md). The version is the one number in app/App.swift.
set -e
cd "$(dirname "$0")"
V=$(sed -n 's/^let VERSION = \([0-9]*\)/\1/p' app/App.swift)
NAME="DJ Mantra Ableton Remote"
APP="build/$NAME.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -parse-as-library -o "$APP/Contents/MacOS/DJMantraAbletonRemote" app/*.swift Sources/E16/*.swift
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>$NAME</string>
<key>CFBundleDisplayName</key><string>$NAME</string>
<key>CFBundleIdentifier</key><string>community.auroville.djmantraabletonremote</string>
<key>CFBundleExecutable</key><string>DJMantraAbletonRemote</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$V</string>
<key>CFBundleVersion</key><string>$V</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
codesign --force -s "Mantra Apps" "$APP"
rm -rf "/Applications/$NAME.app"; cp -R "$APP" /Applications/
echo "built $APP (v$V) and installed it in /Applications"
