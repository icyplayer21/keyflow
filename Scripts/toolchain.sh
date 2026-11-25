# Sourced by the other scripts. Sets SDK_ARGS for `swift build` / `swift test`.
#
# With full Xcode selected, nothing extra is needed. With only the Command Line
# Tools, the macOS 27 SDK turns @State into a macro whose compiler plugin ships
# solely with Xcode, so we build against the newest macOS 26 SDK instead. The
# app still targets macOS 15+ either way.
SDK_ARGS=()
if [[ "$(xcode-select -p 2>/dev/null)" == */CommandLineTools ]]; then
    FALLBACK_SDK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.[0-9]*.sdk 2>/dev/null | sort -V | tail -1)"
    if [[ -n "$FALLBACK_SDK" ]]; then
        SDK_ARGS=(--sdk "$FALLBACK_SDK")
    fi
fi
