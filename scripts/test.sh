#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
source scripts/toolchain.sh
swiftc -parse-as-library "${SWIFT_FLAGS[@]}" Sources/Models.swift Sources/Categories.swift Sources/Backup.swift Sources/MapLocations.swift Sources/Pipeline.swift Tests/StorageTests.swift -o build/storage-tests -framework SwiftUI -framework AppKit -framework MapKit -framework CoreLocation
./build/storage-tests
swiftc -parse-as-library "${SWIFT_FLAGS[@]}" Sources/Models.swift Sources/Categories.swift Sources/Backup.swift Sources/MapLocations.swift Tests/BackupTests.swift -o build/backup-tests -framework SwiftUI -framework AppKit -framework MapKit -framework CoreLocation
./build/backup-tests
swiftc -parse-as-library "${SWIFT_FLAGS[@]}" Sources/Models.swift Sources/Categories.swift Sources/Backup.swift Sources/MapLocations.swift Sources/Pipeline.swift Tests/CategoryTests.swift -o build/category-tests -framework SwiftUI -framework AppKit -framework MapKit -framework CoreLocation
./build/category-tests
