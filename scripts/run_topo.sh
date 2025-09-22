#!/bin/sh
# Helper to run the topology with environment handling.
# Expects to be run from repo root.
set -eu
# Optional first positional argument is PROFILE (overrides .env)
PROFILE_ARG="$1"
if [ -n "$PROFILE_ARG" ]; then
  export TOPO_PROFILE="$PROFILE_ARG"
fi
# determine repo root (parent of scripts)
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM_ENV="$REPO_ROOT/.env"
if [ ! -f "$SIM_ENV" ]; then SIM_ENV="$REPO_ROOT/services/middleware-dt/.env"; fi
if [ -f "$SIM_ENV" ]; then . "$SIM_ENV"; fi
SIMS="${SIMULATOR_COUNT:-1}"
echo "[📡] Running topology with SIMULATOR_COUNT=$SIMS (from $SIM_ENV if present)"
if [ -z "${VERBOSE-}" ]; then
  echo "[INFO] Executando topologia (quiet). Use VERBOSE=1 make topo for detailed logs"
  if [ -z "${PRESERVE_STATE-}" ]; then PRESERVE_STATE=1; fi
  export PRESERVE_STATE
  . services/containernet/venv/bin/activate
  if [ -n "${TOPO_PROFILE-}" ]; then
    sudo -E env PATH="$PATH" PRESERVE_STATE="$PRESERVE_STATE" python3 services/topology/topo_qos.py --sims "$SIMS" --quiet --profile "$TOPO_PROFILE"
  else
    sudo -E env PATH="$PATH" PRESERVE_STATE="$PRESERVE_STATE" python3 services/topology/topo_qos.py --sims "$SIMS" --quiet
  fi
else
  echo "[INFO] Executando topologia (verbose)"
  if [ -z "${PRESERVE_STATE-}" ]; then PRESERVE_STATE=1; fi
  export PRESERVE_STATE
  . services/containernet/venv/bin/activate
  if [ -n "${TOPO_PROFILE-}" ]; then
    sudo -E env PATH="$PATH" PRESERVE_STATE="$PRESERVE_STATE" python3 services/topology/topo_qos.py --sims "$SIMS" --verbose --profile "$TOPO_PROFILE"
  else
    sudo -E env PATH="$PATH" PRESERVE_STATE="$PRESERVE_STATE" python3 services/topology/topo_qos.py --sims "$SIMS" --verbose
  fi
fi
