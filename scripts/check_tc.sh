#!/usr/bin/env bash
set -euo pipefail

# scripts/check_tc.sh - dump tc qdisc and IP info for mn.* containers
for c in $(docker ps --format '{{.Names}}' | grep '^mn\.' || true); do
  echo "---- container: $c ----"
  echo "pid: $(docker inspect -f '{{.State.Pid}}' $c 2>/dev/null || echo '-')"
  echo "interfaces:";
  docker exec $c bash -lc "ip -brief addr || true"
  echo "qdiscs:";
  # prefer to run inside container, fallback to nsenter
  if docker exec $c bash -lc "command -v tc >/dev/null 2>&1"; then
    docker exec $c bash -lc "tc qdisc show || true"
  else
    PID=$(docker inspect -f '{{.State.Pid}}' $c 2>/dev/null || true)
    if [ -n "$PID" ] && command -v nsenter >/dev/null 2>&1; then
      nsenter -t "$PID" -n -- tc qdisc show || true
    else
      echo "  (tc not found and nsenter not available)"
    fi
  fi
  echo
done
