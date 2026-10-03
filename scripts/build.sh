#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/Application Atlas.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/module-cache
VERSION="${ATLAS_VERSION:-$(cat VERSION)}"
BUILD_NUMBER="${ATLAS_BUILD_NUMBER:-9}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version must be X.Y.Z" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "Build number must be numeric" >&2; exit 1; }
ARCHS="${ATLAS_ARCHS:-$(uname -m)}"
source scripts/toolchain.sh
BINARIES=()
for arch in $ARCHS; do
    case "$arch" in arm64|x86_64) ;; *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; esac
    swiftc -O -parse-as-library "${SWIFT_FLAGS[@]}" Sources/*.swift -o "build/ApplicationAtlas-$arch" -framework SwiftUI -framework AppKit -framework MapKit -framework CoreLocation -target "$arch-apple-macosx14.0"
    BINARIES+=("build/ApplicationAtlas-$arch")
done
[[ ${#BINARIES[@]} -gt 0 ]] || { echo "Specify at least one architecture" >&2; exit 1; }
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/ApplicationAtlas"
./scripts/icon.sh
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Assets/AppIcon.png "$APP/Contents/Resources/AppIcon.png"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ApplicationAtlas</string>
<key>CFBundleIdentifier</key><string>local.applicationatlas.mac</string>
<key>CFBundleName</key><string>Application Atlas</string>
<key>CFBundleDisplayName</key><string>Application Atlas</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION; $ARCHS)"
