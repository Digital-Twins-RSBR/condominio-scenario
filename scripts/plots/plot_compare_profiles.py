#!/usr/bin/env python3
"""Proxy wrapper for plot_compare_profiles.py moved under scripts/plots.
Delegates to original module if available under scripts/.
"""
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.plot_compare_profiles import main

if __name__ == '__main__':
    main()
