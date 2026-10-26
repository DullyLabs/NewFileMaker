#!/bin/zsh
set -e
cd "${0:A:h}"
APP=NewFileMaker.app
rm -rf $APP && mkdir -p $APP/Contents/{MacOS,Resources}
swiftc -O main.swift -o $APP/Contents/MacOS/NewFileMaker
cp AppIcon.icns $APP/Contents/Resources/AppIcon.icns
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>NewFileMaker</string>
<key>CFBundleIdentifier</key><string>com.dulangaj.NewFileMaker</string>
<key>CFBundleName</key><string>New File Maker</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSUIElement</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Reads the folder open in Finder.</string>
</dict></plist>
PLIST
ID=5D2G58P6ZB; security find-identity -v -p codesigning | grep -q $ID || ID=-
codesign -s $ID --options runtime --entitlements NewFileMaker.entitlements -i com.dulangaj.NewFileMaker --force $APP
echo "Built $PWD/$APP"
