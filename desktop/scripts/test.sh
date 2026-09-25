#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p desktop/build/module-cache
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/desktop/build/module-cache" \
  desktop/Sources/Models.swift desktop/Sources/GitHub.swift desktop/Tests/Tests.swift \
  -o desktop/build/semantic-tests -framework Security
./desktop/build/semantic-tests

xcrun swiftc -swift-version 5 -module-cache-path "$PWD/desktop/build/module-cache" \
  desktop/Sources/Models.swift desktop/Sources/GitHub.swift desktop/Sources/AppModel.swift desktop/Sources/ProtegiaTheme.swift desktop/Sources/TokenPicker.swift desktop/Sources/TokenPreview.swift desktop/Sources/Views.swift desktop/Tests/PickerTests.swift \
  -o desktop/build/picker-tests -framework AppKit -framework SwiftUI -framework ApplicationServices
./desktop/build/picker-tests -pickerRequested YES -pickerAllApps YES

python3 desktop/Tests/test_release.py
python3 desktop/Tests/test_signing.py
python3 desktop/Tests/test_update_config.py
python3 desktop/Tests/test_github_config.py
bash desktop/scripts/fetch-sparkle.sh
sparkle="$PWD/desktop/build/dependencies/Sparkle-2.10.0"
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/desktop/build/module-cache" \
  desktop/Sources/UpdateConfiguration.swift desktop/Tests/UpdateTests.swift \
  -F "$sparkle" -framework Sparkle -Xlinker -rpath -Xlinker "$sparkle" \
  -o desktop/build/update-tests
./desktop/build/update-tests
