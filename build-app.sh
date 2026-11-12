#!/bin/bash
# Builds "Black Ops Mac.app" (with the kit inside) into dist/.
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")" && pwd)
version=$(cat "$root/kit/VERSION")
app="$root/dist/Black Ops Mac.app"
build="$root/.build"

echo "==> Compiling the app"
swift build -c release --package-path "$root/app" --scratch-path "$build/swift" >/dev/null
bin=$(swift build -c release --package-path "$root/app" --scratch-path "$build/swift" --show-bin-path)/BlackOpsMac

echo "==> Drawing the icon"
rm -rf "$build/AppIcon.iconset"
swiftc -O -o "$build/make-icon" "$root/app/make-icon.swift"
"$build/make-icon" "$build/AppIcon.iconset"
iconutil -c icns -o "$build/AppIcon.icns" "$build/AppIcon.iconset"

echo "==> Assembling $app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/BlackOpsMac"
cp "$build/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
ditto "$root/kit" "$app/Contents/Resources/kit"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Black Ops Mac</string>
  <key>CFBundleDisplayName</key><string>Black Ops Mac</string>
  <key>CFBundleIdentifier</key><string>io.github.blackopsmac</string>
  <key>CFBundleExecutable</key><string>BlackOpsMac</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Black Ops Mac uses the microphone for in-game voice chat in Black Ops and Black Ops II.</string>
</dict>
</plist>
EOF
xattr -cr "$app"   # Finder info and other extended attributes stop codesign
codesign -fs - --deep "$app" 2>/dev/null
echo "==> Built $app ($(du -sh "$app" | cut -f1))"
