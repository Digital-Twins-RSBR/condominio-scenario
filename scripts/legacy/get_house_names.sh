#!/bin/sh
# Extract house names from active simulators (prefers sqlite DB, fallback to grep)
set -eu

ALL_HOUSES=""

for sim in $(docker ps --format '{{.Names}}' | grep '^mn.sim_' || true); do
    # Try sqlite3 inside container to get device names
    if docker exec "$sim" sh -c "command -v sqlite3 >/dev/null 2>&1"; then
        NAMES=$(docker exec "$sim" sh -lc "sqlite3 /iot_simulator/db.sqlite3 \"SELECT name FROM devices_device WHERE name IS NOT NULL;\"" 2>/dev/null || true)
        if [ -n "$NAMES" ]; then
            ALL_HOUSES="$ALL_HOUSES\n$NAMES"
            continue
        fi
    fi

    # Fallback: grep files for 'House' tokens
    GREP_OUT=$(docker exec "$sim" sh -lc "grep -R -nE '\b(house|home|apt|apartment|condo|condominium|unit)[\s_-]?[0-9]+' /iot_simulator || true" 2>/dev/null || true)
    NAMES=$(echo "$GREP_OUT" | grep -Eo "\b(house|home|apt|apartment|condo|condominium|unit)[\s_-]?[0-9]+\b" || true)
    if [ -n "$NAMES" ]; then
        ALL_HOUSES="$ALL_HOUSES\n$NAMES"
        continue
    fi

    # Last fallback: attempt to read device file
    DID_NAME=$(docker exec "$sim" sh -c 'cat /iot_simulator/device_name.txt 2>/dev/null || true' 2>/dev/null || true)
    if [ -n "$DID_NAME" ]; then
        ALL_HOUSES="$ALL_HOUSES\n$DID_NAME"
    fi
done

# Normalize: extract tokens like 'House 1' or 'apt 2' and format as 'House 1'
echo "$ALL_HOUSES" | tr '\r' '\n' | sed -n 's/.*\b\(house\|home\|apt\|apartment\|condo\|condominium\|unit\)[ _-]*\([0-9]\+\)\b.*/\1 \2/ip' | awk '{ $1=toupper(substr($1,1,1)) tolower(substr($1,2)); print $1" "$2 }' | sed 's/^/House /I' | sort -u || true
