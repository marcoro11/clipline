#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/swift-cache"
SWIFT_OPTIONS=(--disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" --manifest-cache local)

# Some Command Line Tools releases omit the Testing macro search path.
TOOLCHAIN_BIN="$(dirname "$(xcrun --find swiftc)")"
TESTING_PLUGIN="$TOOLCHAIN_BIN/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$TESTING_PLUGIN" ]]; then
    SWIFT_OPTIONS+=(-Xswiftc -load-plugin-library -Xswiftc "$TESTING_PLUGIN")
fi
swift test "${SWIFT_OPTIONS[@]}" -debug-info-format none
