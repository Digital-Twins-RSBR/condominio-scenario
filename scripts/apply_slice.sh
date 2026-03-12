#!/usr/bin/env bash
set -euo pipefail

# scripts/apply_slice.sh (renamed from cenario_test.sh)
# Orquestra aplicação de slice (profile) na topologia e opcionalmente executa o cenário

# Usage/help header
usage() {
  cat <<EOF
Usage: $0 [OPTIONS] PROFILE [EXECUTE_TEST_SCENARIO] [DURATION]
  Or:   $0 [OPTIONS] PROFILE [--execute-scenario SECONDS]

Options:
  --apply-only           Apply the profile to running topology and exit.
  --no-tb-config         Skip ThingsBoard config adaptation (use existing config).
  --raw                  Use raw ThingsBoard config (30000ms timeout, measure real latencies).
  --m2s-perf             Use M2S performance mode (URLLC tuned config + timestamps-only hot path).
  PROFILE                Topology profile name (urllc, best_effort, eMBB). Default: best_effort
  EXECUTE_TEST_SCENARIO  Positional: 0 (default) to not execute scenario, 1 to execute.
  --execute-scenario N   Long form: run the scenario for N seconds (sets EXECUTE_TEST_SCENARIO=1 and DURATION=N).
  DURATION               Positional 3: duration in seconds when using positional EXECUTE_TEST_SCENARIO. Default: 1800

Examples:
  # Run eMBB with adaptive ThingsBoard config (500ms timeout)
  $0 embb --execute-scenario 300
  
  # Run eMBB WITHOUT changing ThingsBoard config (baseline comparison)
  $0 --no-tb-config embb --execute-scenario 300
  
  # Run eMBB with RAW config (5000ms timeout, measure real latencies)
  $0 --raw embb --execute-scenario 600

  # Run URLLC with M2S performance config (220ms RPC + middleware fast mode)
  $0 --m2s-perf urllc --execute-scenario 300

  # Optional: full blind perf mode (disables M2S timestamp writes too)
  M2S_PERF_FULL=1 $0 --m2s-perf urllc --execute-scenario 300
  
  # Run URLLC with default config (150ms timeout)
  $0 urllc --execute-scenario 1800
EOF
}

# Defaults
PROFILE=""
EXECUTE_TEST_SCENARIO=0
DURATION="1800"
APPLY_TB_CONFIG=true  # By default, apply ThingsBoard config adaptation
USE_RAW_CONFIG=false  # Use raw config (high timeout) to measure real latencies
USE_M2S_PERF=false    # Use M2S performance profile/configuration

# Parse all arguments (including flags before PROFILE)
ARGS=("$@")
i=0

while [ $i -lt ${#ARGS[@]} ]; do
  a="${ARGS[$i]}"
  case "$a" in
    --no-tb-config)
      APPLY_TB_CONFIG=false
      i=$((i+1))
      continue
      ;;
    --raw)
      USE_RAW_CONFIG=true
      APPLY_TB_CONFIG=true  # Raw config still requires applying config
      i=$((i+1))
      continue
      ;;
    --m2s-perf)
      USE_M2S_PERF=true
      APPLY_TB_CONFIG=true
      i=$((i+1))
      continue
      ;;
    --execute-scenario)
      # next element is duration
      if [ $((i+1)) -lt ${#ARGS[@]} ]; then
        EXECUTE_TEST_SCENARIO=1
        DURATION="${ARGS[$((i+1))]}"
        i=$((i+2))
        continue
      else
        echo "--execute-scenario requires a numeric argument" >&2; usage; exit 1
      fi
      ;;
    --execute-scenario=*)
      DURATION="${a#--execute-scenario=}"
      EXECUTE_TEST_SCENARIO=1
      ;;
    --help|-h)
      usage; exit 0
      ;;
    --*)
      # unknown flag: skip
      ;;
    *)
      # First non-flag argument is PROFILE
      if [ -z "$PROFILE" ]; then
        PROFILE="$a"
      # Subsequent positional: can be EXECUTE_TEST_SCENARIO (0/1/true/false) or numeric duration
      elif echo "$a" | grep -Eq '^[0-9]+$'; then
        EXECUTE_TEST_SCENARIO=1
        DURATION="$a"
      else
        case "$(echo "$a" | tr '[:upper:]' '[:lower:]')" in
          1|true|yes)
            EXECUTE_TEST_SCENARIO=1
            ;;
          0|false|no)
            EXECUTE_TEST_SCENARIO=0
            ;;
          *)
            # ignore unknown positional
            ;;
        esac
      fi
      ;;
  esac
  i=$((i+1))
done

# Default profile if not set
PROFILE="${PROFILE:-best_effort}"

RESULTS_DIR="${RESULTS_DIR:-outputs/results}"
TOPO_SCREEN="topo"
TOPO_MAKE_TARGET="topo"
MAKE_CMD="make"

# Create organized test directory structure
TEST_TIMESTAMP=$(date -u +'%Y%m%dT%H%M%SZ')
TEST_DIR="${RESULTS_DIR}/test_${TEST_TIMESTAMP}_${PROFILE}"

# marker to remember last applied profile (to avoid re-applying)
PROFILE_MARKER=".current_slice_profile"

# load .env if present
if [ -f .env ]; then
  # shellcheck disable=SC1091
  . .env
fi

mkdir -p "$RESULTS_DIR"
mkdir -p "$TEST_DIR"
echo "[🗂️] Test results will be organized in: $TEST_DIR"

# persistent scheduler pid file so repeated runs can detect/kill previous scheduler
SCHED_PID_FILE="${RESULTS_DIR}/condominio_scheduler.pid"

log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }

# check_http_ready_in_container <container> <url>
# Tries curl, then wget, then python3 stdlib to avoid false negatives when curl is absent.
check_http_ready_in_container() {
  local c="$1"
  local url="$2"
  docker exec "$c" bash -lc '
    URL="$1"
    if command -v curl >/dev/null 2>&1; then
      # Any HTTP response means service is up; do not require 2xx.
      curl -sS -o /dev/null --max-time 2 "$URL" >/dev/null 2>&1 && exit 0
    fi
    if command -v wget >/dev/null 2>&1; then
      wget -q -T 2 -O /dev/null "$URL" >/dev/null 2>&1 && exit 0
    fi
    if command -v python3 >/dev/null 2>&1; then
      python3 - "$URL" <<"PY" >/dev/null 2>&1
import sys, urllib.request
import urllib.error
try:
    urllib.request.urlopen(sys.argv[1], timeout=2)
    sys.exit(0)
except urllib.error.HTTPError:
    # HTTPError still means endpoint responded.
    sys.exit(0)
except Exception:
    sys.exit(1)
PY
      [ $? -eq 0 ] && exit 0
    fi
    exit 1
  ' _ "$url"
}

