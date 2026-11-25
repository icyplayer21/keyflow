#!/bin/bash
# Builds a Keyflow beta and packages it as a drag-and-drop DMG.
#
#   Scripts/release-beta.sh <beta number> [--replace]
#
# 1. Builds a universal (Apple silicon + Intel) Release app, version from
#    Scripts/release.config, build number = beta number, channel "Beta <n>".
# 2. Validates the bundle: Info.plist, icon, architectures, minimum macOS,
#    linked libraries and signature.
# 3. Packages dist/Keyflow-Beta-<n>-macOS.dmg (compressed, read-only) holding
#    Keyflow.app and an Applications shortcut.
# 4. Verifies the DMG, mounts it read-only, checks what is inside, unmounts.
# 5. Writes the tester README, checklist and a release report next to it.
#
# Working files go to build/release/beta-<n>; dist/ only gets the results.
# An existing DMG for the same beta is never replaced unless --replace is given.
# Nothing is uploaded anywhere.
#
# Signing: with no Developer ID certificate, the app is ad-hoc signed and not
# notarized. The report says so; testers allow it once in System Settings.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

BETA="${1:-}"
REPLACE="${2:-}"
if [[ ! "$BETA" =~ ^[1-9][0-9]*$ ]] || [[ -n "$REPLACE" && "$REPLACE" != "--replace" ]]; then
    echo "usage: Scripts/release-beta.sh <beta number> [--replace]" >&2; exit 2
fi
source Scripts/release.config

NAME="Keyflow-Beta-$BETA-macOS"
DIST="$ROOT/dist"
DMG="$DIST/$NAME.dmg"
WORK="$ROOT/build/release/beta-$BETA"
APP="$WORK/Keyflow.app"
VOLUME="Keyflow Beta $BETA"
MIN_MACOS="15.0"

if [[ -e "$DMG" && "$REPLACE" != "--replace" ]]; then
    echo "error: $DMG already exists. Rerun with --replace to rebuild it." >&2; exit 1
fi

step() { printf '\n== %s\n' "$1"; }
CHECKS=()
pass() { CHECKS+=("- [x] $1"); echo "  ok: $1"; }
fail() { echo "  FAILED: $1" >&2; exit 1; }

# MARK: Build
step "Building Keyflow $KEYFLOW_VERSION Beta $BETA (build $BETA), universal Release"
mkdir -p "$WORK" "$DIST"
KEYFLOW_VERSION="$KEYFLOW_VERSION" KEYFLOW_BUILD="$BETA" KEYFLOW_CHANNEL="Beta $BETA" \
KEYFLOW_FEEDBACK_EMAIL="$KEYFLOW_FEEDBACK_EMAIL" KEYFLOW_UNIVERSAL=1 KEYFLOW_APP="$APP" \
    Scripts/build-app.sh release

# MARK: Validate the app
step "Validating the app bundle"
PLIST="$APP/Contents/Info.plist"
BIN="$APP/Contents/MacOS/Keyflow"
read_plist() { plutil -extract "$1" raw "$PLIST" 2>/dev/null || echo ""; }
BUNDLE_ID="$(read_plist CFBundleIdentifier)"
[[ "$BUNDLE_ID" == "app.keyflow.Keyflow" ]] && pass "Bundle identifier is app.keyflow.Keyflow" || fail "bundle identifier is '$BUNDLE_ID'"
[[ "$(read_plist CFBundleShortVersionString)" == "$KEYFLOW_VERSION" ]] && pass "Version $KEYFLOW_VERSION" || fail "version"
[[ "$(read_plist CFBundleVersion)" == "$BETA" ]] && pass "Build number $BETA" || fail "build number"
[[ "$(read_plist KeyflowReleaseChannel)" == "Beta $BETA" ]] && pass "Release channel Beta $BETA" || fail "channel"
[[ "$(read_plist LSMinimumSystemVersion)" == "$MIN_MACOS" ]] && pass "Info.plist minimum macOS $MIN_MACOS" || fail "LSMinimumSystemVersion"
if [[ -n "$KEYFLOW_FEEDBACK_EMAIL" ]]; then
    [[ "$(read_plist KeyflowFeedbackEmail)" == "$KEYFLOW_FEEDBACK_EMAIL" ]] && pass "Feedback address set ($KEYFLOW_FEEDBACK_EMAIL)" || fail "feedback address"
else
    pass "No feedback address: the feedback button is hidden"
fi

ARCHS="$(lipo -archs "$BIN")"
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] && pass "Universal binary ($ARCHS)" || fail "architectures: $ARCHS"
MINOS="$(vtool -show-build "$BIN" | awk '/minos/ {print $2}' | sort -u | tr '\n' ' ' | xargs)"
[[ "$MINOS" == "$MIN_MACOS" ]] && pass "Binary minimum macOS $MINOS (both architectures)" || fail "binary minos: $MINOS"

