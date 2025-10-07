#!/usr/bin/env bash
# Wait for topology readiness: checks docker mn.* containers and screen logs
# Usage: scripts/wait_topology_ready.sh [TIMEOUT_SECONDS]

ROOT=$(dirname "$(dirname "$(readlink -f "$0")")")
TIMEOUT=${1:-300}
INTERVAL=5
END=$((SECONDS+TIMEOUT))
echo "[wait] Waiting up to ${TIMEOUT}s for topology readiness..."

required=(mn.sim_001 mn.middts mn.influxdb mn.tb mn.db)

check_containers() {
  local missing=()
  for c in "${required[@]}"; do
    if ! sudo docker ps --filter "name=^${c}$" --format '{{.Names}}' | grep -x "${c}" >/dev/null 2>&1; then
      missing+=("${c}")
    fi
  done
  if [ ${#missing[@]} -eq 0 ]; then
    return 0
  else
    echo "[wait] missing containers: ${missing[*]}"
    return 1
  fi
}

check_screen_logs() {
  # Try to hardcopy the containernet screen into /tmp and search for net.start marker
  if screen -ls | grep -q containernet; then
    # If multiple containernet sessions exist, pick the most recent one
    session=$(screen -ls | awk '/containernet/ {print $1}' | tail -n1)
    if [ -n "$session" ]; then
      echo "[wait] using screen session: $session"
      tmpf="/tmp/containernet_screen_${session}.log"
      screen -S "$session" -X hardcopy "$tmpf" 2>/dev/null || true
      if [ -f "$tmpf" ]; then
        if grep -E "\[net\] aguardando containers docker estarem Running|net.start\(\)" "$tmpf" >/dev/null 2>&1; then
          echo "[wait] detected net.start marker in screen log (session $session)"
          return 0
        fi
      fi
    fi
  fi
  return 1
}

while [ $SECONDS -lt $END ]; do
  ok=1
  if ! check_containers; then ok=0; fi
  if ! check_screen_logs; then ok=0; fi
  if [ $ok -eq 1 ]; then
    echo "[wait] Topology appears ready"
    exit 0
  fi
  sleep $INTERVAL
done

echo "[wait] Timeout waiting for topology readiness"
exit 2