# ============================================================================
# apply_thingsboard_config: Swap ThingsBoard config based on network profile
# ============================================================================
apply_thingsboard_config() {
    local profile=$1
    local tb_config_file=""
    local tb_container=""

  write_tb_config_inplace() {
    local src_file="$1"
    local dest_file="$2"

    # First try direct docker cp (fast path)
    if docker cp "$src_file" "$tb_container:$dest_file" >/dev/null 2>&1; then
      return 0
    fi

    # Fallback for bind-mounted/busy target files: copy to /tmp and overwrite in-place
    local tmp_target="/tmp/$(basename "$dest_file").new"
    if ! docker cp "$src_file" "$tb_container:$tmp_target" >/dev/null 2>&1; then
      return 1
    fi

    docker exec "$tb_container" bash -lc "cat '$tmp_target' > '$dest_file' && rm -f '$tmp_target'"
  }
    
    # Find ThingsBoard container
    tb_container=$(docker ps --format '{{.Names}}' | grep -E 'tb|thingsboard' | head -n1 || true)
    
    if [ -z "$tb_container" ]; then
        log "WARNING: ThingsBoard container not found, skipping config swap"
        return 0
    fi
    
    # Determine if using RAW config (high timeout for real latency measurement)
    local config_suffix=""
    local config_label=""
    if [ "$USE_M2S_PERF" = true ]; then
      config_suffix="-m2s-perf"
      config_label="M2S performance"
    elif [ "$USE_RAW_CONFIG" = true ]; then
        config_suffix="-raw"
        config_label="RAW (no timeout artificial)"
    fi
    
    # Select config file based on profile
    local expected_timeout="150"
    case "$profile" in
        urllc)
            tb_config_file="thingsboard-urllc${config_suffix}.yml"
          if [ "$USE_M2S_PERF" = true ]; then
            expected_timeout="220"
            log "Applying ThingsBoard M2S performance config for URLLC (timeout 220ms)"
          elif [ "$USE_RAW_CONFIG" = true ]; then
                expected_timeout="30000"
                log "📡 Applying ThingsBoard RAW config for URLLC (timeout 30000ms - measure real latencies)"
            else
                expected_timeout="150"
                log "📡 Applying ThingsBoard config for URLLC (timeout 150ms)"
            fi
            ;;
        eMBB|embb)
            tb_config_file="thingsboard-embb${config_suffix}.yml"
            if [ "$USE_RAW_CONFIG" = true ]; then
                expected_timeout="5000"
                log "📡 Applying ThingsBoard RAW config for eMBB (timeout 5000ms - measure real latencies)"
            else
                expected_timeout="300"
                log "📡 Applying ThingsBoard config for eMBB (timeout 300ms)"
            fi
            ;;
        best_effort|best-effort)
            tb_config_file="thingsboard-best-effort${config_suffix}.yml"
            if [ "$USE_RAW_CONFIG" = true ]; then
                expected_timeout="10000"
                log "📡 Applying ThingsBoard RAW config for Best-Effort (timeout 10000ms - measure real latencies)"
            else
                expected_timeout="500"
                log "📡 Applying ThingsBoard config for Best-Effort (timeout 500ms)"
            fi
            ;;
        *)
            log "WARNING: Unknown profile '$profile', using URLLC config as fallback"
            tb_config_file="thingsboard-urllc${config_suffix}.yml"
            if [ "$USE_RAW_CONFIG" = true ]; then
                expected_timeout="30000"
            else
                expected_timeout="150"
            fi
            ;;
    esac
    
    # Check if config file exists
    if [ ! -f "config/$tb_config_file" ]; then
        log "ERROR: Config file config/$tb_config_file not found!"
        return 1
    fi

    # Fast path: if current TB config already has expected timeout, skip copy/restart
    if docker exec "$tb_container" bash -lc "grep -Eq '^[[:space:]]*CLIENT_SIDE_RPC_TIMEOUT:[[:space:]]*${expected_timeout}(ms)?[[:space:]]*$' /usr/share/thingsboard/conf/thingsboard.yml" >/dev/null 2>&1; then
      log "✅ ThingsBoard already configured with CLIENT_SIDE_RPC_TIMEOUT=${expected_timeout}; skipping config swap/restart"
      return 0
    fi
    
    # Copy config to container (with fallback for busy bind-mounted files)
    log "Copying config/$tb_config_file to container $tb_container..."
    if ! write_tb_config_inplace "config/$tb_config_file" "/usr/share/thingsboard/conf/thingsboard.yml"; then
      log "ERROR: Failed to apply config to /usr/share/thingsboard/conf/thingsboard.yml"
      return 1
    fi
    if ! write_tb_config_inplace "config/$tb_config_file" "/usr/share/thingsboard/bin/thingsboard.yml"; then
      log "WARNING: Failed to apply config to /usr/share/thingsboard/bin/thingsboard.yml (may not exist)"
    fi
    
    # Restart ThingsBoard using full container restart for clean initialization
    # This ensures complete isolation and eliminates state from previous tests
    log "Restarting ThingsBoard with full container restart for clean initialization..."
    restart_ok=0

    if docker restart "$tb_container" >/dev/null 2>&1; then
      restart_ok=1
      log "✅ Container restart initiated"
    else
      log "ERROR: docker restart failed for $tb_container"
    fi

    if [ "$restart_ok" -eq 0 ]; then
      log "WARNING: Container restart failed; proceeding to readiness check"
    fi
    
    # Wait for ThingsBoard to become ready after full container restart
    # Full container restart + JVM init takes time (especially with 3GB+ heap)
    local max_wait=600  # 10 minutes for full container restart + JVM initialization
    log "Waiting for ThingsBoard to initialize (max ${max_wait}s - full container restart + JVM init)..."
    local waited=0
    while [ $waited -lt $max_wait ]; do
        # Check if ThingsBoard port is responding
      if check_http_ready_in_container "$tb_container" "http://localhost:8080/api/status" || \
         check_http_ready_in_container "$tb_container" "http://localhost:8080"; then
            log "✅ ThingsBoard restarted successfully with $tb_config_file! (responded after ${waited}s)"
            return 0
        fi
        sleep 3
        waited=$((waited + 3))
        if [ $((waited % 30)) -eq 0 ]; then
            log "Still waiting for ThingsBoard... (${waited}s elapsed, max ${max_wait}s)"
        fi
    done
    
    log "ERROR: ThingsBoard did not respond within ${max_wait}s after config apply"
    # Even if readiness failed, continue with test (may still work)
    log "WARNING: Proceeding with test despite ThingsBoard readiness timeout (may fail)"
    return 0
}

log "Starting topology in screen (PROFILE=$PROFILE)..."

# apply_topo_profile: apply tc/netem to mn.* containers per profile
apply_topo_profile() {
  local prof="$1"
  log "Applying topo profile: $prof"
  case "$prof" in
    urllc)
      BW=1000; DELAY="0.2ms"; LOSS=0
      ;;
    eMBB|embb)
      BW=300; DELAY="25ms"; LOSS=0.2
      ;;
    *)
      BW=200; DELAY="50ms"; LOSS=0.5
      ;;
  esac
  # iterate mn.* containers and apply tc on eth0 where present
  docker ps --format '{{.Names}}' | grep '^mn\.' | while read -r cname; do
    [ -z "$cname" ] && continue
    # skip core services: do not shape influx/thingsboard/middts/neo4j/database containers
    case "$cname" in
      *influx*|*tb*|*thingsboard*|*middts*|*middleware*|*neo4j*|*parser*|*db*|*postgres*)
        log "Skipping shaping for core container $cname to keep core links at max"
        continue
        ;;
    esac
    # check if container has eth0
    if docker exec "$cname" bash -lc "ip link show eth0 >/dev/null 2>&1"; then
      log "Applying tc on $cname: bw=${BW}mbit delay=${DELAY} loss=${LOSS}%"
      # prefer to run tc inside the container if available
      if docker exec "$cname" bash -lc "command -v tc >/dev/null 2>&1"; then
        # delete existing qdisc quietly, then add shaping
        docker exec "$cname" bash -lc "tc qdisc del dev eth0 root 2>/dev/null || true; tc qdisc add dev eth0 root handle 1:0 tbf rate ${BW}mbit burst 32kbit latency 400ms || true; tc qdisc add dev eth0 parent 1:0 handle 10: netem delay ${DELAY} loss ${LOSS}% || true" > /dev/null 2>&1 || log "tc apply failed on $cname"
      else
        # fallback: try to run tc in the container network namespace from the host using nsenter
        PID=$(docker inspect -f '{{.State.Pid}}' "$cname" 2>/dev/null || true)
        if [ -n "$PID" ] && command -v nsenter >/dev/null 2>&1; then
          log "tc not found in $cname; using nsenter into PID $PID to apply tc"
          nsenter -t "$PID" -n -- tc qdisc del dev eth0 root 2>/dev/null || true
          nsenter -t "$PID" -n -- tc qdisc add dev eth0 root handle 1:0 tbf rate ${BW}mbit burst 32kbit latency 400ms || log "nsenter tc tbf failed on $cname"
          nsenter -t "$PID" -n -- tc qdisc add dev eth0 parent 1:0 handle 10: netem delay ${DELAY} loss ${LOSS}% || log "nsenter tc netem failed on $cname"
        else
          log "tc not available inside $cname and nsenter not present on host; skipping tc for $cname"
        fi
      fi
    else
      log "Skipping $cname: no eth0"
    fi
  done
  # write profile marker so subsequent invocations can skip redundant apply
  if [ -w . ] || [ -w "$(dirname "$PROFILE_MARKER")" ] 2>/dev/null; then
    echo "${prof}" > "$PROFILE_MARKER" 2>/dev/null || true
  else
    # fallback: write into results dir
    echo "${prof}" > "${RESULTS_DIR}/${PROFILE_MARKER}" 2>/dev/null || true
  fi
}

# If a containernet topology is already running (containers named mn.*), do not recreate it.
if docker ps --format '{{.Names}}' | grep -q '^mn\.'; then
  log "Detected existing Containernet containers (mn.*). Will not recreate topology."
  # check marker to avoid redundant apply
  CUR=""
  if [ -f "$PROFILE_MARKER" ]; then
    CUR="$(cat "$PROFILE_MARKER" 2>/dev/null || true)"
  elif [ -f "${RESULTS_DIR}/${PROFILE_MARKER}" ]; then
    CUR="$(cat "${RESULTS_DIR}/${PROFILE_MARKER}" 2>/dev/null || true)"
  fi
  if [ "$CUR" = "$PROFILE" ]; then
    log "Profile $PROFILE already applied (marker found); skipping apply"
  else
    log "Applying profile=${PROFILE} to running nodes."
    apply_topo_profile "$PROFILE"
  fi
  if [ "$EXECUTE_TEST_SCENARIO" -eq 0 ]; then
    log "EXECUTE_TEST_SCENARIO=0; exiting after applying profile"
    exit 0
  fi
else
  screen -dmS "$TOPO_SCREEN" bash -lc "${MAKE_CMD} ${TOPO_MAKE_TARGET} PROFILE=${PROFILE}"
  log "Screen session '${TOPO_SCREEN}' started. Waiting for containers to come up before applying profile."
fi

wait_for_services() {
  local timeout=${1:-900}
  local waited=0
  log "Waiting for core services (influx, tb, middts, at least one sim) up (timeout ${timeout}s)..."
  while [ "$waited" -lt "$timeout" ]; do
    names="$(docker ps --format '{{.Names}}' || true)"
    echo "$names" | grep -q -E 'influx' && has_influx=1 || has_influx=0
    echo "$names" | grep -q -E 'tb|thingsboard' && has_tb=1 || has_tb=0
    echo "$names" | grep -q -E 'middts|middleware' && has_middts=1 || has_middts=0
    echo "$names" | grep -q -E 'sim[_-]?[0-9]+' && has_sim=1 || has_sim=0

    if [ "$has_influx" -eq 1 ] && [ "$has_tb" -eq 1 ] && [ "$has_middts" -eq 1 ] && [ "$has_sim" -eq 1 ]; then
      log "Core containers detected: influx, tb, middts, sim"
      return 0
    fi
    sleep 3
    waited=$((waited+3))
  done
  return 1
}

