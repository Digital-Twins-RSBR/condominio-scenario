This folder groups plotting and visualization helpers.

Files moved here from `scripts/`:
- generate_all_plots.sh
- plot_compare_profiles.py
- plot_reviewer_figures.py
- generate_topology_diagram.sh (if present)

Do not call these directly from Makefile; use `make plots` which delegates to `scripts/reports/render_article.py`.
