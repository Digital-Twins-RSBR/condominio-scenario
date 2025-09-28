#!/usr/bin/env bash
set -euo pipefail

# scripts/apply_slice.sh (renamed from cenario_test.sh)
# Orquestra aplicação de slice (profile) na topologia e opcionalmente executa o cenário

# Usage/help header
usage() {
  cat <<EOF
Usage: $0 [--apply-only] PROFILE [EXECUTE_TEST_SCENARIO] [DURATION]
  Or:   $0 [--apply-only] PROFILE [--execute-scenario SECONDS]

Options:
  --apply-only           Apply the profile to running topology and exit.
  PROFILE                Topology profile name (urllc, best_effort, eMBB). Default: best_effort
  EXECUTE_TEST_SCENARIO  Positional: 0 (default) to not execute scenario, 1 to execute.
  --execute-scenario N   Long form: run the scenario for N seconds (sets EXECUTE_TEST_SCENARIO=1 and DURATION=N).
  DURATION               Positional 3: duration in seconds when using positional EXECUTE_TEST_SCENARIO. Default: 1800
EOF
}

# Defaults
PROFILE="${1:-best_effort}"
EXECUTE_TEST_SCENARIO=0
DURATION="1800"

# Build ARGS array starting after PROFILE (we may have already shifted --apply-only earlier)
ARGS=("${@:2}")
i=0
while [ $i -lt ${#ARGS[@]} ]; do
  a="${ARGS[$i]}"
  case "$a" in
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
      # positional-like argument: can be EXECUTE_TEST_SCENARIO (0/1/true/false) or a numeric duration
      if echo "$a" | grep -Eq '^[0-9]+$'; then
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

RESULTS_DIR="results"
TOPO_SCREEN="topo"
TOPO_MAKE_TARGET="topo"
MAKE_CMD="make"

# marker to remember last applied profile (to avoid re-applying)
PROFILE_MARKER=".current_slice_profile"

# load .env if present
if [ -f .env ]; then
  # shellcheck disable=SC1091
  . .env
fi

mkdir -p "$RESULTS_DIR"

log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }

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
      BW=500; DELAY="10ms"; LOSS=0.1
      ;;
    *)
      BW=200; DELAY="50ms"; LOSS=0.5
      ;;
  esac
  # iterate mn.* containers and apply tc on eth0 where present
  docker ps --format '{{.Names}}' | grep '^mn\.' | while read -r cname; do
    [ -z "$cname" ] && continue
    # skip core services: do not shape influx/thingsboard/middts/neo4j containers
    case "$cname" in
      *influx*|*tb*|*thingsboard*|*middts*|*middleware*|*neo4j*|*parser*)
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
  log "Screen session '${TOPO_SCREEN}' started. Waiting briefly for containers to come up and applying profile."
  # wait a short while for topology containers to spawn, then apply profile
  sleep 5
  apply_topo_profile "$PROFILE"
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
  log "Timed out waiting for services to appear. Continuing anyway."
fi

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
    else
      log "Cannot bring down link for $c: no eth0"
    fi
  done
}

apply_link_up() {
  local target="$1"
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
  log "Builtin scheduler started (PID $SCHED_PID)"
}