if ! wait_for_services 900; then
  log "ERROR: Timed out waiting for core services to appear. Aborting run to avoid invalid measurements."
  exit 1
fi

# ============================================================================
# ThingsBoard Config: SKIPPED - container already started with correct config
# ============================================================================
# Since topology recreation now mounts the correct config file based on PROFILE
# and USE_RAW_CONFIG, ThingsBoard starts with the right configuration.
# No need to swap config files or restart container.
log "✅ ThingsBoard already configured via topology mount (profile: $PROFILE, raw: ${USE_RAW_CONFIG:-false}, m2s_perf: ${USE_M2S_PERF:-false})"
log "   Skipping config adaptation - container started with correct config"

# Apply traffic control AFTER containers are fully up AND ThingsBoard is configured
log "Applying profile=${PROFILE} to containers now that they are ready."
apply_topo_profile "$PROFILE"

# record start time
START_ISO="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
START_EPOCH="$(date +%s)"
log "Test start time: $START_ISO (epoch: $START_EPOCH)"

# compute stop times up-front so they are available to export logic
STOP_EPOCH=$((START_EPOCH + DURATION))
STOP_ISO="$(date -u -d "@${STOP_EPOCH}" +'%Y-%m-%dT%H:%M:%SZ')"
log "Test stop time: $STOP_ISO (epoch: $STOP_EPOCH)"

find_container() {
  local pat="$1"
  docker ps --format '{{.Names}}' | grep -i "$pat" | head -n1 || true
}

########################################
# Link outage scheduler helpers
########################################
resolve_targets() {
  local pattern="$1"
  if [ "$pattern" = "global" ]; then
    docker ps --format '{{.Names}}' | grep '^mn\.' || true
  else
    # treat pattern as regex for grep; fall back to literal name
    docker ps --format '{{.Names}}' | grep -E "$pattern" || echo "$pattern"
  fi
}

apply_link_down() {
  local target="$1"
  local event_timestamp_iso="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  local event_timestamp_epoch="$(date +%s)"
  
  for c in $(resolve_targets "$target"); do
    [ -z "$c" ] && continue
    if docker exec "$c" bash -lc "ip link show eth0 >/dev/null 2>&1"; then
      docker exec "$c" bash -lc "ip link set eth0 down" >/dev/null 2>&1 || {
        PID=$(docker inspect -f '{{.State.Pid}}' "$c" 2>/dev/null || true)
        if [ -n "$PID" ] && command -v nsenter >/dev/null 2>&1; then
          nsenter -t "$PID" -n -- ip link set eth0 down || true
        fi
      }
      if [ -z "${SUPPRESS_LINK_LOG:-}" ]; then
        log "LINK DOWN -> $c"
      fi
      # Log event with timestamp for later filtering
      if [ -n "${TEST_DIR:-}" ]; then
        echo "{\"timestamp\":\"${event_timestamp_iso}\",\"epoch\":${event_timestamp_epoch},\"target\":\"${c}\",\"event\":\"down\"}" >> "${TEST_DIR}/link_events.jsonl"
      fi
    else
      log "Cannot bring down link for $c: no eth0"
    fi
  done
}

apply_link_up() {
  local target="$1"
  local event_timestamp_iso="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  local event_timestamp_epoch="$(date +%s)"
  
  for c in $(resolve_targets "$target"); do
    [ -z "$c" ] && continue
    if docker exec "$c" bash -lc "ip link show eth0 >/dev/null 2>&1"; then
      docker exec "$c" bash -lc "ip link set eth0 up" >/dev/null 2>&1 || {
        PID=$(docker inspect -f '{{.State.Pid}}' "$c" 2>/dev/null || true)
        if [ -n "$PID" ] && command -v nsenter >/dev/null 2>&1; then
          nsenter -t "$PID" -n -- ip link set eth0 up || true
        fi
      }
      if [ -z "${SUPPRESS_LINK_LOG:-}" ]; then
        log "LINK UP   -> $c"
      fi
      # Log event with timestamp for later filtering
      if [ -n "${TEST_DIR:-}" ]; then
        echo "{\"timestamp\":\"${event_timestamp_iso}\",\"epoch\":${event_timestamp_epoch},\"target\":\"${c}\",\"event\":\"up\"}" >> "${TEST_DIR}/link_events.jsonl"
      fi
    else
      log "Cannot bring up link for $c: no eth0"
    fi
  done
}

start_scheduler() {
  local schedule="$1"
  if [ -z "$schedule" ] || [ ! -f "$schedule" ]; then
    log "No schedule file found at $schedule; will use builtin scheduler patterns"
    start_builtin_scheduler "$DURATION"
    return 0
  fi
  log "Starting link scheduler from $schedule"
  (
    while IFS=, read -r start_offset duration target mode params; do
      # strip spaces
      start_offset="$(echo "$start_offset" | tr -d '[:space:]')"
      # skip header or comments (empty or lines starting with #)
      if [ -z "$start_offset" ] || echo "$start_offset" | grep -q '^#'; then
        continue
      fi
      duration="$(echo "${duration:-0}" | tr -d '[:space:]')"
      # compute absolute start time
      event_start=$(( START_EPOCH + start_offset ))
      now_epoch=$(date +%s)
      sleep_time=$(( event_start - now_epoch ))
      if [ "$sleep_time" -gt 0 ]; then sleep "$sleep_time"; fi
      log "Scheduler: executing $mode for target=$target duration=$duration params=$params"
      case "$mode" in
        down)
          apply_link_down "$target"
          ( sleep "$duration"; apply_link_up "$target" ) &
          ;;
        flap)
          # params example: cycles=5;down=10;up=50
          cycles=$(echo "$params" | sed -n 's/.*cycles=\([0-9]*\).*/\1/p')
          down_t=$(echo "$params" | sed -n 's/.*down=\([0-9]*\).*/\1/p')
          up_t=$(echo "$params" | sed -n 's/.*up=\([0-9]*\).*/\1/p')
          cycles=${cycles:-5}; down_t=${down_t:-10}; up_t=${up_t:-50}
          for i in $(seq 1 $cycles); do
            apply_link_down "$target"
            sleep "$down_t"
            apply_link_up "$target"
            sleep "$up_t"
          done
          ;;
        degrade)
          # params e.g. bw=50mbit;delay=100ms;loss=2%
          # For simplicity we parse bw and netem params
          bw=$(echo "$params" | sed -n 's/.*bw=\([^;]*\).*/\1/p')
          netem_params=$(echo "$params" | sed -n 's/.*;\?\(delay=[^;]*\|loss=[^;]*\).*$/\1/p' || true)
          for c in $(resolve_targets "$target"); do
            PID=$(docker inspect -f '{{.State.Pid}}' "$c" 2>/dev/null || true)
            if docker exec "$c" bash -lc "command -v tc >/dev/null 2>&1"; then
              docker exec "$c" bash -lc "tc qdisc del dev eth0 root 2>/dev/null || true; tc qdisc add dev eth0 root handle 1:0 tbf rate ${bw:-50mbit} burst 32kbit latency 400ms || true; tc qdisc add dev eth0 parent 1:0 handle 10: netem ${netem_params:-delay 100ms} || true" || log "tc degrade failed on $c"
            elif [ -n "$PID" ] && command -v nsenter >/dev/null 2>&1; then
              nsenter -t "$PID" -n -- tc qdisc del dev eth0 root 2>/dev/null || true
              nsenter -t "$PID" -n -- tc qdisc add dev eth0 root handle 1:0 tbf rate ${bw:-50mbit} burst 32kbit latency 400ms || true
              nsenter -t "$PID" -n -- tc qdisc add dev eth0 parent 1:0 handle 10: netem ${netem_params:-delay 100ms} || true
            else
              log "Cannot apply degrade to $c: no tc and no nsenter"
            fi
          done
          # schedule removal
          ( sleep "$duration"; for c in $(resolve_targets "$target"); do PID=$(docker inspect -f '{{.State.Pid}}' "$c" 2>/dev/null || true); nsenter -t "$PID" -n -- tc qdisc del dev eth0 root 2>/dev/null || true; done ) &
          ;;
        *)
          log "Unknown scheduler mode: $mode"
          ;;
      esac
    done < "$schedule"
  ) &
  SCHED_PID=$!
  # persist pid so later runs can find and stop this scheduler
  echo "$SCHED_PID" > "${SCHED_PID_FILE}" 2>/dev/null || true
  log "Scheduler started (PID $SCHED_PID)"
}