[[ "$(read_plist CFBundleIconFile)" == "AppIcon" && -s "$APP/Contents/Resources/AppIcon.icns" ]] \
    && pass "App icon embedded (Resources/AppIcon.icns)" || fail "app icon missing"
ICONS="$WORK/icon-check.iconset"
rm -rf "$ICONS"
iconutil -c iconset "$APP/Contents/Resources/AppIcon.icns" -o "$ICONS"
COUNT="$(ls "$ICONS" | wc -l | xargs)"
[[ "$COUNT" == 10 ]] && pass "Icon has all 10 sizes (16–1024 px)" || fail "icon has $COUNT sizes"
cmp -s "$APP/Contents/Resources/AppIcon.icns" Assets/AppIcon/AppIcon.icns && pass "Icon is the current Assets/AppIcon/AppIcon.icns" || fail "icon differs from Assets"

# Only system libraries: nothing from a developer machine is needed at run time.
# (otool prints a "<file> (architecture …):" header per slice; skip those.)
FOREIGN="$(otool -L "$BIN" | grep -v ':$' | awk '{print $1}' | grep -v -E '^(/usr/lib/|/System/Library/)' | sort -u || true)"
[[ -z "$FOREIGN" ]] && pass "Links only macOS system libraries" || fail "non-system libraries: $FOREIGN"
DEV_RPATHS="$(otool -l "$BIN" | awk '/LC_RPATH/ {getline; getline; print $2}' | grep -E '^(/Library/Developer|/Applications/Xcode|/Users/)' || true)"
[[ -z "$DEV_RPATHS" ]] && pass "No library search paths into developer tools" || fail "developer rpaths: $DEV_RPATHS"
EXTRA_FILES="$(cd "$APP" && find . -type f | grep -v -E '^\./Contents/(Info\.plist|MacOS/Keyflow|Resources/AppIcon\.icns|_CodeSignature/CodeResources)$' || true)"
[[ -z "$EXTRA_FILES" ]] && pass "Bundle holds only the app, its Info.plist, icon and signature" || fail "unexpected files: $EXTRA_FILES"

codesign --verify --deep --strict "$APP" && pass "Signature verifies (codesign --verify --deep --strict)" || fail "codesign verify"
SIGNATURE="$(codesign -dv "$APP" 2>&1 | grep -E '^Signature=' | cut -d= -f2)"
[[ "$SIGNATURE" == "adhoc" ]] && SIGNING="Ad-hoc signed (no Developer ID certificate on this Mac)" || SIGNING="Signed: $SIGNATURE"
GATEKEEPER="$(spctl --assess --type execute "$APP" 2>&1 || true)"
pass "Gatekeeper assessment recorded: ${GATEKEEPER##*: }"

# MARK: Package
step "Packaging $NAME.dmg"
STAGE="$WORK/dmg-root"
rm -rf "$STAGE" "$WORK/rw.dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Keyflow.app"
ln -s /Applications "$STAGE/Applications"
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 20 ))
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOLUME" -fs HFS+ -format UDRW -size "${SIZE_MB}m" "$WORK/rw.dmg"

# Window layout: the app on the left, Applications on the right, nothing else.
# Uses Finder through AppleScript; if that is not allowed, the DMG still
# works with Finder's default layout.
MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" | awk -F'\t' '/\/Volumes\// {print $NF}')"
LAYOUT="Finder default (layout script not run)"
if osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 760, 480}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set position of item "Keyflow.app" of container window to {150, 170}
        set position of item "Applications" of container window to {410, 170}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
then LAYOUT="Icon view, 128 pt icons, Keyflow left, Applications right"; fi
echo "  layout: $LAYOUT"
# The disk's own icon. Added after the layout: Finder's layout pass removes it.
cp Assets/AppIcon/AppIcon.icns "$MOUNT/.VolumeIcon.icns"
SetFile -c icnC "$MOUNT/.VolumeIcon.icns" 2>/dev/null || true
SetFile -a C "$MOUNT" 2>/dev/null || true
sync
hdiutil detach -quiet "$MOUNT" || { sleep 2; hdiutil detach -quiet -force "$MOUNT"; }

rm -f "$DMG"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -f "$WORK/rw.dmg"

