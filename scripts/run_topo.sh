#!/bin/sh
# Helper to run the topology with environment handling.
# Expects to be run from repo root.
# Usage: run_topo.sh [PROFILE] [DURATION]
set -eu
# Optional first positional argument is PROFILE (overrides .env)
PROFILE_ARG="${1:-}"
DURATION_ARG="${2:-}"

if [ -n "$PROFILE_ARG" ]; then
  export TOPO_PROFILE="$PROFILE_ARG"
fi
# Default profile to 'urllc' when not provided
if [ -z "${TOPO_PROFILE-}" ]; then
  TOPO_PROFILE="urllc"
  export TOPO_PROFILE
fi

# Set duration if provided
if [ -n "$DURATION_ARG" ]; then
  export TOPO_DURATION="$DURATION_ARG"
fi

# determine repo root (parent of scripts)
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM_ENV="$REPO_ROOT/.env"
if [ ! -f "$SIM_ENV" ]; then SIM_ENV="$REPO_ROOT/services/middleware-dt/.env"; fi
if [ -f "$SIM_ENV" ]; then . "$SIM_ENV"; fi
SIMS="${SIMULATOR_COUNT:-1}"
echo "[📡] Running topology with SIMULATOR_COUNT=$SIMS (from $SIM_ENV if present)"

# Prepare duration argument if set
DURATION_ARG_FLAG=""
if [ -n "${TOPO_DURATION:-}" ]; then
  DURATION_ARG_FLAG="--duration ${TOPO_DURATION}"
  echo "[⏱️] Topology duration: ${TOPO_DURATION}s"
fi

if [ -z "${VERBOSE-}" ]; then
  echo "[INFO] Executando topologia (quiet). Use VERBOSE=1 make topo for detailed logs"
  if [ -z "${PRESERVE_STATE-}" ]; then PRESERVE_STATE=1; fi
  export PRESERVE_STATE
  . services/containernet/venv/bin/activate
  sudo -n -E env PATH="$PATH" PRESERVE_STATE="$PRESERVE_STATE" python3 services/topology/topo_qos.py --sims "$SIMS" --quiet --profile "$TOPO_PROFILE" $DURATION_ARG_FLAG
else
  echo "[INFO] Executando topologia (verbose)"
  if [ -z "${PRESERVE_STATE-}" ]; then PRESERVE_STATE=1; fi
  export PRESERVE_STATE
  . services/containernet/venv/bin/activate
  sudo -n -E env PATH="$PATH" PRESERVE_STATE="$PRESERVE_STATE" python3 services/topology/topo_qos.py --sims "$SIMS" --verbose --profile "$TOPO_PROFILE" $DURATION_ARG_FLAG
fi