# Builtin scheduler: generate uptime patterns per simulator index.
# Patterns (example):
# - sim 1: always up
# - sim 2: 66% up / 33% down (periodic)
# - sim 3: intermittent (short flaps)
# - others: randomized flaps to exercise cases
start_builtin_scheduler() {
  local total_duration=${1:-1800}
  log "Starting builtin scheduler for duration=${total_duration}s"
  (
    now=$(date +%s)
    end=$(( now + total_duration ))
    sims=( $(docker ps --format '{{.Names}}' | grep -E 'sim[_-]?[0-9]+' | sort) )
    if [ ${#sims[@]} -eq 0 ]; then
      log "No simulator containers found for builtin scheduler"
      exit 0
    fi
    idx=0
    for s in "${sims[@]}"; do
      idx=$((idx+1))
      # deterministic patterns per simulator index (no randomness)
      case $idx in
        1)
          # always up
          log "Builtin pattern: $s -> always up"
          ;;
        2)
          # 66% up, 33% down (cycle 30s: 20 up / 10 down)
          ( while [ $(date +%s) -lt $end ]; do apply_link_up "$s"; sleep 20; apply_link_down "$s"; sleep 10; done ) &
          ;;
        3)
          # intermittent (cycle 20s: 15 up / 5 down)
          ( while [ $(date +%s) -lt $end ]; do apply_link_up "$s"; sleep 15; apply_link_down "$s"; sleep 5; done ) &
          ;;
        4)
          # 75% up / 25% down (cycle 40s: 30 up / 10 down)
          ( while [ $(date +%s) -lt $end ]; do apply_link_up "$s"; sleep 30; apply_link_down "$s"; sleep 10; done ) &
          ;;
        5)
          # 50% up / 50% down (cycle 20s: 10 up / 10 down)
          ( while [ $(date +%s) -lt $end ]; do apply_link_up "$s"; sleep 10; apply_link_down "$s"; sleep 10; done ) &
          ;;
        *)
          # for idx >5, cycle through pre-defined patterns deterministically
          mod=$(( (idx - 1) % 5 + 1 ))
          case $mod in
            1) ( while [ $(date +%s) -lt $end ]; do apply_link_up "$s"; sleep 20; apply_link_down "$s"; sleep 10; done ) & ;;
            2) ( while [ $(date +%s) -lt $end ]; do apply_link_up "$s"; sleep 15; apply_link_down "$s"; sleep 5; done ) & ;;
            3) ( while [ $(date +%s) -lt $end ]; do apply_link_up "$s"; sleep 30; apply_link_down "$s"; sleep 10; done ) & ;;
            4) ( while [ $(date +%s) -lt $end ]; do apply_link_up "$s"; sleep 10; apply_link_down "$s"; sleep 10; done ) & ;;
            5) ( while [ $(date +%s) -lt $end ]; do apply_link_up "$s"; sleep 15; apply_link_down "$s"; sleep 5; done ) & ;;
          esac
          ;;
      esac
    done
  ) &
  SCHED_PID=$!
  echo "$SCHED_PID" > "${SCHED_PID_FILE}" 2>/dev/null || true
  log "Builtin scheduler started (PID $SCHED_PID)"
}

# start update_causal_property inside middts container
MID_CNT="$(find_container 'middts\|middleware')"
start_middts_update() {
  MID_CNT="$1"
  local m2s_perf_env="0"
  local m2s_perf_timestamps_only="0"
  local m2s_perf_full="0"
  if [ "$USE_M2S_PERF" = true ]; then
    m2s_perf_env="1"
    m2s_perf_timestamps_only="1"
    if [ "${M2S_PERF_FULL:-0}" = "1" ] || [ "${M2S_PERF_FULL:-0}" = "true" ]; then
      m2s_perf_timestamps_only="0"
      m2s_perf_full="1"
    fi
  fi
  if [ -n "$MID_CNT" ]; then
    # ALWAYS stop existing update_causal_property to avoid concurrent processes
    log "Stopping any existing update_causal_property in $MID_CNT"
    docker exec "$MID_CNT" bash -lc "pkill -f 'manage.py update_causal_property' || true; pkill -f 'manage.py listen_gateway' || true; rm -f /tmp/update_causal_property.pid /tmp/listen_gateway.pid || true" 2>/dev/null || true
    sleep 1  # Extra time for cleanup

    # If a pid file exists inside the container but the process is gone, remove stale pidfile.
    RUNNING_PID_CHECK=$(docker exec "$MID_CNT" bash -lc "if [ -f /tmp/update_causal_property.pid ]; then pid=\$(cat /tmp/update_causal_property.pid 2>/dev/null || true); if [ -n \"\$pid\" ]; then if ps -p \$pid >/dev/null 2>&1; then echo running; else rm -f /tmp/update_causal_property.pid; echo stale; fi; fi; fi" 2>/dev/null || true)
    if [ "${RUNNING_PID_CHECK}" = "running" ]; then
      log "update_causal_property already running in $MID_CNT (pidfile present); skipping start"
      return 0
    fi
    
    # Ensure core services are reachable before starting the updater to avoid missed RPCs/exports
    log "Ensuring InfluxDB and ThingsBoard services are responding before starting update_causal_property"
    
    # Wait for actual service responses (proves init completed, not just container running)
    # Bounded wait avoids the whole test being killed by outer timeout before workload starts.
    for svc_name in "ThingsBoard" "InfluxDB"; do
      case "$svc_name" in
        "ThingsBoard")
          host="mn.tb"
          port="8080"
          endpoint="/api/status"
          max_attempts=45    # 45 * 2s = 90s
          ;;
        "InfluxDB")
          host="mn.influxdb"
          port="8086"
          endpoint="/health"
          max_attempts=30    # 30 * 2s = 60s
          ;;
      esac
      
      log "Waiting for $svc_name ($host:$port$endpoint) to respond..."
      attempt=0
      while [ "$attempt" -lt "$max_attempts" ]; do
        # Try to reach the service endpoint
        if check_http_ready_in_container "$host" "http://localhost:$port$endpoint"; then
          log "✅ $svc_name responding at http://$host:$port$endpoint"
          break
        fi
        
        attempt=$((attempt+1))
        if [ $((attempt % 30)) -eq 0 ]; then
          log "⏳ Still waiting for $svc_name ($host:$port$endpoint)... (attempt $attempt)"
        fi
        sleep 2
      done

      if [ "$attempt" -ge "$max_attempts" ]; then
        log "⚠️  $svc_name not responding after $((max_attempts * 2))s; continuing anyway"
      fi
    done
    
    log "All services are responding and ready"

    log "Starting update_causal_property in container: $MID_CNT"
    
    # Determine optimal polling interval based on profile
    # URLLC: 3s (~0.33 Hz, ~200 commands/600s) - reduced pressure for better delivery/SLA stability
    # eMBB: 5s (0.2 Hz, ~120 commands/600s) - medium frequency
    # Best-Effort: 10s (0.1 Hz, ~60 commands/600s) - low frequency
    case "${PROFILE,,}" in
        urllc)
        POLLING_INTERVAL=3
            ;;
        embb)
            POLLING_INTERVAL=5
            ;;
        best_effort)
            POLLING_INTERVAL=10
            ;;
        *)
            # Fallback: read from .env or default to 5s
            POLLING_INTERVAL=$(grep '^MIDDLEWARE_POLLING_INTERVAL' services/middleware-dt/.env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo "5")
            ;;
    esac
    log "🎯 Using polling interval: ${POLLING_INTERVAL}s (profile: ${PROFILE})"
    
    # Start listen_gateway FIRST to capture S2M telemetry from all sensors
    log "🎧 Starting listen_gateway for S2M telemetry capture"
    docker exec -d "$MID_CNT" bash -lc "if [ -f /middleware-dt/.env ]; then set -a; . /middleware-dt/.env; set +a; fi; export M2S_PERF_MODE=${m2s_perf_env}; export M2S_PERF_TIMESTAMPS_ONLY=${m2s_perf_timestamps_only}; export M2S_PERF_FULL=${m2s_perf_full}; export M2S_DISABLE_RPC_INFLUX_HOTPATH=${m2s_perf_full}; cd /var/condominio-scenario/services/middleware-dt || true; nohup python3 manage.py listen_gateway --use-influxdb --interval ${POLLING_INTERVAL} > /middleware-dt/listen_gateway.out 2>&1 & echo \$! >/tmp/listen_gateway.pid" || log "Failed to exec listen_gateway (non-fatal)"
    sleep 2
    
    # Then start update_causal_property for M2S commands
    docker exec -d "$MID_CNT" bash -lc "if [ -f /middleware-dt/.env ]; then set -a; . /middleware-dt/.env; set +a; fi; export M2S_PERF_MODE=${m2s_perf_env}; export M2S_PERF_TIMESTAMPS_ONLY=${m2s_perf_timestamps_only}; export M2S_PERF_FULL=${m2s_perf_full}; export M2S_DISABLE_RPC_INFLUX_HOTPATH=${m2s_perf_full}; cd /var/condominio-scenario/services/middleware-dt || true; nohup python3 manage.py update_causal_property --interval ${POLLING_INTERVAL} > /middleware-dt/update_causal_property.out 2>&1 & echo \$! >/tmp/update_causal_property.pid" || log "Failed to exec update_causal_property (non-fatal)"
    # brief check
    sleep 1
    
    # Check listen_gateway status
    if docker exec "$MID_CNT" bash -lc "ps -ef | grep -v grep | grep listen_gateway >/dev/null 2>&1"; then
      log "✅ listen_gateway is running (capturing S2M telemetry from ALL sensors)"
    else
      log "⚠️  Warning: listen_gateway does not appear to be running"
    fi
    
    # Check update_causal_property status
    if docker exec "$MID_CNT" bash -lc "ps -ef | grep -v grep | grep update_causal_property >/dev/null 2>&1"; then
      log "✅ update_causal_property is running (sending M2S commands)"
    else
      log "Warning: update_causal_property does not appear to be running in $MID_CNT"
      # capture a short tail of the updater output if present for diagnosis
      docker exec "$MID_CNT" bash -lc "if [ -f /middleware-dt/update_causal_property.out ]; then tail -n 200 /middleware-dt/update_causal_property.out; fi" > "${TEST_DIR}/${PROFILE}_middts_update_tail_${TEST_TIMESTAMP}.log" 2>/dev/null || true
    fi
  else
    log "middts container not found, skipping update_causal_property start."
  fi
}