# start update_causal_property inside middts container
MID_CNT="$(find_container 'middts\|middleware')"
start_middts_update() {
  MID_CNT="$1"
  if [ -n "$MID_CNT" ]; then
    log "Starting update_causal_property in container: $MID_CNT"
    # Source middts .env inside the container so INFLUX/NEO4J vars are available
    docker exec -d "$MID_CNT" bash -lc "if [ -f /middleware-dt/.env ]; then set -a; . /middleware-dt/.env; set +a; fi; cd /var/condominio-scenario/services/middleware-dt || true; nohup python3 manage.py update_causal_property > /middleware-dt/update_causal_property.out 2>&1 & echo \$! >/tmp/update_causal_property.pid" || log "Failed to exec update_causal_property (non-fatal)"
    # brief check
    sleep 1
    if docker exec "$MID_CNT" bash -lc "ps -ef | grep -v grep | grep update_causal_property >/dev/null 2>&1"; then
      log "update_causal_property appears to be running in $MID_CNT"
    else
      log "Warning: update_causal_property does not appear to be running in $MID_CNT"
      # capture a short tail of the updater output if present for diagnosis
      docker exec "$MID_CNT" bash -lc "if [ -f /middleware-dt/update_causal_property.out ]; then tail -n 200 /middleware-dt/update_causal_property.out; fi" > "${RESULTS_DIR}/${PROFILE}_middts_update_tail_$(date -u +'%Y%m%dT%H%M%SZ').log" 2>/dev/null || true
    fi
  else
    log "middts container not found, skipping update_causal_property start."
  fi
}

