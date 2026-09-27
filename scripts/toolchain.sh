#!/bin/bash
# Sourced from build/test scripts after switching to the project directory.
SWIFT_FLAGS=(-module-cache-path build/module-cache)
TOOLCHAIN_ROOT="$(xcode-select -p)"
OLD_MAP="$TOOLCHAIN_ROOT/usr/include/swift/module.modulemap"
NEW_MAP="$TOOLCHAIN_ROOT/usr/include/swift/bridging.modulemap"
if [[ -f "$OLD_MAP" && -f "$NEW_MAP" ]] && grep -q 'module SwiftBridging' "$OLD_MAP" && grep -q 'module SwiftBridging' "$NEW_MAP"; then
    # Some upgraded Command Line Tools retain both module definitions.
    # Hide the obsolete map only for this compiler invocation, without modifying the installation.
    mkdir -p build
    python3 - "$OLD_MAP" <<'PY'
import json, pathlib, sys
root = pathlib.Path('build').resolve()
(root / 'empty.modulemap').write_text('// Obsolete duplicate module map, hidden for this build.\n')
(root / 'toolchain-overlay.json').write_text(json.dumps({'version': 0, 'roots': [{'type': 'file', 'name': sys.argv[1], 'external-contents': str(root / 'empty.modulemap')}]}))
PY
    SWIFT_FLAGS+=(-vfsoverlay "$PWD/build/toolchain-overlay.json" -Xcc -ivfsoverlay -Xcc "$PWD/build/toolchain-overlay.json")
    if [[ -d "$TOOLCHAIN_ROOT/SDKs/MacOSX15.5.sdk" ]]; then
        SWIFT_FLAGS+=(-sdk "$TOOLCHAIN_ROOT/SDKs/MacOSX15.5.sdk")
    fi
fi