# MARK: Verify the DMG
step "Verifying the DMG"
hdiutil verify -quiet "$DMG" && pass "hdiutil verify: checksum valid" || fail "hdiutil verify"
FORMAT="$(hdiutil imageinfo "$DMG" | awk -F': ' '/^Format:/ {print $2; exit}')"
[[ "$FORMAT" == "UDZO" ]] && pass "Compressed, read-only image (UDZO)" || fail "format $FORMAT"
CHECK_MOUNT="$WORK/verify-mount"
mkdir -p "$CHECK_MOUNT"
hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$CHECK_MOUNT" "$DMG"
detach() { hdiutil detach -quiet "$CHECK_MOUNT" 2>/dev/null || hdiutil detach -quiet -force "$CHECK_MOUNT"; }
trap detach EXIT
VISIBLE="$(cd "$CHECK_MOUNT" && ls | tr '\n' ' ' | xargs)"
[[ "$VISIBLE" == "Applications Keyflow.app" ]] && pass "DMG shows exactly: Keyflow.app, Applications" || fail "DMG contents: $VISIBLE"
[[ -L "$CHECK_MOUNT/Applications" && "$(readlink "$CHECK_MOUNT/Applications")" == "/Applications" ]] \
    && pass "Applications is a shortcut to /Applications" || fail "Applications shortcut"
codesign --verify --deep --strict "$CHECK_MOUNT/Keyflow.app" && pass "App inside the DMG: signature intact" || fail "packaged signature"
cmp -s "$CHECK_MOUNT/Keyflow.app/Contents/MacOS/Keyflow" "$BIN" && pass "App inside the DMG is the validated build" || fail "packaged binary differs"
[[ -s "$CHECK_MOUNT/Keyflow.app/Contents/Resources/AppIcon.icns" ]] && pass "App inside the DMG: icon present" || fail "packaged icon"
[[ -s "$CHECK_MOUNT/.VolumeIcon.icns" ]] && pass "Disk icon set to the Keyflow icon" || fail "disk icon missing"
detach
trap - EXIT

# MARK: Documents
step "Writing tester documents and report"
DMG_BYTES="$(stat -f %z "$DMG")"
DMG_SIZE="$(awk -v b="$DMG_BYTES" 'BEGIN {printf "%.1f MB", b / 1000000}')"
SHA256="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
FEEDBACK_LINE="In Keyflow, open **Settings ▸ About** and click **Send Beta Feedback…**. It opens an email to $KEYFLOW_FEEDBACK_EMAIL with your Keyflow and macOS versions filled in. You can also write to that address directly."
[[ -z "$KEYFLOW_FEEDBACK_EMAIL" ]] && FEEDBACK_LINE="Reply to the person who sent you Keyflow."
fill() {
    sed -e "s|{{VERSION}}|$KEYFLOW_VERSION Beta $BETA (build $BETA)|g" -e "s|{{BETA}}|$BETA|g" \
        -e "s|{{DMG}}|$NAME.dmg|g" -e "s|{{MIN_MACOS}}|$MIN_MACOS|g" -e "s|{{VOLUME}}|$VOLUME|g" \
        -e "s|{{FEEDBACK}}|$FEEDBACK_LINE|g" "$1"
}
fill Docs/Beta/README.md > "$DIST/$NAME-README.md"
fill Docs/Beta/Testing-Checklist.md > "$DIST/$NAME-Testing-Checklist.md"

REPORT="$DIST/$NAME-Release-Report.md"
{
    echo "# Keyflow $KEYFLOW_VERSION Beta $BETA — release report"
    echo
    echo "Generated by \`Scripts/release-beta.sh\` on $(date '+%Y-%m-%d %H:%M %Z')."
    echo
    echo "| | |"
    echo "| --- | --- |"
    echo "| DMG | \`$DMG\` |"
    echo "| Size | $DMG_SIZE ($DMG_BYTES bytes) |"
    echo "| SHA-256 | \`$SHA256\` |"
    echo "| Version | $KEYFLOW_VERSION Beta $BETA |"
    echo "| Build number | $BETA |"
    echo "| Bundle identifier | $BUNDLE_ID |"
    echo "| Minimum macOS | $MIN_MACOS |"
    echo "| Architectures | $ARCHS |"
    echo "| Signing | $SIGNING |"
    echo "| Notarization | Not notarized (needs a Developer ID certificate and an Apple Developer Program account) |"
    echo "| Gatekeeper on this Mac | \`$GATEKEEPER\` |"
    echo "| Feedback | ${KEYFLOW_FEEDBACK_EMAIL:-none (button hidden)} |"
    echo "| DMG window | $LAYOUT |"
    echo
    echo "## Automated checks (all passed)"
    echo
    printf '%s\n' "${CHECKS[@]}"
    echo
    echo "## What testers will see"
    echo
    echo "macOS blocks the first launch of an app that is not notarized. Testers allow"
    echo "Keyflow once in System Settings ▸ Privacy & Security ▸ Open Anyway, as the"
    echo "README explains. Gatekeeper stays on for everything else."
} > "$REPORT"

step "Done"
echo "DMG:      $DMG ($DMG_SIZE)"
echo "README:   $DIST/$NAME-README.md"
echo "Checklist $DIST/$NAME-Testing-Checklist.md"
echo "Report:   $REPORT"
