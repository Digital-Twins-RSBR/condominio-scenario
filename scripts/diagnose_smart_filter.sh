#!/bin/sh
# diagnostics for update_causal_property / intelligent filter
set -eu

MID_CNT=${1:-mn.middts}
echo "Diagnostic helper for intelligent filter (container: $MID_CNT)"

echo "\n1) Last 200 lines of /middleware-dt/update_causal_property.out (if present):"
docker exec "$MID_CNT" bash -lc "if [ -f /middleware-dt/update_causal_property.out ]; then tail -n 200 /middleware-dt/update_causal_property.out; else echo 'NO update_causal_property.out found'; fi"

echo "\n2) Extract any ThingsBoard UUIDs and 'House' lines from the output (unique):"
docker exec "$MID_CNT" bash -lc "if [ -f /middleware-dt/update_causal_property.out ]; then grep -o '[a-f0-9]\{8\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{12\}' /middleware-dt/update_causal_property.out | sort | uniq || true; echo '---'; grep -E 'House [0-9]+' /middleware-dt/update_causal_property.out | head -20 || true; else echo 'NO update_causal_property.out found'; fi"

echo "\n3) Count active mn.sim_ containers from host docker ps (quick check):"
docker ps --format '{{.Names}}' | grep '^mn.sim_' || echo 'No mn.sim_ container names found in docker ps output'

echo "\n4) Run quick Django checks inside mn.middts to inspect Device / DigitalTwinInstance counts and a sample query"
docker exec -it "$MID_CNT" bash -lc "cd /middleware-dt || true; if [ -f manage.py ]; then echo '-> Running Django checks...'; python3 manage.py shell -c \"from facade.models import Device; from orchestrator.models import DigitalTwinInstance; print('Device.count=', Device.objects.count()); print('DT.count=', DigitalTwinInstance.objects.count()); print('Sample device identifiers:', list(Device.objects.values_list('identifier', flat=True)[:10]));\"; else echo 'manage.py not found in /middleware-dt'; fi"

echo "\n5) Attempt to run the auto-detection function path (dry-run) via manage.py shell (ensures Django apps loaded):"
docker exec -it "$MID_CNT" bash -lc "cd /middleware-dt || true; if [ -f manage.py ]; then echo '-> Running auto-detect via manage.py shell...'; python3 manage.py shell -c \"from orchestrator.management.commands.update_causal_property import Command; print('auto_detect_active_devices ->', Command().auto_detect_active_devices())\"; else echo 'manage.py not found, skipping auto-detect dry-run'; fi"

echo "\nDiagnostics completed."
