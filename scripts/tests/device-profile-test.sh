#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/scripts/device-profile.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAILURES=0

assert_eq() {
    local expected="$1"
    local actual="$2"
    local label="$3"

    if [[ "$actual" != "$expected" ]]; then
        echo "FAIL: $label (expected '$expected', got '$actual')" >&2
        FAILURES=$((FAILURES + 1))
    fi
}

assert_ok() {
    local label="$1"
    shift

    if ! "$@"; then
        echo "FAIL: $label" >&2
        FAILURES=$((FAILURES + 1))
    fi
}

assert_fails() {
    local label="$1"
    shift

    if "$@"; then
        echo "FAIL: $label" >&2
        FAILURES=$((FAILURES + 1))
    fi
}

printf 'oneplus,enchilada\0qcom,sdm845\0' >"$TMP_DIR/enchilada-compatible"
printf 'oneplus,fajita\0qcom,sdm845\0' >"$TMP_DIR/fajita-compatible"

assert_eq \
    "oneplus-enchilada" \
    "$(ORBITAL_DEVICE_TREE_COMPATIBLE_FILE="$TMP_DIR/enchilada-compatible" orbital_detect_device_id)" \
    "detect OnePlus 6 compatible"
assert_eq \
    "oneplus-fajita" \
    "$(ORBITAL_DEVICE_TREE_COMPATIBLE_FILE="$TMP_DIR/fajita-compatible" orbital_detect_device_id)" \
    "detect OnePlus 6T compatible"
assert_eq \
    "oneplus-enchilada" \
    "$(ORBITAL_DEVICE=oneplus-enchilada ORBITAL_DEVICE_TREE_COMPATIBLE_FILE="$TMP_DIR/missing" orbital_detect_device_id)" \
    "explicit device override"
assert_eq \
    "unknown" \
    "$(ORBITAL_DEVICE_TREE_COMPATIBLE_FILE="$TMP_DIR/missing" orbital_detect_device_id)" \
    "unknown device"

assert_eq "2.15" "$(orbital_profile_get oneplus-enchilada scale)" "OnePlus 6 scale"
assert_eq "2.2" "$(orbital_profile_get oneplus-fajita scale)" "OnePlus 6T scale"
assert_eq "1080" "$(orbital_profile_get oneplus-enchilada screen_width)" "OnePlus 6 width"
assert_eq "2280" "$(orbital_profile_get oneplus-enchilada screen_height)" "OnePlus 6 height"

assert_ok "valid scale 2.15" orbital_validate_scale 2.15
assert_ok "valid integer scale" orbital_validate_scale 2
assert_fails "reject invalid scale" orbital_validate_scale nope
assert_fails "reject zero scale" orbital_validate_scale 0
assert_fails "reject negative scale" orbital_validate_scale -1

INPUT_ROOT="$TMP_DIR/input"
DEV_INPUT_ROOT="$TMP_DIR/dev-input"
mkdir -p "$INPUT_ROOT/event5/device" "$DEV_INPUT_ROOT"
printf 'synaptics-rmi4-i2c\n' >"$INPUT_ROOT/event5/device/name"

assert_eq \
    "$DEV_INPUT_ROOT/event5" \
    "$(ORBITAL_PROFILE_ID=oneplus-enchilada ORBITAL_SYS_CLASS_INPUT_ROOT="$INPUT_ROOT" ORBITAL_DEV_INPUT_ROOT="$DEV_INPUT_ROOT" orbital_discover_input_path touch)" \
    "discover unique touch input"

mkdir -p "$INPUT_ROOT/event6/device"
printf 'secondary touch panel\n' >"$INPUT_ROOT/event6/device/name"

assert_fails \
    "ambiguous touch input is not guessed" \
    env \
    ORBITAL_PROFILE_ID=oneplus-enchilada \
    ORBITAL_SYS_CLASS_INPUT_ROOT="$INPUT_ROOT" \
    ORBITAL_DEV_INPUT_ROOT="$DEV_INPUT_ROOT" \
    bash -c 'source "$1"; orbital_discover_input_path touch' _ \
    "$PROJECT_DIR/scripts/device-profile.sh"

mkdir -p "$INPUT_ROOT/event0/device" "$INPUT_ROOT/event3/device"
printf 'pm8941_pwrkey\n' >"$INPUT_ROOT/event0/device/name"
printf 'Volume keys\n' >"$INPUT_ROOT/event3/device/name"

assert_eq \
    "$DEV_INPUT_ROOT/event0" \
    "$(ORBITAL_PROFILE_ID=oneplus-enchilada ORBITAL_SYS_CLASS_INPUT_ROOT="$INPUT_ROOT" ORBITAL_DEV_INPUT_ROOT="$DEV_INPUT_ROOT" orbital_discover_input_path power)" \
    "discover power key"
assert_eq \
    "$DEV_INPUT_ROOT/event3" \
    "$(ORBITAL_PROFILE_ID=oneplus-enchilada ORBITAL_SYS_CLASS_INPUT_ROOT="$INPUT_ROOT" ORBITAL_DEV_INPUT_ROOT="$DEV_INPUT_ROOT" orbital_discover_input_path volume)" \
    "discover volume key"

INHIBIT_PATH="$TMP_DIR/sys/devices/platform/rmi4-00/input/input5/inhibited"
mkdir -p "$(dirname "$INHIBIT_PATH")"
: >"$INHIBIT_PATH"

assert_eq \
    "$INHIBIT_PATH" \
    "$(ORBITAL_SYS_DEVICES_ROOT="$TMP_DIR/sys/devices" orbital_discover_touch_inhibit_path oneplus-enchilada)" \
    "discover touch inhibit path"

if [[ $FAILURES -ne 0 ]]; then
    echo "$FAILURES test(s) failed" >&2
    exit 1
fi

echo "All device profile tests passed"
