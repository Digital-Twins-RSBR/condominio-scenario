#!/bin/sh
# Wrapper to run the topology visualizer and copy PNG outputs into article/plots
set -eu
PROOT=$(dirname "$0")/..
cd "$PROOT"
# maintain legacy ROOT name for compatibility with existing code
ROOT="$PROOT"
# Prefer an existing reports venv, then docs venv, then generic .venv
if [ -f "$PROOT/.venv-reports/bin/activate" ]; then
  # shellcheck disable=SC1091
  . "$PROOT/.venv-reports/bin/activate"
  PYTHON=${PYTHON:-"$PROOT/.venv-reports/bin/python"}
elif [ -f "$PROOT/.venv-docs/bin/activate" ]; then
  . "$PROOT/.venv-docs/bin/activate"
  PYTHON=${PYTHON:-"$PROOT/.venv-docs/bin/python"}
elif [ -f "$PROOT/.venv/bin/activate" ]; then
  . "$PROOT/.venv/bin/activate"
  PYTHON=${PYTHON:-"$PROOT/.venv/bin/python"}
else
  PYTHON=${PYTHON:-python3}
  echo "[WARN] No project virtualenv found (.venv-reports/.venv-docs/.venv). Using system python ($PYTHON)."
  echo "If you encounter ImportError for pydot, create and activate a virtualenv and install requirements/local.txt:"
  echo "  python3 -m venv .venv-reports && . .venv-reports/bin/activate && pip install -r requirements/local.txt"
fi
OUT_DIR="$ROOT/outputs/topology_output"
PLOTS_DIR="$ROOT/outputs/results/article/plots"
mkdir -p "$PLOTS_DIR"

# Ensure Graphviz 'dot' binary is available (pydot requires it)
if ! command -v dot >/dev/null 2>&1; then
  echo "[WARN] 'dot' (Graphviz) command not found. Install system package 'graphviz' (apt: sudo apt-get install -y graphviz)"
fi

# Run visualizer with a sensible default of 6 sims
set +e
$PYTHON services/topology/topology_visualizer.py --sims 5 --output "$OUT_DIR" --filename condominio_topology
RC=$?
set -e
if [ $RC -ne 0 ]; then
  echo "[ERROR] topology_visualizer.py exited with code $RC (see above)."
fi

# Copy main outputs if present
if [ -f "$OUT_DIR/condominio_topology_main.png" ]; then
  cp "$OUT_DIR/condominio_topology_main.png" "$PLOTS_DIR/fig5_topology_diagram.png" || true
fi
if [ -f "$OUT_DIR/condominio_topology_hierarchical.png" ]; then
  cp "$OUT_DIR/condominio_topology_hierarchical.png" "$PLOTS_DIR/fig5_topology_diagram_hierarchical.png" || true
fi

echo "Topology diagrams copied to $PLOTS_DIR"
