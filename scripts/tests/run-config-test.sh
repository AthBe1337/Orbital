#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_ORBITAL="$TMP_DIR/fake-orbital"
printf '#!/bin/sh\nexit 0\n' >"$FAKE_ORBITAL"
chmod +x "$FAKE_ORBITAL"

FAILURES=0

assert_contains() {
    local output="$1"
    local expected="$2"
    local label="$3"

    if [[ "$output" != *"$expected"* ]]; then
        echo "FAIL: $label (missing '$expected')" >&2
        echo "$output" >&2
        FAILURES=$((FAILURES + 1))
    fi
}

run_config() {
    (
        cd "$PROJECT_DIR"
        bash scripts/run.sh "$@"
    ) 2>&1
}

export ORBITAL_EXECUTABLE="$FAKE_ORBITAL"

output="$(
    ORBITAL_DEVICE=oneplus-enchilada run_config
)"
assert_contains "$output" \
    "Orbital device: OnePlus 6 (oneplus-enchilada), scale=2.15" \
    "OnePlus 6 profile default"

output="$(
    ORBITAL_DEVICE=oneplus-fajita run_config
)"
assert_contains "$output" \
    "Orbital device: OnePlus 6T (oneplus-fajita), scale=2.2" \
    "OnePlus 6T profile default"

output="$(
    QT_SCALE_FACTOR=1.8 ORBITAL_DEVICE=oneplus-enchilada run_config --scale 2.05
)"
assert_contains "$output" "scale=2.05" "CLI scale overrides environment"

output="$(
    ORBITAL_DEVICE=oneplus-enchilada run_config --scale invalid
)"
assert_contains "$output" \
    "Invalid scale 'invalid'; falling back to 2.15 for OnePlus 6" \
    "invalid scale fallback message"
assert_contains "$output" "scale=2.15" "invalid scale fallback value"

INPUT_ROOT="$TMP_DIR/input"
DEV_INPUT_ROOT="$TMP_DIR/dev-input"
mkdir -p "$INPUT_ROOT/event5/device" "$DEV_INPUT_ROOT"
printf 'synaptics-rmi4-i2c\n' >"$INPUT_ROOT/event5/device/name"
: >"$DEV_INPUT_ROOT/event5"

output="$(
    ORBITAL_DEVICE=oneplus-enchilada \
    ORBITAL_SYS_CLASS_INPUT_ROOT="$INPUT_ROOT" \
    ORBITAL_DEV_INPUT_ROOT="$DEV_INPUT_ROOT" \
    run_config
)"
assert_contains "$output" "inputs=auto" "unique input discovery source"
assert_contains "$output" "touch=$DEV_INPUT_ROOT/event5 (auto)" "touch auto discovery"

output="$(
    ORBITAL_DEVICE=oneplus-enchilada \
    ORBITAL_SYS_CLASS_INPUT_ROOT="$INPUT_ROOT" \
    ORBITAL_DEV_INPUT_ROOT="$DEV_INPUT_ROOT" \
    ORBITAL_TOUCH_INPUT_PATH="$DEV_INPUT_ROOT/event5" \
    run_config
)"
assert_contains "$output" "inputs=override" "environment override source"
assert_contains "$output" "touch=$DEV_INPUT_ROOT/event5 (override)" "touch environment override"

if [[ $FAILURES -ne 0 ]]; then
    echo "$FAILURES test(s) failed" >&2
    exit 1
fi

echo "All run configuration tests passed"