# start scheduler (scheduler is independent of scenario_runner)
# Start simulators' send_telemetry if not already running (helps when topology doesn't auto-start them)
start_simulators() {
  local m2s_perf_env="0"
  local m2s_perf_timestamps_only="0"
  local m2s_perf_full="0"
  if [ "$USE_M2S_PERF" = true ]; then
    m2s_perf_env="1"
    m2s_perf_timestamps_only="1"
    if [ "${M2S_PERF_FULL:-0}" = "1" ] || [ "${M2S_PERF_FULL:-0}" = "true" ]; then
      m2s_perf_timestamps_only="0"
      m2s_perf_full="1"
    fi
  fi
  for s in $(docker ps --format '{{.Names}}' | grep -E 'sim[_-]?[0-9]+' || true); do
    [ -z "$s" ] && continue
    
    # ALWAYS stop existing send_telemetry to avoid concurrent processes
    log "Stopping any existing send_telemetry in $s"
    docker exec "$s" bash -lc "pkill -f 'manage.py send_telemetry' || true; " 2>/dev/null || true
    sleep 0.5

    # If pidfile exists in container and process is alive, skip starting a new one
    SIM_RUNNING=$(docker exec "$s" bash -lc "if [ -f /tmp/send_telemetry.pid ]; then pid=\$(cat /tmp/send_telemetry.pid 2>/dev/null || true); if [ -n \"\$pid\" ]; then if ps -p \$pid >/dev/null 2>&1; then echo running; else rm -f /tmp/send_telemetry.pid; echo stale; fi; fi; fi" 2>/dev/null || true)
    if [ "${SIM_RUNNING}" = "running" ]; then
      log "send_telemetry already running in $s (pidfile present); skipping start"
    else
      log "Starting send_telemetry in $s"
    # start with --randomize to vary sensor timestamps and avoid deterministic collisions
    # Ensure .env exists inside the container (copy from .env.example if present)
    docker exec "$s" bash -lc "if [ ! -f /iot_simulator/.env ] && [ -f /iot_simulator/.env.example ]; then echo '[auto] copying .env.example -> .env inside container'; cp /iot_simulator/.env.example /iot_simulator/.env; fi" >/dev/null 2>&1 || true
    # Source the container's .env so THINGSBOARD_* and INFLUX_* are available to the process
    # HEARTBEAT_INTERVAL and optimizations are now set by default in Dockerfile
    # Start simulators with in-memory mode and Influx enabled by default
    # Use SIM_NO_INFLUX=1 in the container .env to disable Influx writes when needed
      docker exec -d "$s" bash -lc "if [ -f /iot_simulator/.env ]; then set -a; . /iot_simulator/.env; set +a; fi; export M2S_SIMULATOR_FAST_MODE=${m2s_perf_env}; export M2S_SIMULATOR_TIMESTAMPS_ONLY=${m2s_perf_timestamps_only}; export M2S_SIMULATOR_PERF_FULL=${m2s_perf_full}; export M2S_DISABLE_SIMULATOR_RPC_INFLUX=${m2s_perf_full}; cd /iot_simulator || true; \ 
    # Default flags: enable Influx and memory mode
    NO_INFLUX=\"\"; \ 
    if [ \"\${SIM_NO_INFLUX:-}\" = \"1\" ] || [ \"\${SIM_NO_INFLUX:-}\" = \"true\" ]; then \ 
      NO_INFLUX=\"--no-influx\"; \ 
    fi; \ 
    MEMORY_FLAG=\"--memory\"; \ 
    RANDOMIZE_FLAG=\"--randomize\"; \ 
    nohup python3 manage.py send_telemetry --use-influxdb \$RANDOMIZE_FLAG \$MEMORY_FLAG > /iot_simulator/send_telemetry.out 2>&1 & echo \$! >/tmp/send_telemetry.pid" || log "Failed to start send_telemetry in $s"
    # warn if THINGSBOARD credentials missing inside the container env file
    if ! docker exec "$s" bash -lc "[ -f /iot_simulator/.env ] && grep -q '^THINGSBOARD_USER=' /iot_simulator/.env >/dev/null 2>&1"; then
      log "Warning: THINGSBOARD_USER not found in /iot_simulator/.env inside $s"
    fi
    if ! docker exec "$s" bash -lc "[ -f /iot_simulator/.env ] && grep -q '^THINGSBOARD_PASSWORD=' /iot_simulator/.env >/dev/null 2>&1"; then
      log "Warning: THINGSBOARD_PASSWORD not found in /iot_simulator/.env inside $s"
    fi
    sleep 0.5
    fi
  done
}

SCHEDULE_FILE="${SCHEDULE_FILE:-scripts/link_schedule.csv}"

# If the operator explicitly disabled scheduling (SCHEDULE_FILE=/dev/null or 'none'), skip starting any scheduler.
if [ "${SCHEDULE_FILE}" = "/dev/null" ] || [ "${SCHEDULE_FILE}" = "none" ] || [ "${SCHEDULE_FILE}" = "disabled" ]; then
  log "Scheduler disabled (SCHEDULE_FILE=${SCHEDULE_FILE}); skipping scheduler startup"
else
  start_scheduler "$SCHEDULE_FILE"
fi

# Ensure simulators and middts updater are running before starting the test
start_simulators
start_middts_update "$MID_CNT"

# Optional warmup window so simulators can finish MQTT auth/subscription before
# we start counting the official workload time window.
WORKLOAD_WARMUP_SECONDS="${WORKLOAD_WARMUP_SECONDS:-12}"
case "$WORKLOAD_WARMUP_SECONDS" in
  ''|*[!0-9]*) WORKLOAD_WARMUP_SECONDS=12 ;;
esac
if [ "$WORKLOAD_WARMUP_SECONDS" -gt 0 ]; then
  log "Warmup: aguardando ${WORKLOAD_WARMUP_SECONDS}s para estabilizar MQTT/RPC antes do workload"
  sleep "$WORKLOAD_WARMUP_SECONDS"
fi

# Re-anchor export window to the actual workload start (after producers/consumers are up)
WORKLOAD_START_EPOCH="$(date +%s)"
WORKLOAD_START_ISO="$(date -u -d "@${WORKLOAD_START_EPOCH}" +'%Y-%m-%dT%H:%M:%SZ')"
WORKLOAD_STOP_EPOCH=$((WORKLOAD_START_EPOCH + DURATION))
WORKLOAD_STOP_ISO="$(date -u -d "@${WORKLOAD_STOP_EPOCH}" +'%Y-%m-%dT%H:%M:%SZ')"
log "Effective workload start time: ${WORKLOAD_START_ISO} (epoch: ${WORKLOAD_START_EPOCH})"
log "Effective workload stop time: ${WORKLOAD_STOP_ISO} (epoch: ${WORKLOAD_STOP_EPOCH})"

# If scheduler disabled or operator requested, suppress noisy LINK UP/DOWN logs
if [ "${SCHEDULE_FILE}" = "/dev/null" ] || [ "${SUPPRESS_LINK_LOG:-}" = "1" ]; then
  SUPPRESS_LINK_LOG=1
else
  unset SUPPRESS_LINK_LOG
fi

log "Running test for ${DURATION}s..."
sleep "$DURATION"

log "Test duration elapsed; capturing data BEFORE stopping processes..."

# ================================================
# CRITICAL: Export InfluxDB data BEFORE stopping update_causal_property
# This ensures M2S command counts are captured correctly
# ================================================
BUCKET="${BUCKET:-${INFLUXDB_BUCKET:-${IOT_INFLUX_BUCKET:-iot_data}}}"
OUTFILE="${TEST_DIR}/${PROFILE}_${TEST_TIMESTAMP}.csv"
INFLUX_ORG="${INFLUXDB_ORG:-${INFLUX_ORG:-minha_org}}"
INFLUX_TOKEN="${INFLUXDB_TOKEN:-${INFLUX_TOKEN:-}}"

# Allow overriding the Influx host/port via env vars (INFLUXDB_HOST/INFLUXDB_PORT or INFLUX_HOST/INFLUX_PORT)
INFLUX_HOST="${INFLUXDB_HOST:-${INFLUX_HOST:-mn.influxdb}}"
INFLUX_PORT="${INFLUXDB_PORT:-${INFLUX_PORT:-8086}}"

# Choose curl command (containerized vs host) - check both mn.influx and mn.influxdb
if docker ps --format '{{.Names}}' | grep -q '^mn\.influx$'; then
  CURL_CMD="docker exec mn.influx curl -s"
elif docker ps --format '{{.Names}}' | grep -q '^mn\.influxdb$'; then
  CURL_CMD="docker exec mn.influxdb curl -s"
  INFLUX_HOST="localhost"  # When running inside container, use localhost
