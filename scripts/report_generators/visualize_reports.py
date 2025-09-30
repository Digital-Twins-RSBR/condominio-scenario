#!/usr/bin/env python3
"""
Aggregate generated reports and produce visualization PNGs.

Usage: python3 scripts/report_generators/visualize_reports.py <generated_reports_dir>

Produces PNGs in <generated_reports_dir>/plots/:
- ecdf_rtt.png
- odte_per_sensor.png
- odte_time_series.png
- latency_tails.png
"""
import csv
import sys
import os
from datetime import datetime
import math


def safe_float(s):
    try:
        return float(s)
    except Exception:
        return 0.0


def read_csv_dict(path):
    with open(path, newline='') as f:
        r = csv.DictReader(f)
        return list(r)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    d = sys.argv[1]
    if not os.path.isdir(d):
        print('dir not found:', d)
        sys.exit(2)

    plots_dir = os.path.join(d, 'plots')
    os.makedirs(plots_dir, exist_ok=True)

    # find latest odte, ecdf, windows, latency files
    def latest(pattern):
        files = [os.path.join(d, f) for f in os.listdir(d) if f.startswith(pattern)]
        files = [f for f in files if os.path.isfile(f)]
        if not files:
            return None
        return sorted(files, key=os.path.getmtime)[-1]

    odte = latest('urllc_odte_')
    ecdf = latest('urllc_ecdf_rtt_')
    windows = latest('urllc_windows_')
    lat_m = latest('urllc_latencia_stats_middts_to_simulator_')

    # Try importing matplotlib; if unavailable, print an instruction
    try:
        import matplotlib.pyplot as plt
        import numpy as np
    except Exception as e:
        print('matplotlib/numpy not available. To generate plots install them:')
        print('  sudo pip3 install matplotlib numpy')
        sys.exit(3)

    # ECDF plot
    if ecdf:
        rows = read_csv_dict(ecdf)
        xs = [safe_float(r.get('rtt_ms', 0)) for r in rows]
        cs = [safe_float(r.get('cdf', 0)) for r in rows]
        plt.figure(figsize=(6,4))
        plt.plot(xs, cs, drawstyle='steps-post')
        plt.xlabel('RTT (ms)')
        plt.ylabel('CDF')
        plt.title('RTT ECDF')
        plt.grid(True)
        out = os.path.join(plots_dir, 'ecdf_rtt.png')
        plt.savefig(out, bbox_inches='tight')
        plt.close()
        print('Wrote', out)

    # ODTE per sensor
    if odte:
        rows = read_csv_dict(odte)
        sensors = [r.get('sensor','') for r in rows]
        odtes = [safe_float(r.get('ODTE', 0)) for r in rows]
        sent = [int(r.get('sent_count') or 0) for r in rows]
        # sort by odte desc
        order = sorted(range(len(sensors)), key=lambda i: odtes[i], reverse=True)
        sensors_s = [sensors[i] for i in order]
        odtes_s = [odtes[i] for i in order]
        sent_s = [sent[i] for i in order]
        plt.figure(figsize=(10,6))
        plt.bar(range(len(odtes_s)), odtes_s, color='C0')
        plt.xticks(range(len(sensors_s)), sensors_s, rotation=90, fontsize=6)
        plt.ylabel('ODTE')
        plt.title('ODTE per sensor (sorted)')
        plt.tight_layout()
        out = os.path.join(plots_dir, 'odte_per_sensor.png')
        plt.savefig(out, bbox_inches='tight')
        plt.close()
        print('Wrote', out)

    # ODTE time series (windows)
    if windows:
        rows = read_csv_dict(windows)
        times = [r.get('window_start_iso') for r in rows]
        odte_mean = [safe_float(r.get('ODTE_mean') or r.get('odte_mean') or 0) for r in rows]
        plt.figure(figsize=(8,4))
        x = list(range(len(times)))
        plt.plot(x, odte_mean, marker='o')
        plt.xlabel('window idx (10s)')
        plt.ylabel('ODTE mean')
        plt.title('ODTE over time (10s windows)')
        plt.grid(True)
        out = os.path.join(plots_dir, 'odte_time_series.png')
        plt.savefig(out, bbox_inches='tight')
        plt.close()
        print('Wrote', out)

    # Latency tails: p95/p99/jitter per sensor
    if lat_m:
        rows = read_csv_dict(lat_m)
        sensors = [r.get('sensor') for r in rows]
        p95 = [safe_float(r.get('p95_ms', r.get('p95', 0))) for r in rows]
        p99 = [safe_float(r.get('p99_ms', r.get('p99', 0))) for r in rows]
        jitter = [safe_float(r.get('jitter_ms', r.get('jitter', 0))) for r in rows]
        x = list(range(len(sensors)))
        width = 0.35
        plt.figure(figsize=(10,6))
        plt.bar(x, p95, width=width, label='p95')
        plt.bar([i+width for i in x], p99, width=width, label='p99')
        plt.xticks([i+width/2 for i in x], sensors, rotation=90, fontsize=6)
        plt.ylabel('ms')
        plt.title('Latency tails (p95/p99) per sensor')
        plt.legend()
        plt.tight_layout()
        out = os.path.join(plots_dir, 'latency_tails.png')
        plt.savefig(out, bbox_inches='tight')
        plt.close()
        print('Wrote', out)

    print('Plots written to', plots_dir)


if __name__ == '__main__':
    main()
