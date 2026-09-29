#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="PersonalControlCenter"
BUNDLE_ID="org.sceneharbor.PersonalControlCenter"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
DERIVED_DATA="$ROOT_DIR/DerivedData"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/Personal Control Center.app"

if [[ "$MODE" != "--build-only" ]]; then
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

if xcodebuild -version >/dev/null 2>&1; then
    xcodebuild \
        -project "$ROOT_DIR/PersonalControlCenter.xcodeproj" \
        -scheme PersonalControlCenter \
        -configuration Debug \
        -derivedDataPath "$DERIVED_DATA" \
        -destination "platform=macOS,arch=arm64" \
        CODE_SIGNING_ALLOWED=NO \
        build
    APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/PersonalControlCenter.app"
else
    # This CLT's macOS 27 SDK lacks SwiftUIMacros. Prefer the installed
    # macOS 26 SDK, while allowing an explicit caller-selected SDK.
    if [[ -z "${SDKROOT:-}" ]]; then
        if [[ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk" ]]; then
            export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
        else
            export SDKROOT="$(xcrun --show-sdk-path)"
        fi
    fi
    export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-cache"
    export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/swiftpm-cache"
    swift build --package-path "$ROOT_DIR"
    BUILD_BINARY="$(swift build --package-path "$ROOT_DIR" --show-bin-path)/$APP_NAME"
    APP_CONTENTS="$APP_BUNDLE/Contents"
    APP_MACOS="$APP_CONTENTS/MacOS"

    rm -rf "$APP_BUNDLE"
    mkdir -p "$APP_MACOS"
    cp "$BUILD_BINARY" "$APP_MACOS/$APP_NAME"
    cp "$ROOT_DIR/PersonalControlCenter/Info.plist" "$APP_CONTENTS/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$APP_CONTENTS/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_CONTENTS/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName Personal Control Center" "$APP_CONTENTS/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Personal Control Center" "$APP_CONTENTS/Info.plist"
    chmod +x "$APP_MACOS/$APP_NAME"
fi

bash "$ROOT_DIR/script/probe_refresh_pulse.sh" --help
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$ROOT_DIR/.build/probe-refresh-pulse" "$APP_BUNDLE/Contents/Resources/probe-refresh-pulse"
chmod +x "$APP_BUNDLE/Contents/Resources/probe-refresh-pulse"

APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

open_app() {
    if [[ "$MODE" == "--enable-refresh-return" ]]; then
        /usr/bin/open -n "$APP_BUNDLE" --args --enable-refresh-return
    else
        /usr/bin/open -n "$APP_BUNDLE"
    fi
}

case "$MODE" in
    --build-only)
        echo "Built: $APP_BUNDLE (not launched; not notarized)"
        ;;
    run|--enable-refresh-return)
        open_app
        ;;
    --debug|debug)
        lldb -- "$APP_BINARY"
        ;;
    --logs|logs)
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
        ;;
    --telemetry|telemetry)
        open_app
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
        ;;
    --verify|verify)
        open_app
        sleep 2
        pgrep -x "$APP_NAME" >/dev/null
        ;;
    *)
        echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2
        exit 2
        ;;
esac
