#!/bin/bash
# Runs the unit tests. Usage: Scripts/test.sh [extra swift-test arguments]
set -uo pipefail
cd "$(dirname "$0")/.."
source Scripts/toolchain.sh

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

# With the Command Line Tools, the first build after a source change sometimes
# fails to locate the swift-testing macro plugin; an immediate rebuild finds it.
for attempt in 1 2 3; do
    swift test ${SDK_ARGS[@]+"${SDK_ARGS[@]}"} "$@" >"$LOG" 2>&1
    status=$?
    if [[ $status -ne 0 ]] && grep -q "plugin for module 'TestingMacros' not found" "$LOG" && [[ $attempt -lt 3 ]]; then
        continue
    fi
    cat "$LOG"
    exit $status
done
