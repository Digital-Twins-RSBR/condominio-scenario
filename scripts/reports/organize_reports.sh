#!/bin/sh
# Wrapper delegating to top-level script to preserve behavior while organizing files
exec sh scripts/organize_reports.sh "$@"
