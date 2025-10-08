#!/usr/bin/env python3
"""Deprecated entrypoint.

This script used to forward to the canonical implementation under
`scripts/reports/report_generators/_compute_run_metrics.py` but callers
were migrated. Keep this stub to provide a clear error message if any
external system still calls the old path.
"""
import sys

msg = (
    "ERROR: this wrapper was removed. Use the canonical implementation:"
    " scripts/reports/report_generators/_compute_run_metrics.py\n"
    "Example: python3 scripts/reports/report_generators/_compute_run_metrics.py <generated_reports_dir>"
)
print(msg, file=sys.stderr)
sys.exit(2)
