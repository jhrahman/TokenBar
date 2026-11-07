#!/bin/zsh
# Builds a universal TokenBar.app (arm64 + x86_64) and zips it.
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(tr -d '[:space:]' < VERSION)   # single source of truth: edit the VERSION file to release
for a in arm64 x86_64; do swift build -c release --arch $a; done
APP=build/TokenBar.app
rm -rf build && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp Resources/AppIcon.icns $APP/Contents/Resources/
lipo -create .build/arm64-apple-macosx/release/TokenBar .build/x86_64-apple-macosx/release/TokenBar -output $APP/Contents/MacOS/TokenBar
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.tokenbar.app</string>
<key>CFBundleName</key><string>TokenBar</string>
<key>CFBundleExecutable</key><string>TokenBar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - $APP
lipo -archs $APP/Contents/MacOS/TokenBar
(cd build && ditto -c -k --keepParent TokenBar.app TokenBar-$VERSION.zip)

# Disk image: TokenBar.app next to an Applications shortcut, so installing is a drag.
STAGE=$(mktemp -d)
cp -R $APP "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "TokenBar" -srcfolder "$STAGE" -ov -format UDZO build/TokenBar-$VERSION.dmg >/dev/null
rm -rf "$STAGE"
echo "Built TokenBar $VERSION: $APP, build/TokenBar-$VERSION.dmg, build/TokenBar-$VERSION.zip"
