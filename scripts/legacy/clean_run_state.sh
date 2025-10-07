#!/usr/bin/env bash
set -euo pipefail

# Kill simulator and middts processes and remove pidfiles inside containers
# Usage: sudo scripts/clean_run_state.sh

log(){ echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }

# kill scheduler persisted pid if present
if [ -f results/condominio_scheduler.pid ]; then
  pid=$(cat results/condominio_scheduler.pid 2>/dev/null || true)
  if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
    log "Killing persisted scheduler pid $pid"
    kill "$pid" 2>/dev/null || true
  fi
  rm -f results/condominio_scheduler.pid || true
fi

# For each simulator container, kill send_telemetry and remove pidfile
for s in $(docker ps --format '{{.Names}}' | grep -E 'sim[_-]?[0-9]+' || true); do
  [ -z "$s" ] && continue
  log "Cleaning simulator $s"
  docker exec "$s" bash -lc "pkill -f send_telemetry || true; pkill -f scenario_runner.py || true; rm -f /tmp/send_telemetry.pid || true" || true
done

# For middts container, kill updater and remove pidfile
MID=$(docker ps --format '{{.Names}}' | grep -E 'middts|middleware' | head -n1 || true)
if [ -n "$MID" ]; then
  log "Cleaning middts container $MID"
  docker exec "$MID" bash -lc "pkill -f update_causal_property || true; pkill -f manage.py || true; rm -f /tmp/update_causal_property.pid || true" || true
fi

log "Cleanup done"