else
  CURL_CMD="curl -s"
fi

# Recompute URL after selecting execution context (host vs container)
BASE_INFLUX_URL="http://${INFLUX_HOST}:${INFLUX_PORT}"

if [ -z "$INFLUX_TOKEN" ]; then
  log "INFLUX_TOKEN not set. Cannot export Influx CSV. Skipping export."
else
  log "⚡ PRIORITY EXPORT: Capturing InfluxDB data while update_causal_property is still running..."
  log "🔍 DEBUG: BUCKET=$BUCKET, INFLUX_ORG=$INFLUX_ORG, BASE_INFLUX_URL=$BASE_INFLUX_URL"
  log "🔍 DEBUG: START_ISO=$WORKLOAD_START_ISO, STOP_ISO=$WORKLOAD_STOP_ISO"
  log "🔍 DEBUG: CURL_CMD=$CURL_CMD"
  
  # Export device_data only
  OUTFILE_DEVICE="${TEST_DIR}/${PROFILE}_${TEST_TIMESTAMP}_device_data.csv"
  log "🔍 Executing device_data export to: $OUTFILE_DEVICE"
  if timeout 30 $CURL_CMD --request POST "${BASE_INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
      --header "Authorization: Token ${INFLUX_TOKEN}" \
      --header 'Accept: text/csv' \
      --header 'Content-type: application/vnd.flux' \
      --data "from(bucket: \"${BUCKET}\") |> range(start: time(v: \"${WORKLOAD_START_ISO}\"), stop: time(v: \"${WORKLOAD_STOP_ISO}\")) |> filter(fn: (r) => r._measurement == \"device_data\")" \
      > "$OUTFILE_DEVICE" 2>"${OUTFILE_DEVICE}.err"; then
    log "⚡ Device data export completed -> $OUTFILE_DEVICE"
    log "✅ Device data captured successfully before process shutdown"
  else
    log "❌ Device data export failed"
    [ -s "${OUTFILE_DEVICE}.err" ] && log "❌ Device data stderr: $(tail -1 "${OUTFILE_DEVICE}.err")"
    OUTFILE_DEVICE=""
  fi
  [ -f "${OUTFILE_DEVICE}.err" ] && rm -f "${OUTFILE_DEVICE}.err"
  [ -n "$OUTFILE_DEVICE" ] && [ ! -s "$OUTFILE_DEVICE" ] && { log "❌ Device data export empty"; OUTFILE_DEVICE=""; }

  # Export latency_measurement only (with request_id)
  OUTFILE_LATENCY="${TEST_DIR}/${PROFILE}_${TEST_TIMESTAMP}_latency_measurement.csv"
  log "🔍 Executing latency_measurement export to: $OUTFILE_LATENCY"
  if timeout 30 $CURL_CMD --request POST "${BASE_INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
      --header "Authorization: Token ${INFLUX_TOKEN}" \
      --header 'Accept: text/csv' \
      --header 'Content-type: application/vnd.flux' \
      --data "from(bucket: \"${BUCKET}\") |> range(start: time(v: \"${WORKLOAD_START_ISO}\"), stop: time(v: \"${WORKLOAD_STOP_ISO}\")) |> filter(fn: (r) => r._measurement == \"latency_measurement\")" \
      > "$OUTFILE_LATENCY" 2>"${OUTFILE_LATENCY}.err"; then
    log "⚡ Latency measurement export completed -> $OUTFILE_LATENCY"
    log "✅ Latency measurement data captured successfully before process shutdown"
  else
    log "❌ Latency measurement export failed"
    [ -s "${OUTFILE_LATENCY}.err" ] && log "❌ Latency stderr: $(tail -1 "${OUTFILE_LATENCY}.err")"
    OUTFILE_LATENCY=""
  fi
  [ -f "${OUTFILE_LATENCY}.err" ] && rm -f "${OUTFILE_LATENCY}.err"
  [ -n "$OUTFILE_LATENCY" ] && [ ! -s "$OUTFILE_LATENCY" ] && { log "❌ Latency export empty"; OUTFILE_LATENCY=""; }

  # Set OUTFILE to device_data to prevent secondary export (we have both files now)
  if [ -f "$OUTFILE_DEVICE" ] && [ -f "$OUTFILE_LATENCY" ]; then
    OUTFILE="$OUTFILE_DEVICE"
    SKIP_SECONDARY_EXPORT=1
    log "✅ Both priority exports completed successfully, skipping secondary export"
  fi
fi

# Persist runtime logs before stopping processes so RPC diagnostics survive cleanup.
if [ -n "$MID_CNT" ]; then
  MID_LOG_OUT="${TEST_DIR}/${PROFILE}_middts_update_${TEST_TIMESTAMP}.log"
  docker exec "$MID_CNT" bash -lc "if [ -f /middleware-dt/update_causal_property.out ]; then tail -n 12000 /middleware-dt/update_causal_property.out; fi" > "$MID_LOG_OUT" 2>/dev/null || true
  [ -s "$MID_LOG_OUT" ] && log "📝 Saved middleware RPC runtime log: $MID_LOG_OUT"

  MID_LG_OUT="${TEST_DIR}/${PROFILE}_middts_listen_${TEST_TIMESTAMP}.log"
  docker exec "$MID_CNT" bash -lc "if [ -f /middleware-dt/listen_gateway.out ]; then tail -n 6000 /middleware-dt/listen_gateway.out; fi" > "$MID_LG_OUT" 2>/dev/null || true
  [ -s "$MID_LG_OUT" ] && log "📝 Saved middleware listener log: $MID_LG_OUT"
fi

for simc in $(docker ps --format '{{.Names}}' | grep -E '^mn\.sim_[0-9]+$' || true); do
  [ -z "$simc" ] && continue
  SIM_LOG_OUT="${TEST_DIR}/${PROFILE}_${simc}_telemetry_${TEST_TIMESTAMP}.log"
  docker exec "$simc" bash -lc "if [ -f /iot_simulator/send_telemetry.out ]; then tail -n 8000 /iot_simulator/send_telemetry.out; fi" > "$SIM_LOG_OUT" 2>/dev/null || true
  [ -s "$SIM_LOG_OUT" ] && log "📝 Saved simulator runtime log: $SIM_LOG_OUT"
done

log "Now stopping processes after data capture..."

# stop update_causal_property
if [ -n "$MID_CNT" ]; then
  log "Stopping update_causal_property in $MID_CNT"
  docker exec "$MID_CNT" bash -lc "pkill -f update_causal_property || true; pkill -f manage.py || true; rm -f /tmp/update_causal_property.pid || true" || true
fi

# stop all simulators' send_telemetry and scenario_runner
docker ps --format '{{.Names}}' | grep -E 'sim[_-]?[0-9]+' | while read -r simc; do
  [ -z "$simc" ] && continue
  log "Stopping send_telemetry/scenario_runner on $simc"
  docker exec "$simc" bash -lc "pkill -f send_telemetry || true; pkill -f scenario_runner.py || true; pkill -f python3 manage.py || true; rm -f /tmp/send_telemetry.pid || true" || true
done

# stop scheduler if running
if [ -n "${SCHED_PID:-}" ]; then
  log "Stopping scheduler (PID $SCHED_PID)"
  kill "$SCHED_PID" 2>/dev/null || true
fi
# also check for persisted scheduler pid from previous runs
if [ -f "${SCHED_PID_FILE}" ]; then
  oldpid=$(cat "${SCHED_PID_FILE}" 2>/dev/null || true)
  if [ -n "$oldpid" ] && ps -p "$oldpid" >/dev/null 2>&1; then
    log "Stopping previously persisted scheduler (PID $oldpid)"
    kill "$oldpid" 2>/dev/null || true
  fi
  rm -f "${SCHED_PID_FILE}" 2>/dev/null || true
fi

# Clean up middleware HTTP sessions and connections to prevent accumulation
if [ -n "$MID_CNT" ]; then
  log "Cleaning up middleware URLLC singleton sessions"
  # Use the new singleton session manager cleanup
  docker exec "$MID_CNT" bash -lc "python3 -c \"
import sys
sys.path.append('/middleware-dt')
try:
    from facade.utils import close_all_sessions
    close_all_sessions()
    print('URLLC singleton sessions cleaned successfully')
except Exception as e:
    print(f'Session cleanup error: {e}')
    # Fallback: force garbage collection
    import gc
    gc.collect()
    print('Fallback garbage collection completed')
\"" || true
  
  # Wait a moment for connections to close gracefully
  sleep 2
fi

# ================================================
# Secondary export attempt (only if priority export failed)
# ================================================
if [ -z "${OUTFILE}" ] || [ ! -f "${OUTFILE}" ]; then
  log "Priority export failed or missing - attempting secondary export..."
  BUCKET="${BUCKET:-${INFLUXDB_BUCKET:-${IOT_INFLUX_BUCKET:-iot_data}}}"
  OUTFILE="${TEST_DIR}/${PROFILE}_${TEST_TIMESTAMP}.csv"
  INFLUX_ORG="${INFLUXDB_ORG:-${INFLUX_ORG:-minha_org}}"
  INFLUX_TOKEN="${INFLUXDB_TOKEN:-${INFLUX_TOKEN:-}}"
