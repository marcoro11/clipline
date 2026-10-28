#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

# Keep compiler caches inside the project for restricted development environments.
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/swift-cache"
SWIFT_OPTIONS=(--disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" --manifest-cache local)
swift build "${SWIFT_OPTIONS[@]}" -c release -debug-info-format none
BIN_DIR="$(swift build "${SWIFT_OPTIONS[@]}" -c release --show-bin-path)"
APP_DIR="$PWD/build/Clipline.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/Clipline" "$APP_DIR/Contents/MacOS/Clipline.next"
mv -f "$APP_DIR/Contents/MacOS/Clipline.next" "$APP_DIR/Contents/MacOS/Clipline"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
python3 scripts/sign_app.py "$APP_DIR"
printf '\nBuilt %s\n' "$APP_DIR"
if [[ "${1:-}" == "--run" ]]; then
    /usr/bin/open "$APP_DIR"
fi
