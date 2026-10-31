#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

source "$SCRIPT_DIR/device-profile.sh"

PROFILE_ID="$(orbital_detect_device_id)"
PROFILE_MODEL="$(orbital_profile_get "$PROFILE_ID" model)"
PROFILE_SCALE="$(orbital_profile_get "$PROFILE_ID" scale)"

SCALE_VALUE="${QT_SCALE_FACTOR:-$PROFILE_SCALE}"

TOUCH_INPUT_SOURCE="auto"
TOUCH_INPUT_PATH="${ORBITAL_TOUCH_INPUT_PATH:-}"
if [[ -n "${ORBITAL_TOUCH_INPUT_PATH:-}" ]]; then
    TOUCH_INPUT_SOURCE="override"
elif ! TOUCH_INPUT_PATH="$(orbital_discover_input_path touch)"; then
    TOUCH_INPUT_PATH="$(orbital_profile_get "$PROFILE_ID" legacy_touch_path)"
    if [[ -n "$TOUCH_INPUT_PATH" ]]; then
        TOUCH_INPUT_SOURCE="legacy"
    else
        TOUCH_INPUT_SOURCE="unresolved"
    fi
fi

TOUCH_INHIBIT_PATH="${ORBITAL_TOUCH_INHIBIT_PATH:-}"
if [[ -z "${ORBITAL_TOUCH_INHIBIT_PATH:-}" ]]; then
    if ! TOUCH_INHIBIT_PATH="$(orbital_discover_touch_inhibit_path "$PROFILE_ID")"; then
        TOUCH_INHIBIT_PATH="$(orbital_profile_get "$PROFILE_ID" legacy_touch_inhibit_path 2>/dev/null || true)"
    fi
fi

POWER_KEY_SOURCE="auto"
POWER_KEY_PATH="${ORBITAL_POWER_KEY_PATH:-}"
if [[ -n "${ORBITAL_POWER_KEY_PATH:-}" ]]; then
    POWER_KEY_SOURCE="override"
elif ! POWER_KEY_PATH="$(orbital_discover_input_path power)"; then
    POWER_KEY_PATH="$(orbital_profile_get "$PROFILE_ID" legacy_power_path)"
    if [[ -n "$POWER_KEY_PATH" ]]; then
        POWER_KEY_SOURCE="legacy"
    else
        POWER_KEY_SOURCE="unresolved"
    fi
fi

VOLUME_KEY_SOURCE="auto"
VOLUME_KEY_PATH="${ORBITAL_VOLUME_KEY_PATH:-}"
if [[ -n "${ORBITAL_VOLUME_KEY_PATH:-}" ]]; then
    VOLUME_KEY_SOURCE="override"
elif ! VOLUME_KEY_PATH="$(orbital_discover_input_path volume)"; then
    VOLUME_KEY_PATH="$(orbital_profile_get "$PROFILE_ID" legacy_volume_path)"
    if [[ -n "$VOLUME_KEY_PATH" ]]; then
        VOLUME_KEY_SOURCE="legacy"
    else
        VOLUME_KEY_SOURCE="unresolved"
    fi
fi

SCREENSHOT_DIR="${ORBITAL_SCREENSHOT_DIR:-}"
VOLUME_KEY_PATH_EXPLICIT=0

if [[ -n "${ORBITAL_VOLUME_KEY_PATH:-}" ]]; then
    VOLUME_KEY_PATH_EXPLICIT=1
fi

print_usage() {
    cat <<'EOF'
Usage: ./run.sh [options]

Options:
  --scale <value>                Set QT scale factor.
  --touch-input-path <path>      Set the evdev touch input path.
  --touch-inhibit-path <path>    Set the touch inhibit sysfs path.
  --power-key-path <path>        Set the power key input path.
  --volume-key-path <path>       Set the volume key input path.
  --screenshot-dir <path>        Set the screenshot output directory.
  -h, --help                     Show this help message.
EOF
}

