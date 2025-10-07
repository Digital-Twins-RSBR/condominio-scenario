#!/bin/sh
# Collect ThingsBoard device IDs to be used by orchestration.
# Prints a single line with space-separated UUIDs. Respects env var TB_IDS if provided.

set -eu

if [ -n "${TB_IDS:-}" ]; then
    echo "$TB_IDS"
    exit 0
fi

DJANGO_QUERY="""
from middleware.models import Device
devices = Device.objects.all()
device_ids = [str(device.thingsboard_id) for device in devices if device.thingsboard_id]
for device_id in device_ids:
    print(device_id)
"""

OUT_IDS=""
RETRIES=3
SLEEP=1
for i in $(seq 1 $RETRIES); do
    DB_RESULT=$(docker exec mn.middts bash -lc "cd /middleware-dt && echo '$DJANGO_QUERY' | python3 manage.py shell" 2>/dev/null || true)
    if echo "$DB_RESULT" | grep -E '^[a-f0-9-]{36}$' >/dev/null 2>&1; then
        OUT_IDS=$(echo "$DB_RESULT" | grep -E '^[a-f0-9-]{36}$' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ //; s/ $//')
        break
    fi
    sleep $SLEEP
done

if [ -n "$OUT_IDS" ]; then
    echo "$OUT_IDS"
    exit 0
fi

# Fallback: try to read device_id.txt from simulators
SIM_IDS=""
for sim in $(docker ps --format '{{.Names}}' | grep '^mn.sim_' || true); do
    id=$(docker exec "$sim" sh -c 'cat /iot_simulator/device_id.txt 2>/dev/null || true' || true)
    if echo "$id" | grep -E '^[a-f0-9-]{36}$' >/dev/null 2>&1; then
        SIM_IDS="$SIM_IDS $id"
    fi
done
SIM_IDS=$(echo "$SIM_IDS" | sed 's/^ //; s/ $//' | sed 's/  */ /g')
if [ -n "$SIM_IDS" ]; then
    echo "$SIM_IDS"
    exit 0
fi

# Final fallback: try DB via psql on mn.db
SQL_IDS=$(docker exec mn.db psql -U postgres -d middts -tAc "SELECT thingsboard_id FROM middleware_device WHERE thingsboard_id IS NOT NULL;" 2>/dev/null || true)
if echo "$SQL_IDS" | grep -E '^[a-f0-9-]{36}$' >/dev/null 2>&1; then
    OUT_IDS=$(echo "$SQL_IDS" | grep -E '^[a-f0-9-]{36}$' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ //; s/ $//')
    echo "$OUT_IDS"
    exit 0
fi

# Nothing found
exit 0
