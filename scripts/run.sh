#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export QT_SCALE_FACTOR=2.2
export QT_QPA_PLATFORM=eglfs
export QT_QPA_GENERIC_PLUGINS=evdevtouch:/dev/input/event5
RESTART_EXIT_CODE=42
while true; do
    ./appOrbital
    EXIT_CODE=$?

    if [ $EXIT_CODE -ne $RESTART_EXIT_CODE ]; then
        break
    fi

    sleep 1
done
