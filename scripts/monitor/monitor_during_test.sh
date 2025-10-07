#!/bin/sh
# Wrapper to call monitor script relocated for organization
exec sh scripts/monitor/monitor_during_test_impl.sh "$@"
