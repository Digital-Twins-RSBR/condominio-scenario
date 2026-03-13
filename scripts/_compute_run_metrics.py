#!/usr/bin/env python3
import os, sys
HERE = os.path.dirname(__file__)
CANON = os.path.normpath(os.path.join(HERE, 'reports', 'report_generators', '_compute_run_metrics.py'))
if os.path.exists(CANON):
    os.execv(sys.executable, [sys.executable, CANON] + sys.argv[1:])
else:
    sys.stderr.write('Canonical _compute_run_metrics.py not found\n')
    sys.exit(2)