# start scheduler (scheduler is independent of scenario_runner)
# Start simulators' send_telemetry if not already running (helps when topology doesn't auto-start them)
start_simulators() {
  for s in $(docker ps --format '{{.Names}}' | grep -E 'sim[_-]?[0-9]+' || true); do
    [ -z "$s" ] && continue
    # check if send_telemetry is running
    if docker exec "$s" bash -lc "ps -eo cmd | grep -E 'manage.py send_telemetry' | grep -v grep >/dev/null 2>&1"; then
      log "send_telemetry already running in $s"
    else
      log "Starting send_telemetry in $s"
  # start with --randomize to vary sensor timestamps and avoid deterministic collisions
  # Ensure .env exists inside the container (copy from .env.example if present)
  docker exec "$s" bash -lc "if [ ! -f /iot_simulator/.env ] && [ -f /iot_simulator/.env.example ]; then echo '[auto] copying .env.example -> .env inside container'; cp /iot_simulator/.env.example /iot_simulator/.env; fi" >/dev/null 2>&1 || true
  # Source the container's .env so THINGSBOARD_* and INFLUX_* are available to the process
  docker exec -d "$s" bash -lc "if [ -f /iot_simulator/.env ]; then set -a; . /iot_simulator/.env; set +a; fi; cd /iot_simulator || true; nohup python3 manage.py send_telemetry --use-influxdb --randomize > /iot_simulator/send_telemetry.out 2>&1 & echo \$! >/tmp/send_telemetry.pid" || log "Failed to start send_telemetry in $s"
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

# If scheduler disabled or operator requested, suppress noisy LINK UP/DOWN logs
if [ "${SCHEDULE_FILE}" = "/dev/null" ] || [ "${SUPPRESS_LINK_LOG:-}" = "1" ]; then
  SUPPRESS_LINK_LOG=1
else
  unset SUPPRESS_LINK_LOG
fi

log "Running test for ${DURATION}s..."
sleep "$DURATION"

log "Test duration elapsed; performing shutdown actions..."

# stop update_causal_property
if [ -n "$MID_CNT" ]; then
  log "Stopping update_causal_property in $MID_CNT"
  docker exec "$MID_CNT" bash -lc "pkill -f update_causal_property || true; pkill -f manage.py || true" || true
fi

# stop all simulators' send_telemetry and scenario_runner
docker ps --format '{{.Names}}' | grep -E 'sim[_-]?[0-9]+' | while read -r simc; do
  [ -z "$simc" ] && continue
  log "Stopping send_telemetry/scenario_runner on $simc"
  docker exec "$simc" bash -lc "pkill -f send_telemetry || true; pkill -f scenario_runner.py || true; pkill -f python3 manage.py || true" || true
done

# stop scheduler if running
if [ -n "${SCHED_PID:-}" ]; then
  log "Stopping scheduler (PID $SCHED_PID)"
  kill "$SCHED_PID" 2>/dev/null || true
fi

# export bucket to CSV
BUCKET="${BUCKET:-${INFLUXDB_BUCKET:-${IOT_INFLUX_BUCKET:-iot_data}}}"
OUTFILE="${RESULTS_DIR}/${PROFILE}_$(date -u +'%Y%m%dT%H%M%SZ').csv"
INFLUX_ORG="${INFLUXDB_ORG:-${INFLUX_ORG:-minha_org}}"
INFLUX_TOKEN="${INFLUXDB_TOKEN:-${INFLUX_TOKEN:-}}"

# Allow overriding the Influx host/port via env vars (INFLUXDB_HOST/INFLUXDB_PORT or INFLUX_HOST/INFLUX_PORT)
INFLUX_HOST="${INFLUXDB_HOST:-${INFLUX_HOST:-localhost}}"
INFLUX_PORT="${INFLUXDB_PORT:-${INFLUX_PORT:-8086}}"
BASE_INFLUX_URL="http://${INFLUX_HOST}:${INFLUX_PORT}"

if [ -z "$INFLUX_TOKEN" ]; then
  log "INFLUX_TOKEN not set. Cannot export Influx CSV. Skipping export."
else
  log "Exporting bucket '$BUCKET' to $OUTFILE (this may take a while)..."
  # Create a scenario-specific bucket (name: <bucket>_<profile>_<start>) and copy the range into it via a Flux to() call
  SCENARIO_BUCKET="${BUCKET}_${PROFILE}_$(date -u +'%Y%m%dT%H%M%SZ')"
  log "Attempting to create Influx bucket: $SCENARIO_BUCKET"
  # Create bucket via API (best-effort). Requires INFLUX_ORG and admin token
  # Get org ID
  ORG_ID="$(curl --silent --show-error --fail -G "${BASE_INFLUX_URL}/api/v2/orgs?org=${INFLUX_ORG}" --header "Authorization: Token ${INFLUX_TOKEN}" | sed -n 's/.*"id":"\([a-f0-9-]*\)".*/\1/p' || true)"
  if [ -n "$ORG_ID" ]; then
    curl --silent --show-error --fail -X POST "${BASE_INFLUX_URL}/api/v2/buckets" \
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
  if curl --silent --show-error --fail --request POST "${BASE_INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
      --header "Authorization: Token ${INFLUX_TOKEN}" \
      --header 'Content-type: application/vnd.flux' \
      --data "$RANGE_FLUX" > /dev/null 2>&1; then
    log "Server-side copy initiated to ${SCENARIO_BUCKET}"
    # Export the new bucket to CSV
    OUTFILE="${RESULTS_DIR}/${SCENARIO_BUCKET}.csv"
    curl --silent --show-error --fail --request POST "${BASE_INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
      --header "Authorization: Token ${INFLUX_TOKEN}" \
      --header 'Accept: text/csv' \
      --header 'Content-type: application/vnd.flux' \
      --data "from(bucket: \"${SCENARIO_BUCKET}\") |> range(start: 0)" -o "$OUTFILE" \
      && log "Export completed -> $OUTFILE" || log "Export failed"
  else
    log "Server-side copy failed; falling back to exporting full original bucket"
    curl --silent --show-error --fail --request POST "${BASE_INFLUX_URL}/api/v2/query?org=${INFLUX_ORG}" \
      --header "Authorization: Token ${INFLUX_TOKEN}" \
      --header 'Accept: text/csv' \
      --header 'Content-type: application/vnd.flux' \
      --data "from(bucket: \"${BUCKET}\") |> range(start: time(v: \"${START_ISO}\"), stop: time(v: \"${STOP_ISO}\"))" -o "$OUTFILE" \
      && log "Export completed -> $OUTFILE" || log "Export failed"
  fi
fi

# run flux reports in services/middleware-dt/docs replacing time window
REPORTS_DIR="services/middleware-dt/docs"
STOP_EPOCH=$((START_EPOCH + DURATION))
STOP_ISO="$(date -u -d "@${STOP_EPOCH}" +'%Y-%m-%dT%H:%M:%SZ')"

## We no longer call the Influx HTTP API to generate Flux reports.
## Instead we rely on the exported CSV (OUTFILE) and run the offline generator
## which parses the CSV and produces the ODTE and latency CSVs.
mkdir -p "${RESULTS_DIR}/generated_reports"
if [ -f "${OUTFILE}" ]; then
  log "Generating reports from CSV export: ${OUTFILE} -> ${RESULTS_DIR}/generated_reports"
  # prefer the local venv/python if present; otherwise use system python3
  PYTHON=${PYTHON:-python3}
  "$PYTHON" "${PWD}/scripts/report_generators/generate_reports_from_export.py" "${OUTFILE}" "${PROFILE}" "${RESULTS_DIR}/generated_reports" || log "Offline report generation failed"
else
  log "No export CSV found (${OUTFILE}); skipping offline report generation"
fi

# summary
SUMMARY="${RESULTS_DIR}/summary_${PROFILE}_$(date -u +'%Y%m%dT%H%M%SZ').txt"
{
  echo "profile: $PROFILE"
  echo "start: $START_ISO"
  echo "duration_seconds: $DURATION"
  echo "bucket_export: ${OUTFILE:-skipped}"
  echo "reports_dir: ${RESULTS_DIR}"
  echo "note: check logs for screen session: screen -r ${TOPO_SCREEN}"
} > "$SUMMARY"

log "Cenario test finished. Summary -> $SUMMARY"

# Post-process: locate ODTE report CSV and compute mean T, R, A per-sensor
ODTE_CSV="$(ls -1 ${RESULTS_DIR}/${PROFILE}_odte_*.csv 2>/dev/null | tail -n1 || true)"
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
  if echo "$low_header" | grep -q 't,' || echo "$low_header" | grep -q ',t,'; then
    # header contains T column
    # awk to average column named T (case-insensitive)
    mean_T=$(awk -F"," 'NR==1{for(i=1;i<=NF;i++){h=tolower($i); if(h=="t") c=i}} NR>1 && c{if($c!="" && $c!="na") {s+=$c; n++}} END{if(n>0) print s/n; else print 0}' "$ODTE_CSV" )
  fi
  if echo "$low_header" | grep -q 'r,' || echo "$low_header" | grep -q ',r,'; then
    mean_R=$(awk -F"," 'NR==1{for(i=1;i<=NF;i++){h=tolower($i); if(h=="r") c=i}} NR>1 && c{if($c!="" && $c!="na") {s+=$c; n++}} END{if(n>0) print s/n; else print 0}' "$ODTE_CSV" )
  fi
  if echo "$low_header" | grep -q 'a,' || echo "$low_header" | grep -q ',a,'; then
    mean_A=$(awk -F"," 'NR==1{for(i=1;i<=NF;i++){h=tolower($i); if(h=="a") c=i}} NR>1 && c{if($c!="" && $c!="na") {s+=$c; n++}} END{if(n>0) print s/n; else print 0}' "$ODTE_CSV" )
  fi
  # Fallback: if T/R/A not present, but ODTE present, we cannot separate components. write ODTE mean instead.
  if [ "$mean_T" = "0" ] && [ "$mean_R" = "0" ] && [ "$mean_A" = "0" ]; then
    if echo "$low_header" | grep -q 'odte'; then
      mean_odte=$(awk -F"," 'NR==1{for(i=1;i<=NF;i++){if(tolower($i)=="odte") c=i}} NR>1 && c{if($c!="" && $c!="na") {s+=$c; n++}} END{if(n>0) print s/n; else print 0}' "$ODTE_CSV" )
      echo "mean_ODTE: $mean_odte" >> "$SUMMARY"
    fi
  else
    echo "mean_T: $mean_T" >> "$SUMMARY"
    echo "mean_R: $mean_R" >> "$SUMMARY"
    echo "mean_A: $mean_A" >> "$SUMMARY"
  fi
else
  log "No ODTE CSV found (${RESULTS_DIR}/${PROFILE}_odte_*.csv) — skipping T/R/A summary"
fi

log "You can review results in $RESULTS_DIR"
