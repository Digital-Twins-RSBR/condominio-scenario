#!/usr/bin/env python3
"""Wrapper delegating to top-level scripts/render_article.py (moved for organization).
This small file exists so Makefile and other callers can reference scripts/reports/render_article.py
while the main implementation remains in scripts/ (or vice-versa). For now it imports the original.
"""
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.render_article import main

if __name__ == '__main__':
    main()
