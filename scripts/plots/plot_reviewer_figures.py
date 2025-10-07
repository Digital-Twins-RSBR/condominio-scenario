#!/usr/bin/env python3
"""Proxy wrapper: original plot_reviewer_figures living in scripts/ was moved here.
This file is a copy of the original and its imports assume repo root layout.
"""
import sys
from pathlib import Path

# Adjust sys.path to allow imports relative to repo root if needed
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.plot_reviewer_figures import main

if __name__ == '__main__':
    main()
