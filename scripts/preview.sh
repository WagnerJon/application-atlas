#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
APP="build/${ATLAS_PREVIEW_NAME:-Atlas Preview}.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
./scripts/icon.sh
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp Assets/AppIcon.png "$APP/Contents/Resources/AppIcon.png"
python3 - <<'PY'
from pathlib import Path
source = Path('Sources/App.swift').read_text()
Path('build/PreviewContent.swift').write_text('import SwiftUI\nimport AppKit\n' + source[source.index('extension Notification.Name'):])
PY
swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" "${SWIFT_FLAGS[@]}" Sources/Models.swift Sources/Categories.swift Sources/Backup.swift Sources/MapLocations.swift Sources/Pipeline.swift Sources/Sankey.swift Sources/Editor.swift Sources/SettingsMenu.swift Sources/CategoryManager.swift Sources/ApplicationMapView.swift build/PreviewContent.swift Tests/Preview.swift -o "$APP/Contents/MacOS/AtlasPreview" -framework SwiftUI -framework AppKit -framework MapKit -framework CoreLocation
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>AtlasPreview</string><key>CFBundleIdentifier</key><string>local.applicationatlas.preview</string><key>CFBundleName</key><string>Atlas Preview</string><key>CFBundleIconFile</key><string>AppIcon</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${ATLAS_PREVIEW_ID:-local.applicationatlas.preview}" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
