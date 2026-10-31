#!/bin/sh
# build.sh: DJ Mantra Ableton Remote for OXI E16 (Mantra).app, swiftc straight, no Xcode, signed "Mantra Apps" (MANTRA_MANIFEST
# mac-app-signing.md, swift-apps.md). The version is the one number in app/App.swift.
set -e
cd "$(dirname "$0")"
V=$(sed -n 's/^let VERSION = \([0-9]*\)/\1/p' app/App.swift)
NAME="E16 Ableton Remote (Mantra)"
APP="build/$NAME.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -parse-as-library -o "$APP/Contents/MacOS/DJMantraAbletonRemote" app/*.swift Sources/E16/*.swift
# the icon carries the version (version-visible.md): drawn again at every build
(cd icon && swift make_icon.swift "$V" >/dev/null)
I=build/AppIcon.iconset; rm -rf $I; mkdir -p $I
for s in 16 32 128 256 512; do
  sips -z $s $s icon/icon_1024.png --out $I/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) icon/icon_1024.png --out $I/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $I -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>$NAME</string>
<key>CFBundleDisplayName</key><string>$NAME</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
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
rm -rf "/Applications/DJ Mantra Ableton Remote.app" "/Applications/DJ Mantra Ableton Remote for OXI E16 (Mantra).app" "/Applications/$NAME.app"; cp -R "$APP" /Applications/
echo "built $APP (v$V) and installed it in /Applications"

# v27 (Marko, 29.10.2026): E16 FOR DAVINCI RESOLVE, the same program as its own app (its identifier says "resolve", so
# it starts as the Resolve mixer: SOLO, MUTE, VOLUME, PAN of four audio tracks a page). Only one of the two may hold
# the E16 at a time.
R="build/E16 for DaVinci Resolve (Mantra).app"
rm -rf "$R"; cp -R "$APP" "$R"
plutil -replace CFBundleIdentifier -string community.auroville.e16resolve "$R/Contents/Info.plist"
plutil -replace CFBundleName -string "E16 for DaVinci Resolve (Mantra)" "$R/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "E16 for DaVinci Resolve (Mantra)" "$R/Contents/Info.plist"
codesign --force -s "Mantra Apps" "$R"
rm -rf "/Applications/E16 for DaVinci Resolve (Mantra).app"; cp -R "$R" /Applications/
echo "built $R (v$V) and installed it in /Applications"
