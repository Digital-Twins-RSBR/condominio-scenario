#!/bin/sh
# Collect ThingsBoard device IDs from the active simulators first, falling back to DB
# Usage:
#   ./get_thingsboard_ids.sh            # prints space-separated TB IDs (simulators preferred)
#   ./get_thingsboard_ids.sh --apply    # also calls update_causal_property inside mn.middts with the IDs

set -eu

APPLY=0
if [ "${1:-}" = "--apply" ]; then
    APPLY=1
fi

# If orchestration already provided TB_IDS, prefer it and optionally apply
if [ -n "${TB_IDS:-}" ]; then
    echo "$TB_IDS"
    if [ "$APPLY" -eq 1 ]; then
        echo "Applying update_causal_property with provided TB_IDS..."
        echo "Applying update_causal_property with provided TB_IDS via file transfer (avoids ARG length limits)..."
        TMP_HOST="/tmp/tb_ids_$$.txt"
        echo "$TB_IDS" | tr ' ' '\n' > "$TMP_HOST"
        docker cp "$TMP_HOST" mn.middts:/tmp/tb_ids_for_update.txt
        rm -f "$TMP_HOST"
            docker exec -d mn.middts bash -lc "cd /middleware-dt && nohup python3 - <<'PY' > /middleware-dt/update_causal_property_from_get_ids.out 2>&1 &
import subprocess
ids = open('/tmp/tb_ids_for_update.txt').read().split()
if ids:
    cmd = ['python3', 'manage.py', 'update_causal_property', '--thingsboard-ids'] + [' '.join(ids)]
    subprocess.run(cmd)
PY
echo \$! > /tmp/update_causal_property_get_ids.pid"
    fi
    exit 0
fi

# Helper: normalize and dedupe IDs
normalize_ids() {
    echo "$@" | tr ' ' '\n' | grep -E '^[a-f0-9-]{36}$' || true
}

ALL_IDS=""

# 1) Preferred: read each active simulator's sqlite DB (fast and authoritative)
for sim in $(docker ps --format '{{.Names}}' | grep '^mn.sim_' || true); do
    # Try sqlite3 query inside the container (if sqlite3 binary exists)
    IDS=""
    IDS=$(docker exec "$sim" sh -lc "sqlite3 /iot_simulator/db.sqlite3 \"SELECT thingsboard_id FROM devices_device WHERE thingsboard_id IS NOT NULL;\" 2>/dev/null || true" 2>/dev/null || true)
    if echo "$IDS" | grep -Eq '^[a-f0-9-]{36}'; then
        for id in $(echo "$IDS" | tr '\n' ' '); do
            if echo "$id" | grep -Eq '^[a-f0-9-]{36}$'; then
                ALL_IDS="$ALL_IDS $id"
            fi
        done
        continue
    fi

    # Fallback: grep UUIDs from files under /iot_simulator (if sqlite3 not present)
    GREP_OUT=$(docker exec "$sim" sh -lc "grep -R -nE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' /iot_simulator || true" 2>/dev/null || true)
    # Extract UUIDs robustly (handle lines like path:uuid or just uuid)
    ID_LIST=$(echo "$GREP_OUT" | grep -Eo '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' || true)
    if [ -n "$ID_LIST" ]; then
        for id in $(echo "$ID_LIST" | tr '\n' ' '); do
            ALL_IDS="$ALL_IDS $id"
        done
        continue
    fi

    # Final fallback inside simulator: device_id.txt
    DID=$(docker exec "$sim" sh -c 'cat /iot_simulator/device_id.txt 2>/dev/null || true' 2>/dev/null || true)
    if echo "$DID" | grep -Eq '^[a-f0-9-]{36}$'; then
        ALL_IDS="$ALL_IDS $DID"
    fi
done

# 2) If none found in simulators, try middts DB via Django shell
if [ -z "$(normalize_ids $ALL_IDS)" ]; then
    DJANGO_QUERY="""
from middleware.models import Device
device_ids = [str(d.thingsboard_id) for d in Device.objects.all() if d.thingsboard_id]
for i in device_ids:
    print(i)
"""
    DB_RESULT=$(docker exec mn.middts bash -lc "cd /middleware-dt && echo '$DJANGO_QUERY' | python3 manage.py shell" 2>/dev/null || true)
    for id in $(echo "$DB_RESULT" | tr '\n' ' '); do
        if echo "$id" | grep -Eq '^[a-f0-9-]{36}$'; then
            ALL_IDS="$ALL_IDS $id"
        fi
    done
fi

# 3) Last fallback: DB container query
if [ -z "$(normalize_ids $ALL_IDS)" ]; then
    SQL_IDS=$(docker exec mn.db psql -U postgres -d middts -tAc "SELECT thingsboard_id FROM middleware_device WHERE thingsboard_id IS NOT NULL;" 2>/dev/null || true)
    for id in $(echo "$SQL_IDS" | tr '\n' ' '); do
        if echo "$id" | grep -Eq '^[a-f0-9-]{36}$'; then
            ALL_IDS="$ALL_IDS $id"
        fi
    done
fi

# Normalize, dedupe and print
IDS=$(normalize_ids $ALL_IDS | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ //; s/ $//')
if [ -n "$IDS" ]; then
    echo "$IDS"
    if [ "$APPLY" -eq 1 ]; then
        echo "Applying update_causal_property with $IDS via file transfer (avoids ARG length limits)..."
        TMP_HOST="/tmp/tb_ids_$$.txt"
        echo "$IDS" | tr ' ' '\n' > "$TMP_HOST"
        docker cp "$TMP_HOST" mn.middts:/tmp/tb_ids_for_update.txt
        rm -f "$TMP_HOST"
        docker exec -d mn.middts bash -lc "cd /middleware-dt && nohup python3 - <<'PY' > /middleware-dt/update_causal_property_from_get_ids.out 2>&1 &
import sys
from django.core.management import call_command
ids = open('/tmp/tb_ids_for_update.txt').read().split()
if ids:
    call_command('update_causal_property', '--thingsboard-ids', ' '.join(ids))
PY
echo \$! > /tmp/update_causal_property_get_ids.pid"
    fi
    exit 0
fi

# Nothing found
exit 0
