#!/usr/bin/env python3
"""Compatibility wrapper for moved compare_urllc_tests.py
"""
import os
import sys

HERE = os.path.dirname(__file__)
TARGET = os.path.join(HERE, 'reports', 'report_generators', 'compare_urllc_tests.py')

if __name__ == '__main__':
    os.execv(sys.executable, [sys.executable, TARGET] + sys.argv[1:])