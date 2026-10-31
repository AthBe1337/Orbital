#!/bin/bash

# Device profiles and hardware discovery used by run.sh. Keep this file free of
# top-level side effects so it can also be sourced by the test harness.

orbital_profile_get() {
    local profile_id="$1"
    local field="$2"

    case "${profile_id}:${field}" in
        oneplus-enchilada:id)
            printf '%s\n' 'oneplus-enchilada'
            ;;
        oneplus-enchilada:model)
            printf '%s\n' 'OnePlus 6'
            ;;
        oneplus-enchilada:scale)
            printf '%s\n' '2.15'
            ;;
        oneplus-enchilada:screen_width)
            printf '%s\n' '1080'
            ;;
        oneplus-enchilada:screen_height)
            printf '%s\n' '2280'
            ;;
        oneplus-fajita:id)
            printf '%s\n' 'oneplus-fajita'
            ;;
        oneplus-fajita:model)
            printf '%s\n' 'OnePlus 6T'
            ;;
        oneplus-fajita:scale)
            printf '%s\n' '2.2'
            ;;
        oneplus-fajita:screen_width)
            printf '%s\n' '1080'
            ;;
        oneplus-fajita:screen_height)
            printf '%s\n' '2340'
            ;;
        unknown:id)
            printf '%s\n' 'unknown'
            ;;
        unknown:model)
            printf '%s\n' 'Unknown device'
            ;;
        unknown:scale)
            printf '%s\n' '2.2'
            ;;
        unknown:screen_width|unknown:screen_height)
            printf '%s\n' '0'
            ;;
        oneplus-enchilada:touch_name_patterns|oneplus-fajita:touch_name_patterns|unknown:touch_name_patterns)
            printf '%s\n' 'synaptics|rmi4|touch'
            ;;
        oneplus-enchilada:touch_path_patterns|oneplus-fajita:touch_path_patterns|unknown:touch_path_patterns)
            printf '%s\n' 'rmi4'
            ;;
        oneplus-enchilada:power_name_patterns|oneplus-fajita:power_name_patterns|unknown:power_name_patterns)
            printf '%s\n' 'pwrkey|power button'
            ;;
        oneplus-enchilada:volume_name_patterns|oneplus-fajita:volume_name_patterns|unknown:volume_name_patterns)
            printf '%s\n' 'volume keys|volume'
            ;;
        oneplus-enchilada:touch_inhibit_glob|oneplus-fajita:touch_inhibit_glob|unknown:touch_inhibit_glob)
            printf '%s\n' '*rmi4-00/input/input*/inhibited'
            ;;
        oneplus-enchilada:legacy_touch_path|oneplus-enchilada:legacy_power_path|oneplus-enchilada:legacy_volume_path)
            printf '\n'
            ;;
        oneplus-fajita:legacy_touch_path|unknown:legacy_touch_path)
            printf '%s\n' '/dev/input/event5'
            ;;
        oneplus-fajita:legacy_power_path|unknown:legacy_power_path)
            printf '%s\n' '/dev/input/event0'
            ;;
        oneplus-fajita:legacy_volume_path|unknown:legacy_volume_path)
            printf '%s\n' '/dev/input/event3'
            ;;
        *)
            return 1
            ;;
    esac
}

orbital_detect_device_id() {
    local requested="${ORBITAL_DEVICE:-}"
    local compatible_file="${ORBITAL_DEVICE_TREE_COMPATIBLE_FILE:-/sys/firmware/devicetree/base/compatible}"
    local compatible=""

    requested="$(printf '%s' "$requested" | tr '[:upper:]' '[:lower:]')"
    case "$requested" in
        oneplus-enchilada|oneplus,enchilada)
            printf '%s\n' 'oneplus-enchilada'
            return 0
            ;;
        oneplus-fajita|oneplus,fajita)
            printf '%s\n' 'oneplus-fajita'
            return 0
            ;;
    esac

    if [[ -r "$compatible_file" ]]; then
        compatible="$(tr -d '\0' <"$compatible_file" | tr '[:upper:]' '[:lower:]')"
        case "$compatible" in
            *oneplus,enchilada*|*oneplus-enchilada*)
                printf '%s\n' 'oneplus-enchilada'
                return 0
                ;;
            *oneplus,fajita*|*oneplus-fajita*)
                printf '%s\n' 'oneplus-fajita'
                return 0
                ;;
        esac
    fi

    printf '%s\n' 'unknown'
}

orbital_discover_input_path() {
    local kind="$1"
    local profile_id="${ORBITAL_PROFILE_ID:-$(orbital_detect_device_id)}"
    local input_root="${ORBITAL_SYS_CLASS_INPUT_ROOT:-/sys/class/input}"
    local device_root="${ORBITAL_DEV_INPUT_ROOT:-/dev/input}"
    local name_pattern=""
    local path_pattern=""
    local event_dir=""
    local event_name=""
    local event_base=""
    local resolved_path=""
    local lower_name=""
    local lower_path=""
    local -a matches=()

    case "$kind" in
        touch)
            name_pattern="$(orbital_profile_get "$profile_id" touch_name_patterns)" || return 1
            path_pattern="$(orbital_profile_get "$profile_id" touch_path_patterns)" || return 1
            ;;
        power)
            name_pattern="$(orbital_profile_get "$profile_id" power_name_patterns)" || return 1
            ;;
        volume)
            name_pattern="$(orbital_profile_get "$profile_id" volume_name_patterns)" || return 1
            ;;
        *)
            return 1
            ;;
    esac

    for event_dir in "$input_root"/event*; do
        [[ -d "$event_dir" && -r "$event_dir/device/name" ]] || continue

        event_name="$(tr '[:upper:]' '[:lower:]' <"$event_dir/device/name" 2>/dev/null)"
        event_base="$(basename "$event_dir")"
        resolved_path="$(readlink -f "$event_dir/device" 2>/dev/null || printf '%s' "$event_dir/device")"
        lower_name="$(printf '%s' "$event_name" | tr '[:upper:]' '[:lower:]')"
        lower_path="$(printf '%s' "$resolved_path" | tr '[:upper:]' '[:lower:]')"

        case "$kind" in
            touch)
                if [[ "$lower_name" =~ $name_pattern || "$lower_path" =~ $path_pattern ]]; then
                    matches+=("$device_root/$event_base")
                fi
                ;;
            *)
                if [[ "$lower_name" =~ $name_pattern ]]; then
                    matches+=("$device_root/$event_base")
                fi
                ;;
        esac
    done

    if [[ ${#matches[@]} -ne 1 ]]; then
        return 1
    fi

    printf '%s\n' "${matches[0]}"
}

orbital_discover_touch_inhibit_path() {
    local profile_id="$1"
    local sys_devices_root="${ORBITAL_SYS_DEVICES_ROOT:-/sys/devices}"
    local glob_pattern=""

    glob_pattern="$(orbital_profile_get "$profile_id" touch_inhibit_glob)" || return 1
    if [[ ! -d "$sys_devices_root" ]]; then
        return 1
    fi

    find "$sys_devices_root" -type f -path "$glob_pattern" -print -quit 2>/dev/null
}

orbital_validate_scale() {
    local value="$1"

    awk -v value="$value" 'BEGIN {
        if (value !~ /^[0-9]+([.][0-9]+)?$/ || value <= 0) {
            exit 1
        }
    }'
}
