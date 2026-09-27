#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${ATLAS_VERSION:-$(cat VERSION)}"
export ATLAS_VERSION="$VERSION"
export ATLAS_ARCHS="arm64 x86_64"
./scripts/build.sh
lipo -verify_arch arm64 x86_64 "build/Application Atlas.app/Contents/MacOS/ApplicationAtlas"
mkdir -p dist
ARCHIVE="Application-Atlas-${VERSION}-macOS-universal.zip"
# ditto preserves the bundle's metadata and executable permissions.
ditto -c -k --sequesterRsrc --keepParent "build/Application Atlas.app" "dist/$ARCHIVE"
cp docs/INSTALL.md dist/INSTALL.md
cp LICENSE dist/LICENSE
(cd dist && shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt)
echo "Release files: dist/$ARCHIVE and dist/SHA256SUMS.txt"