else
  log "Priority export successful - skipping secondary export"
  # Skip to report generation
  SKIP_SECONDARY_EXPORT=1
fi

# Allow overriding the Influx host/port via env vars (INFLUXDB_HOST/INFLUXDB_PORT or INFLUX_HOST/INFLUX_PORT)
INFLUX_HOST="${INFLUXDB_HOST:-${INFLUX_HOST:-localhost}}"
INFLUX_PORT="${INFLUXDB_PORT:-${INFLUX_PORT:-8086}}"
BASE_INFLUX_URL="http://${INFLUX_HOST}:${INFLUX_PORT}"

# Determine how to invoke curl against the Influx API: try local first, else use a curl container
choose_influx_curl() {
  # prefer host-local curl if it can reach the Influx /health endpoint
  if command -v curl >/dev/null 2>&1 && curl -sS --max-time 3 "${BASE_INFLUX_URL}/health" >/dev/null 2>&1; then
    CURL_CMD_LOCAL="curl --silent --show-error --fail"
    CURL_CMD="${CURL_CMD_LOCAL}"
    log "Using host curl to contact Influx at ${BASE_INFLUX_URL}"
    return 0
  fi

  # fallback: if mn.influxdb container exists, run curl inside a transient container that shares its network
  if docker ps --format '{{.Names}}' | grep -q '^mn.influxdb$$'; then
    CURL_CMD="docker run --rm --network container:mn.influxdb curlimages/curl:8.3.0 -sS"
    # test via docker-run curl
    if $CURL_CMD --max-time 5 "${BASE_INFLUX_URL}/health" >/dev/null 2>&1; then
      log "Using docker-run curl (network container:mn.influxdb) to contact Influx"
      return 0
    fi
  fi

  # final fallback: host curl (may fail)
  CURL_CMD="curl --silent --show-error --fail"
  log "Warning: could not reach Influx via host or docker-run; will attempt host curl which may fail"
  return 1
}

if [ "${SKIP_SECONDARY_EXPORT:-0}" = "1" ]; then
  log "Skipping secondary export - priority export was successful"
else
  choose_influx_curl

  if [ -z "$INFLUX_TOKEN" ]; then
    log "INFLUX_TOKEN not set. Cannot export Influx CSV. Skipping export."
  else
  log "Exporting bucket '$BUCKET' to $OUTFILE (this may take a while)..."
  # Quick pre-check: ask Influx for a single point in the time window. If none, skip export to avoid creating empty CSVs.
  TMP_CHECK_FILE="$(mktemp --tmpdir=/tmp influx_check_XXXX.csv)"
  log "Checking for presence of points in bucket '${BUCKET}' for window ${START_ISO}..${STOP_ISO}"
  # Limit to 1 row to make the check fast. Save output to temporary file and test size.
  if $CURL_CMD --request POST "${BASE_INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
        --header "Authorization: Token ${INFLUX_TOKEN}" \
        --header 'Accept: text/csv' \
        --header 'Content-type: application/vnd.flux' \
        --data "from(bucket: \"${BUCKET}\") |> range(start: time(v: \"${START_ISO}\"), stop: time(v: \"${STOP_ISO}\")) |> limit(n:1)" -o "$TMP_CHECK_FILE" 2>/dev/null; then
    # If the response file is very small (only CRLF/header), treat as empty
    if [ ! -s "$TMP_CHECK_FILE" ] || [ "$(wc -c < "$TMP_CHECK_FILE")" -le 2 ]; then
      log "No points found in Influx for the requested window; skipping export and offline report generation. (checked ${TMP_CHECK_FILE})"
      rm -f "$TMP_CHECK_FILE" || true
      OUTFILE=""
      # Skip the rest of the export logic by jumping to after the export block
      SKIP_INFLUX_EXPORT=1
    else
      rm -f "$TMP_CHECK_FILE" || true
      SKIP_INFLUX_EXPORT=0
    fi
  else
    log "Warning: pre-export check against Influx failed (network or auth); continuing with export attempt"
    rm -f "$TMP_CHECK_FILE" || true
    SKIP_INFLUX_EXPORT=0
  fi
  # Create a scenario-specific bucket (name: <bucket>_<profile>_<start>) and copy the range into it via a Flux to() call
  SCENARIO_BUCKET="${BUCKET}_${PROFILE}_$(date -u +'%Y%m%dT%H%M%SZ')"
  log "Attempting to create Influx bucket: $SCENARIO_BUCKET"
  # Create bucket via API (best-effort). Requires INFLUX_ORG and admin token
  # Get org ID
  ORG_ID="$($CURL_CMD -G "${BASE_INFLUX_URL}/api/v2/orgs?org=${INFLUX_ORG}" --header "Authorization: Token ${INFLUX_TOKEN}" 2>/dev/null | sed -n 's/.*"id":"\([a-f0-9-]*\)".*/\1/p' || true)"
  if [ -n "$ORG_ID" ]; then
    $CURL_CMD -X POST "${BASE_INFLUX_URL}/api/v2/buckets" \
      --header "Authorization: Token ${INFLUX_TOKEN}" \
      --header 'Content-type: application/json' \
      --data "{\"orgID\": \"${ORG_ID}\", \"name\": \"${SCENARIO_BUCKET}\", \"retentionRules\": [] }" \
      && log "Bucket ${SCENARIO_BUCKET} created (or already existed)" || log "Bucket creation failed (continuing)"
  else
    log "Could not determine org ID for ${INFLUX_ORG}; skipping bucket creation"
  fi

  # Try a server-side copy using Flux to() (copy the test time window)
  RANGE_FLUX="from(bucket: \"${BUCKET}\") |> range(start: time(v: \"${START_ISO}\"), stop: time(v: \"${STOP_ISO}\")) |> to(bucket: \"${SCENARIO_BUCKET}\")"
  log "Attempting server-side copy of test window into ${SCENARIO_BUCKET}"
  if [ "${SKIP_INFLUX_EXPORT:-0}" = "1" ]; then
    log "Skipping server-side copy because pre-check decided there are no points in the time window"
  elif $CURL_CMD --request POST "${BASE_INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
    --header "Authorization: Token ${INFLUX_TOKEN}" \
    --header 'Content-type: application/vnd.flux' \
    --data "$RANGE_FLUX" > /dev/null 2>&1; then
    log "Server-side copy initiated to ${SCENARIO_BUCKET}"
    # Export the new bucket to CSV
    OUTFILE="${RESULTS_DIR}/${SCENARIO_BUCKET}.csv"
    $CURL_CMD --request POST "${BASE_INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
      --header "Authorization: Token ${INFLUX_TOKEN}" \
      --header 'Accept: text/csv' \
      --header 'Content-type: application/vnd.flux' \
      --data "from(bucket: \"${SCENARIO_BUCKET}\") |> range(start: 0)" -o "$OUTFILE" \
      && log "Export completed -> $OUTFILE" || log "Export failed"
  else
    log "Server-side copy failed; falling back to exporting full original bucket"
    if [ "${SKIP_INFLUX_EXPORT:-0}" = "1" ]; then
      log "Skipping fallback export because pre-check decided there are no points in the time window"
      OUTFILE=""
    else
      $CURL_CMD --request POST "${BASE_INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
        --header "Authorization: Token ${INFLUX_TOKEN}" \
        --header 'Accept: text/csv' \
        --header 'Content-type: application/vnd.flux' \
        --data "from(bucket: \"${BUCKET}\") |> range(start: time(v: \"${START_ISO}\"), stop: time(v: \"${STOP_ISO}\")) |> filter(fn: (r) => r._measurement == \"device_data\" or r._measurement == \"latency_measurement\")" -o "$OUTFILE" \
        && log "Export completed -> $OUTFILE" || log "Export failed"
    fi
  fi
  fi  # End of secondary export block
fi  # End of SKIP_SECONDARY_EXPORT check

# run flux reports in services/middleware-dt/docs replacing time window
REPORTS_DIR="services/middleware-dt/docs"
STOP_EPOCH=$((START_EPOCH + DURATION))
STOP_ISO="$(date -u -d "@${STOP_EPOCH}" +'%Y-%m-%dT%H:%M:%SZ')"

## We no longer call the Influx HTTP API to generate Flux reports.
## Instead we rely on the exported CSV (OUTFILE) and run the offline generator
## which parses the CSV and produces the ODTE and latency CSVs.
mkdir -p "${TEST_DIR}/generated_reports"
if [ -f "${OUTFILE}" ]; then
  log "Generating reports from CSV export: ${OUTFILE} -> ${TEST_DIR}/generated_reports"
  # prefer the local venv/python if present; otherwise use system python3
  PYTHON=${PYTHON:-python3}
  "$PYTHON" "${PWD}/scripts/reports/report_generators/generate_reports_from_export.py" "${OUTFILE}" "${PROFILE}" "${TEST_DIR}/generated_reports" || log "Offline report generation failed"
else
  log "No export CSV found (${OUTFILE}); skipping offline report generation"
fi

