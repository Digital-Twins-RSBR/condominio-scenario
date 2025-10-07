#!/bin/sh
# Generate all plots (PNG-only). Intended to be run from repo root.
set -eu
ROOT=$(dirname "$0")/..
cd "$ROOT"
PYTHON=${PYTHON:-python3}

echo "Generating reviewer figures..."
$PYTHON scripts/plots/plot_reviewer_figures.py

echo "Generating compare profiles..."
$PYTHON scripts/plots/plot_compare_profiles.py

# If there's a topology visualizer wrapper, run it (safe to run again)
if [ -x scripts/generate_topology_diagram.sh ]; then
  echo "Generating topology diagram via wrapper..."
  scripts/generate_topology_diagram.sh || true
fi

echo "All plots generated under article/plots"
