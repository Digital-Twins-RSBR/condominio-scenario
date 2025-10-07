#!/bin/sh
set -eu
# Organize report outputs produced by the test run.
# Moves raw Influx exports, generated reports and broken influx-produced
# report CSVs into subfolders under results/ and computes mean ODTE.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="$ROOT_DIR/results"
GENERATED_DIR="$ROOT_DIR/generated_reports"

mkdir -p "$RESULTS_DIR/raw_exports" "$RESULTS_DIR/generated_reports" \
	"$RESULTS_DIR/influx_reports_failed" "$RESULTS_DIR/flux_payloads"

echo "Organizing reports under $RESULTS_DIR"

# Move full exports (detect '_measurement' header) into raw_exports
for f in "$RESULTS_DIR"/urllc_*.csv; do
	[ -e "$f" ] || continue
	if head -n 10 "$f" | grep -q '_measurement'; then
		echo "Moving export: $(basename "$f") -> raw_exports/"
		mv -v "$f" "$RESULTS_DIR/raw_exports/" || true
	fi
done

# Move generated reports (offline generator outputs) into results/generated_reports
if [ -d "$GENERATED_DIR" ]; then
	for g in "$GENERATED_DIR"/*.csv; do
		[ -e "$g" ] || continue
		echo "Moving generated report: $(basename "$g") -> results/generated_reports/"
		mv -v "$g" "$RESULTS_DIR/generated_reports/" || true
	done
fi

# Detect broken influx-produced reports: files whose first data row has an empty sensor
for f in "$RESULTS_DIR"/*odte*.csv "$RESULTS_DIR/generated_reports"/*odte*.csv; do
	[ -e "$f" ] || continue
	data_line=$(sed -n '2p' "$f" 2>/dev/null || true)
	first_field=$(printf '%s' "$data_line" | awk -F, '{print $1}')
	if [ -z "$first_field" ]; then
		echo "Detected broken ODTE CSV (empty sensor): $(basename "$f") -> influx_reports_failed/"
		mv -v "$f" "$RESULTS_DIR/influx_reports_failed/" || true
	fi
done

# Compute mean ODTE from newest generated ODTE CSV (ignore sensors with sent_count==0)
latest=$(ls -1t "$RESULTS_DIR"/generated_reports/urllc_odte_*.csv 2>/dev/null | head -n1 || true)
if [ -z "$latest" ]; then
	echo "No generated ODTE CSV found in $RESULTS_DIR/generated_reports"
	exit 0
fi

echo "Computing mean ODTE from: $(basename "$latest")"
mean=$(python3 - <<PY
import csv
f='''$latest'''
vals=[]
with open(f,newline='') as fh:
		r=csv.DictReader(fh)
		for row in r:
				try:
						s=int(row.get('sent_count','0') or 0)
						od=float(row.get('ODTE','0') or 0)
				except:
						continue
				if s>0:
						vals.append(od)
if vals:
		print(sum(vals)/len(vals))
else:
		print(0.0)
PY
)

summary_file="$(ls -1t "$RESULTS_DIR"/summary_urllc_*.txt 2>/dev/null | head -n1 || true)"
if [ -z "$summary_file" ]; then
	summary_file="$RESULTS_DIR/summary_urllc_$(date -u +%Y%m%dT%H%M%SZ).txt"
fi

echo "mean_ODTE,${mean}" >> "$summary_file"
echo "Appended mean_ODTE=${mean} to $summary_file"

echo "Done. Organized outputs under $RESULTS_DIR."

# Run visualizer automatically if present and there are generated reports
GEN_DIR="$RESULTS_DIR/generated_reports"
VISUALIZER="$ROOT_DIR/scripts/report_generators/visualize_reports.py"
if [ -d "$GEN_DIR" ] && [ -f "$VISUALIZER" ]; then
	echo "Running visualizer on $GEN_DIR"
	if command -v python3 >/dev/null 2>&1; then
		python3 "$VISUALIZER" "$GEN_DIR" || echo "Visualizer failed (see output)"
	else
		echo "python3 not available; skipping visualization"
	fi
else
	echo "Visualizer not run: generated_reports dir or visualizer script missing"
fi
