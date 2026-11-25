#!/bin/bash
# Builds Keyflow and wraps the binary in a double-clickable Keyflow.app.
# Usage: Scripts/build-app.sh [debug|release]   (default: release)
#
# Optional settings, from the environment (Scripts/release-beta.sh sets them):
#   KEYFLOW_VERSION         CFBundleShortVersionString (default 1.0)
#   KEYFLOW_BUILD           CFBundleVersion (default 1)
#   KEYFLOW_CHANNEL         release channel shown after the version, e.g. "Beta 1" (default none)
#   KEYFLOW_FEEDBACK_EMAIL  address for Settings ▸ About ▸ Send Beta Feedback (default none: no button)
#   KEYFLOW_UNIVERSAL=1     build for Apple silicon and Intel (default: this Mac only)
#   KEYFLOW_APP             where to put the app (default build/Keyflow.app)
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
VERSION="${KEYFLOW_VERSION:-1.0}"
BUILD="${KEYFLOW_BUILD:-1}"
CHANNEL="${KEYFLOW_CHANNEL:-}"
FEEDBACK_EMAIL="${KEYFLOW_FEEDBACK_EMAIL:-}"
APP="${KEYFLOW_APP:-build/Keyflow.app}"
source Scripts/toolchain.sh
SDK=(${SDK_ARGS[@]+"${SDK_ARGS[@]}"})
ARCHS=()
if [[ "${KEYFLOW_UNIVERSAL:-0}" == 1 ]]; then ARCHS=(--arch arm64 --arch x86_64); fi

for value in "$VERSION" "$BUILD" "$CHANNEL" "$FEEDBACK_EMAIL"; do
    if [[ "$value" == *[\<\>\&\"]* ]]; then echo "error: '$value' contains <, >, & or \"" >&2; exit 1; fi
done
if [[ -n "$FEEDBACK_EMAIL" && ! "$FEEDBACK_EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
    echo "error: '$FEEDBACK_EMAIL' is not an email address" >&2; exit 1
fi

swift build -c "$CONFIG" --product Keyflow ${SDK[@]+"${SDK[@]}"} ${ARCHS[@]+"${ARCHS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path ${SDK[@]+"${SDK[@]}"} ${ARCHS[@]+"${ARCHS[@]}"})"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/Keyflow" "$APP/Contents/MacOS/Keyflow"

# Drop run-path entries that point into developer tools (the toolchain adds
# its own); every library Keyflow uses is part of macOS.
otool -l "$APP/Contents/MacOS/Keyflow" | awk '/LC_RPATH/ {getline; getline; print $2}' | sort -u | while read -r rpath; do
    case "$rpath" in
        /Library/Developer/*|/Applications/Xcode*) install_name_tool -delete_rpath "$rpath" "$APP/Contents/MacOS/Keyflow" 2>/dev/null ;;
    esac
done

# Record the SDK the app was actually compiled against. With the Command Line
# Tools the linker can stamp the binary with the deployment target (15.0) as
# its SDK version, and macOS then shows the pre-26 design: an opaque sidebar
# instead of Liquid Glass. The minimum system version stays 15.0.
SDK_PATH="${SDK[1]:-$(xcrun --sdk macosx --show-sdk-path)}"
SDK_VERSION="$(plutil -extract Version raw "$SDK_PATH/SDKSettings.plist" 2>/dev/null || true)"
if [[ -n "$SDK_VERSION" ]]; then
    vtool -set-build-version macos 15.0 "$SDK_VERSION" -replace \
        -output "$APP/Contents/MacOS/Keyflow" "$APP/Contents/MacOS/Keyflow"
fi

# App icon, built from Assets/AppIcon/Source (see build-icon.sh there).
mkdir -p "$APP/Contents/Resources"
cp Assets/AppIcon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

EXTRA=""
if [[ -n "$CHANNEL" ]]; then EXTRA+="    <key>KeyflowReleaseChannel</key><string>$CHANNEL</string>"$'\n'; fi
if [[ -n "$FEEDBACK_EMAIL" ]]; then EXTRA+="    <key>KeyflowFeedbackEmail</key><string>$FEEDBACK_EMAIL</string>"$'\n'; fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Keyflow</string>
    <key>CFBundleDisplayName</key><string>Keyflow</string>
    <key>CFBundleIdentifier</key><string>app.keyflow.Keyflow</string>
    <key>CFBundleExecutable</key><string>Keyflow</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
$EXTRA</dict>
</plist>
PLIST

# Ad-hoc signature: enough for macOS to run the app and check it was not
# altered, but not a Developer ID signature, and not notarized.
plutil -lint -s "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc codesign failed"
echo "Built $APP"
