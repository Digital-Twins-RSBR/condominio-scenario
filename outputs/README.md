outputs/

Purpose: a single place for generated test outputs to live. This repository historically used `results/` at the repo root and several per-script generated_reports/ folders. To simplify workflows, we now provide an `outputs/` umbrella which contains:

- outputs/results/: canonical storage for raw exports and test-run directories (e.g., test_20251001T214429Z_urllc)
- outputs/reports/: canonical storage for processed report files (CSV summaries, evaluation tables, LaTeX sections)
- outputs/plots/: canonical storage for generated PNG/SVG figures used in papers and dashboards

Migration suggestions:
1. Move existing `results/` contents into `outputs/results/`:
   - mv results/* outputs/results/  # review before deleting `results/` folder
2. Update Makefile targets or export REPORTS_DIR to point to outputs/results/generated_reports when invoking plotting scripts.
3. The scripts in `scripts/reports/report_generators/` will write their outputs where they currently do; consider updating them to write to `outputs/` if you want the global location enforced.

Notes:
- I created the directories only; I did not move any existing data. Please review migration steps and confirm if you want me to move files and update scripts/Makefile accordingly.