# summary
SUMMARY="${TEST_DIR}/summary_${PROFILE}_${TEST_TIMESTAMP}.txt"
{
  echo "profile: $PROFILE"
  echo "start: ${WORKLOAD_START_ISO:-$START_ISO}"
  echo "duration_seconds: $DURATION"
  # Ensure any legacy prefix 'results/' is canonicalized to the configured RESULTS_DIR
  if [ -n "${OUTFILE:-}" ]; then
    CANON_OUTFILE="${OUTFILE/#results\//${RESULTS_DIR}/}"
  else
    CANON_OUTFILE=""
  fi
  echo "bucket_export: ${CANON_OUTFILE:-skipped}"
  # Canonicalize reports_dir if it uses legacy 'results/' prefix
  CANON_REPORTS_DIR="${TEST_DIR/#results\//${RESULTS_DIR}/}"
  echo "reports_dir: ${CANON_REPORTS_DIR}"
  echo "note: check logs for screen session: screen -r ${TOPO_SCREEN}"
} > "$SUMMARY"

log "Cenario test finished. Summary -> $SUMMARY"

# Post-process: locate a non-empty ODTE report CSV (prefer any non-empty file; accept .csv.bak too)
ODTE_CSV=""
# enable nullglob in bash if available so the for-loop skips when no matches
if command -v bash >/dev/null 2>&1; then
  # shellcheck disable=SC2034
  shopt -s nullglob 2>/dev/null || true
fi
for f in "${TEST_DIR}/generated_reports/${PROFILE}_odte_"*; do
  if [ -f "$f" ] && [ -s "$f" ]; then
    ODTE_CSV="$f"
    break
  fi
done
if [ -z "$ODTE_CSV" ]; then
  # fallback to any matching csv (may be empty)
  ODTE_CSV="$(ls -1 ${TEST_DIR}/generated_reports/${PROFILE}_odte_*.csv 2>/dev/null | tail -n1 || true)"
fi
if [ -n "$ODTE_CSV" ]; then
  log "Found ODTE CSV: $ODTE_CSV. Computing mean T/R/A..."
  # CSV from Influx may include columns: _time,_value,_field,... or named columns depending on report.
  # We'll try to extract columns labelled 'T','R','A' or 'ODTE' and compute their means.
  # Convert CSV to simple comma-separated rows ignoring the Influx prefix columns
  # Try to find header line
  header=$(head -n1 "$ODTE_CSV" 2>/dev/null || true)
  # normalize header to lowercase
  low_header=$(echo "$header" | tr '[:upper:]' '[:lower:]')
  mean_T=0; mean_R=0; mean_A=0; count=0
  # detect T/R/A-like columns (t, t_m2s, r_s2m, a, a_...) and average them
  if echo "$low_header" | grep -qiE '(^|,)t($|_|,)' ; then
    mean_T=$(awk -F"," 'NR==1{for(i=1;i<=NF;i++){h=tolower($i); if(h=="t" || h ~ /^t($|_)/) c=i}} NR>1 && c{if($c!="" && $c!="na") {s+=$c; n++}} END{if(n>0) print s/n; else print 0}' "$ODTE_CSV" )
  fi
  if echo "$low_header" | grep -qiE '(^|,)r($|_|,)' ; then
    mean_R=$(awk -F"," 'NR==1{for(i=1;i<=NF;i++){h=tolower($i); if(h=="r" || h ~ /^r($|_)/) c=i}} NR>1 && c{if($c!="" && $c!="na") {s+=$c; n++}} END{if(n>0) print s/n; else print 0}' "$ODTE_CSV" )
  fi
  if echo "$low_header" | grep -qiE '(^|,)a($|_|,)' ; then
    mean_A=$(awk -F"," 'NR==1{for(i=1;i<=NF;i++){h=tolower($i); if(h=="a" || h ~ /^a($|_)/) c=i}} NR>1 && c{if($c!="" && $c!="na") {s+=$c; n++}} END{if(n>0) print s/n; else print 0}' "$ODTE_CSV" )
  fi
  # Fallback: if T/R/A not present, but ODTE present, we cannot separate components. write ODTE mean instead.
  if [ "$mean_T" = "0" ] && [ "$mean_R" = "0" ] && [ "$mean_A" = "0" ]; then
    if echo "$low_header" | grep -q 'odte'; then
      mean_odte=$(awk -F"," 'NR==1{for(i=1;i<=NF;i++){if(tolower($i)=="odte") c=i}} NR>1 && c{if($c!="" && $c!="na") {s+=$c; n++}} END{if(n>0) print s/n; else print 0}' "$ODTE_CSV" )
      echo "mean_ODTE: $mean_odte" >> "$SUMMARY"
    fi
  else
    # Defer writing mean_T/mean_R/mean_A to the Python helper which will
    # compute richer statistics (means, medians) and append them to the
    # summary in a consistent format.
    log "ODTE components computed (deferred writing to metrics helper)"
  fi
else
  log "No ODTE CSV found (${TEST_DIR}/generated_reports/${PROFILE}_odte_*.csv) — skipping T/R/A summary"
fi

log "You can review results in $TEST_DIR"

# Compute latency metrics from device_data and latency_measurement CSVs
if [ -n "$OUTFILE_DEVICE" ] && [ -f "$OUTFILE_DEVICE" ] && [ -n "$OUTFILE_LATENCY" ] && [ -f "$OUTFILE_LATENCY" ]; then
  log "🔍 Analyzing S2M/M2S latencies from exported CSVs..."
  
  # Merge device_data and latency_measurement CSVs into a single analysis file
  MERGED_CSV="${TEST_DIR}/analysis_merged.csv"
  {
    head -1 "$OUTFILE_DEVICE"
    tail -n +2 "$OUTFILE_DEVICE"
    tail -n +2 "$OUTFILE_LATENCY" 2>/dev/null || true
  } > "$MERGED_CSV"
  
  if command -v python3 >/dev/null 2>&1; then
    PYTHON=${PYTHON:-python3}
    LATENCY_REPORT="${TEST_DIR}/latency_analysis.txt"
    log "Running latency analysis on merged CSV..."
    "$PYTHON" "${PWD}/analyze_latencies.py" "$MERGED_CSV" > "$LATENCY_REPORT" 2>&1 && \
      log "✅ Latency analysis complete (see ${LATENCY_REPORT})" || \
      log "⚠️  Latency analysis failed (non-fatal)"

    # NEW: authoritative end-to-end analysis by correlation_id (what was previously run manually)
    CORRELATION_REPORT="${TEST_DIR}/latency_analysis_correlation.txt"
    log "Running end-to-end correlation analysis..."
    "$PYTHON" "${PWD}/analyze_latencies.py" "$OUTFILE_LATENCY" --by-correlation-id > "$CORRELATION_REPORT" 2>&1 && {
      log "✅ Correlation analysis complete (see ${CORRELATION_REPORT})"
      {
        echo ""
        echo "# Correlation-ID End-to-End Analysis"
        cat "$CORRELATION_REPORT"
      } >> "$SUMMARY"
    } || log "⚠️  Correlation analysis failed (non-fatal)"
  fi
fi

# Compute extended run metrics (means, medians, counts, P95, cdf<=200) and
# append them to the summary. This helper reads files under generated_reports.
if [ -d "${TEST_DIR}/generated_reports" ]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON=${PYTHON:-python3}
    METRICS_LOG="${TEST_DIR}/computed_run_metrics.log"
    "$PYTHON" "${PWD}/scripts/reports/report_generators/_compute_run_metrics.py" \
      --reports-dir "${TEST_DIR}/generated_reports" \
      --profile "${PROFILE}" \
      --odte "${ODTE_CSV}" \
      --device-csv "${OUTFILE_DEVICE:-}" \
      --latency-csv "${OUTFILE_LATENCY:-}" \
      --summary "${SUMMARY}" > "$METRICS_LOG" 2>&1 || log "Run metrics computation failed (see $METRICS_LOG)"
  else
    log "python3 not available; skipping extended run metrics computation"
  fi
else
  log "No generated_reports directory (${TEST_DIR}/generated_reports); skipping extended metrics"
fi
# Override S2M metrics with correct values from analyze_latencies.py output
# Using Python script to reliably parse and update metrics
LATENCY_REPORT="${TEST_DIR}/latency_analysis.txt"
if [ -f "$LATENCY_REPORT" ] && [ -f "$SUMMARY" ]; then
  if command -v python3 >/dev/null 2>&1; then
    CORRELATION_REPORT="${TEST_DIR}/latency_analysis_correlation.txt"
    if grep -q "📊 S2M Latencies" "$LATENCY_REPORT" || [ -f "$CORRELATION_REPORT" ]; then
      log "Fixing summary latency metrics using analyze_latencies outputs..."
      python3 "${PWD}/scripts/fix_summary_s2m_metrics.py" "$SUMMARY" "$LATENCY_REPORT" > "${TEST_DIR}/fix_summary_s2m.log" 2>&1 || true
    else
      log "Skipping summary fix: no S2M section and no correlation report"
    fi
  fi
fi

# Analyze results with link event separation (baseline vs resilience)
if command -v python3 >/dev/null 2>&1; then
  ANALYSIS_SCRIPT="${PWD}/scripts/analyze_results.py"
  if [ -f "$ANALYSIS_SCRIPT" ]; then
    log "Running results analysis with link separation..."
    python3 "$ANALYSIS_SCRIPT" "$TEST_DIR" > "${TEST_DIR}/analyze_results.log" 2>&1 || log "⚠️  Results analysis failed (see ${TEST_DIR}/analyze_results.log)"
  else
    log "⚠️  scripts/analyze_results.py not found, skipping link separation analysis"
  fi
else
  log "python3 not available; skipping results analysis"
fi