require_value() {
    local option_name="$1"
    local option_value="$2"

    if [[ -z "$option_value" ]]; then
        echo "Missing value for ${option_name}" >&2
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scale)
            require_value "$1" "$2"
            SCALE_VALUE="$2"
            shift 2
            ;;
        --scale=*)
            SCALE_VALUE="${1#*=}"
            require_value "--scale" "$SCALE_VALUE"
            shift
            ;;
        --touch-input-path)
            require_value "$1" "$2"
            TOUCH_INPUT_PATH="$2"
            TOUCH_INPUT_SOURCE="override"
            shift 2
            ;;
        --touch-input-path=*)
            TOUCH_INPUT_PATH="${1#*=}"
            require_value "--touch-input-path" "$TOUCH_INPUT_PATH"
            TOUCH_INPUT_SOURCE="override"
            shift
            ;;
        --touch-inhibit-path)
            require_value "$1" "$2"
            TOUCH_INHIBIT_PATH="$2"
            shift 2
            ;;
        --touch-inhibit-path=*)
            TOUCH_INHIBIT_PATH="${1#*=}"
            require_value "--touch-inhibit-path" "$TOUCH_INHIBIT_PATH"
            shift
            ;;
        --power-key-path)
            require_value "$1" "$2"
            POWER_KEY_PATH="$2"
            POWER_KEY_SOURCE="override"
            if [[ $VOLUME_KEY_PATH_EXPLICIT -eq 0 ]]; then
                VOLUME_KEY_PATH="$POWER_KEY_PATH"
                VOLUME_KEY_SOURCE="override"
            fi
            shift 2
            ;;
        --power-key-path=*)
            POWER_KEY_PATH="${1#*=}"
            require_value "--power-key-path" "$POWER_KEY_PATH"
            POWER_KEY_SOURCE="override"
            if [[ $VOLUME_KEY_PATH_EXPLICIT -eq 0 ]]; then
                VOLUME_KEY_PATH="$POWER_KEY_PATH"
                VOLUME_KEY_SOURCE="override"
            fi
            shift
            ;;
        --volume-key-path)
            require_value "$1" "$2"
            VOLUME_KEY_PATH="$2"
            VOLUME_KEY_PATH_EXPLICIT=1
            VOLUME_KEY_SOURCE="override"
            shift 2
            ;;
        --volume-key-path=*)
            VOLUME_KEY_PATH="${1#*=}"
            require_value "--volume-key-path" "$VOLUME_KEY_PATH"
            VOLUME_KEY_PATH_EXPLICIT=1
            VOLUME_KEY_SOURCE="override"
            shift
            ;;
        --screenshot-dir)
            require_value "$1" "$2"
            SCREENSHOT_DIR="$2"
            shift 2
            ;;
        --screenshot-dir=*)
            SCREENSHOT_DIR="${1#*=}"
            require_value "--screenshot-dir" "$SCREENSHOT_DIR"
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            print_usage >&2
            exit 1
            ;;
    esac
done

if ! orbital_validate_scale "$SCALE_VALUE"; then
    echo "Invalid scale '$SCALE_VALUE'; falling back to $PROFILE_SCALE for $PROFILE_MODEL" >&2
    SCALE_VALUE="$PROFILE_SCALE"
fi

if [[ -n "$TOUCH_INPUT_PATH" && ! -e "$TOUCH_INPUT_PATH" ]]; then
    echo "Touch input path does not exist: $TOUCH_INPUT_PATH" >&2
    TOUCH_INPUT_PATH=""
    TOUCH_INPUT_SOURCE="unresolved"
fi

path_list_exists() {
    local combined="$1"
    local path=""
    local -a paths=()

    IFS=',' read -r -a paths <<<"$combined"
    for path in "${paths[@]}"; do
        [[ -n "$path" && -e "$path" ]] || return 1
    done
}

if [[ -n "$POWER_KEY_PATH" ]] && ! path_list_exists "$POWER_KEY_PATH"; then
    echo "Power key path does not exist: $POWER_KEY_PATH" >&2
fi
if [[ -n "$VOLUME_KEY_PATH" ]] && ! path_list_exists "$VOLUME_KEY_PATH"; then
    echo "Volume key path does not exist: $VOLUME_KEY_PATH" >&2
fi

INPUT_SOURCE="auto"
if [[ "$TOUCH_INPUT_SOURCE" == "override" || "$POWER_KEY_SOURCE" == "override" || "$VOLUME_KEY_SOURCE" == "override" ]]; then
    INPUT_SOURCE="override"
elif [[ "$TOUCH_INPUT_SOURCE" == "legacy" || "$POWER_KEY_SOURCE" == "legacy" || "$VOLUME_KEY_SOURCE" == "legacy" ]]; then
    INPUT_SOURCE="legacy"
elif [[ "$TOUCH_INPUT_SOURCE" == "unresolved" && "$POWER_KEY_SOURCE" == "unresolved" && "$VOLUME_KEY_SOURCE" == "unresolved" ]]; then
    INPUT_SOURCE="unresolved"
fi

echo "Orbital device: $PROFILE_MODEL ($PROFILE_ID), scale=$SCALE_VALUE, inputs=$INPUT_SOURCE" >&2
echo "  touch=$TOUCH_INPUT_PATH ($TOUCH_INPUT_SOURCE)" >&2
echo "  power=$POWER_KEY_PATH ($POWER_KEY_SOURCE)" >&2
echo "  volume=$VOLUME_KEY_PATH ($VOLUME_KEY_SOURCE)" >&2

export QT_SCALE_FACTOR="$SCALE_VALUE"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-eglfs}"
export ORBITAL_TOUCH_INPUT_PATH="$TOUCH_INPUT_PATH"
export ORBITAL_TOUCH_INHIBIT_PATH="$TOUCH_INHIBIT_PATH"
export ORBITAL_POWER_KEY_PATH="$POWER_KEY_PATH"
export ORBITAL_VOLUME_KEY_PATH="$VOLUME_KEY_PATH"
export ORBITAL_SCREENSHOT_DIR="$SCREENSHOT_DIR"
export ORBITAL_INPUT_SOURCE="$INPUT_SOURCE"
if [[ -n "$ORBITAL_TOUCH_INPUT_PATH" ]]; then
    export QT_QPA_GENERIC_PLUGINS="evdevtouch:${ORBITAL_TOUCH_INPUT_PATH}"
fi
ORBITAL_EXECUTABLE="${ORBITAL_EXECUTABLE:-./Orbital}"
RESTART_EXIT_CODE=42
while true; do
    "$ORBITAL_EXECUTABLE"
    EXIT_CODE=$?

    if [ $EXIT_CODE -ne $RESTART_EXIT_CODE ]; then
        break
    fi

    sleep 1
done
