#!/usr/bin/env python3
"""
Analyze ODTE results and keep only devices that had bidirectional activity:
- Telemetry (simulator -> middts -> Influx) presence (from ODTE CSV)
- RPC responses recorded in updater logs (RPC_RESULT lines)

Produces:
- filtered_odte_<ts>.csv in the same reports directory
- summary_bidirectional_<ts>.txt with counts and basic stats
"""
import sys, os, re, csv, statistics
from datetime import datetime

if len(sys.argv) < 2:
    print("Usage: analyze_bidirectional.py <reports_dir>")
    sys.exit(1)

reports_dir = sys.argv[1]
if not os.path.isdir(reports_dir):
    print("reports_dir not found:", reports_dir)
    sys.exit(1)

# Find the ODTE CSV (usual pattern: urllc_odte_*.csv)
odte_csv = None
for fn in os.listdir(reports_dir):
    if fn.startswith('urllc_odte_') and fn.endswith('.csv'):
        #!/usr/bin/env python3
        """
        analyze_bidirectional.py

        Analyze ODTE results and keep only devices that had bidirectional activity:
        - Telemetry (simulator -> middts -> Influx) presence (from ODTE CSV)
        - RPC responses recorded in updater logs (RPC_RESULT lines)

        Produces:
        - filtered_odte_<ts>.csv in the same reports directory
        - summary_bidirectional_<ts>.txt with counts and basic stats
        """
        import sys
        import os
        import re
        import csv
        import statistics
        from datetime import datetime

        if len(sys.argv) < 2:
            print("Usage: analyze_bidirectional.py <reports_dir>")
            sys.exit(1)

        reports_dir = sys.argv[1]
        if not os.path.isdir(reports_dir):
            print("reports_dir not found:", reports_dir)
            sys.exit(1)

        # Find the ODTE CSV (usual pattern: urllc_odte_*.csv)
        odte_csv = None
        for fn in os.listdir(reports_dir):
            if fn.startswith('urllc_odte_') and fn.endswith('.csv'):
                odte_csv = os.path.join(reports_dir, fn)
                break

        if not odte_csv:
            print('No ODTE CSV found in', reports_dir)
            sys.exit(1)

        # Read the ODTE CSV and collect telemetry device ids (ThingsBoard ids)
        telemetry_ids = set()
        rows = []
        with open(odte_csv, 'r', newline='') as f:
            reader = csv.DictReader(f)
            for r in reader:
                rows.append(r)
                # try common columns
                for col in ('sensor', 'device_id', 'thingsboard_id', 'tb_id'):
                    if col in r and r[col]:
                        telemetry_ids.add(r[col])

        # Parse updater log for RPC_RESULT lines
        # Look for files previously copied or in /middleware-dt logs
        rpc_ids = set()
        rpc_times = []
        log_candidates = [
            '/tmp/update_causal_property_abrangente_current.out',
            '/tmp/update_causal_property_current.out',
            '/middleware-dt/update_causal_property.out'
        ]
        regex = re.compile(r"RPC_RESULT .* tb_id=(?P<tb>[0-9a-f-]+) .* time=(?P<time>[0-9.]+)")

        for path in log_candidates:
            try:
                with open(path, 'r', errors='ignore') as f:
                    for l in f:
                        m = regex.search(l)
                        if m:
                            rpc_ids.add(m.group('tb'))
                            try:
                                rpc_times.append(float(m.group('time')))
                            except Exception:
                                pass
            except Exception:
                continue

        # Devices with bidirectional activity are intersection of telemetry_ids and rpc_ids
        bidirectional = telemetry_ids & rpc_ids

        # Write filtered CSV containing only rows where sensor/tb matches bidirectional set
        ts = datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')
        filtered_csv = os.path.join(reports_dir, f'filtered_odte_{ts}.csv')
        with open(filtered_csv, 'w', newline='') as out:
            if rows:
                writer = csv.DictWriter(out, fieldnames=rows[0].keys())
                writer.writeheader()
                for r in rows:
                    found = False
                    for col in ('sensor', 'device_id', 'thingsboard_id', 'tb_id'):
                        if col in r and r[col] and r[col] in bidirectional:
                            found = True
                            break
                    if found:
                        writer.writerow(r)

        # Summary
        summary_file = os.path.join(reports_dir, f'summary_bidirectional_{ts}.txt')
        with open(summary_file, 'w') as sf:
            sf.write(f"timestamp={ts}\n")
            sf.write(f"telemetry_devices={len(telemetry_ids)}\n")
            sf.write(f"rpc_devices={len(rpc_ids)}\n")
            sf.write(f"bidirectional_devices={len(bidirectional)}\n")
            sf.write(f"rpc_count={len(rpc_times)}\n")
            if rpc_times:
                sf.write(f"mean_rpc_time={statistics.mean(rpc_times):.6f}\n")
                sf.write(f"median_rpc_time={statistics.median(rpc_times):.6f}\n")
                sf.write(f"max_rpc_time={max(rpc_times):.6f}\n")

        print('Wrote filtered CSV:', filtered_csv)
        print('Wrote summary:', summary_file)
