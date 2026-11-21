#!/bin/zsh
set -e
cd "${0:A:h}"
APP=NewFileMaker.app
rm -rf $APP && mkdir -p $APP/Contents/{MacOS,Resources}
swiftc -O main.swift Finder.swift Templates.swift EmailPDF.swift -o $APP/Contents/MacOS/NewFileMaker
cp AppIcon.icns Templates/* $APP/Contents/Resources/
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
<key>NSAppleEventsUsageDescription</key><string>Reads the folder open in Finder and the emails selected in Mail.</string>
<key>NSServices</key><array><dict>
<key>NSMenuItem</key><dict><key>default</key><string>Copy Full Path</string></dict>
<key>NSMessage</key><string>copyPath</string>
<key>NSPortName</key><string>NewFileMaker</string>
<key>NSRequiredContext</key><dict/>
<key>NSSendFileTypes</key><array><string>public.item</string></array>
</dict></array>
</dict></plist>
PLIST
ID=5D2G58P6ZB; security find-identity -v -p codesigning | grep -q $ID || ID=-
codesign -s $ID --options runtime --entitlements NewFileMaker.entitlements -i com.dulangaj.NewFileMaker --force $APP
sips -s format png AppIcon.icns --out Alfred/icon.png >/dev/null
rm -f NewFileMaker.alfredworkflow && (cd Alfred && zip -qr ../NewFileMaker.alfredworkflow .)
echo "Built $PWD/$APP and NewFileMaker.alfredworkflow"
