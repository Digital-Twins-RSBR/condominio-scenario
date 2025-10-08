#!/usr/bin/env python3
"""Compatibility wrapper to call moved implementation under
`scripts/reports/report_generators/plot_compare_profiles.py`.
"""
import os
import sys

HERE = os.path.dirname(__file__)
TARGET = os.path.join(HERE, 'reports', 'report_generators', 'plot_compare_profiles.py')

if __name__ == '__main__':
    os.execv(sys.executable, [sys.executable, TARGET] + sys.argv[1:])
