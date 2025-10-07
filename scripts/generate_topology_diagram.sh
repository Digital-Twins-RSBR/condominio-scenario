#!/bin/sh
# Wrapper to run the topology visualizer and copy PNG outputs into article/plots
set -eu
ROOT=$(dirname "$0")/..
cd "$ROOT"
PYTHON=${PYTHON:-python3}
OUT_DIR="$ROOT/topology_output"
PLOTS_DIR="$ROOT/article/plots"
mkdir -p "$PLOTS_DIR"

# Run visualizer with a sensible default of 6 sims
$PYTHON services/topology/topology_visualizer.py --sims 6 --output "$OUT_DIR" --filename condominio_topology || true

# Copy main outputs if present
if [ -f "$OUT_DIR/condominio_topology_main.png" ]; then
  cp "$OUT_DIR/condominio_topology_main.png" "$PLOTS_DIR/fig5_topology_diagram.png" || true
fi
if [ -f "$OUT_DIR/condominio_topology_hierarchical.png" ]; then
  cp "$OUT_DIR/condominio_topology_hierarchical.png" "$PLOTS_DIR/fig5_topology_diagram_hierarchical.png" || true
fi

echo "Topology diagrams copied to $PLOTS_DIR"
