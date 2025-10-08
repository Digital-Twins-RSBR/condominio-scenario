#!/usr/bin/env python3
"""Moved implementation of _compute_run_metrics.py
Canonical location for report computation helpers used by generators.
"""
import argparse
import csv
import glob
import os
import statistics
import sys


def read_per_sensor_stats(path_pattern):
    pairs = []
    medians_with_counts = []
    for path in glob.glob(path_pattern):
        try:
            with open(path, newline='') as f:
                r = csv.DictReader(f)
                for row in r:
                    mean = None
                    for k in ('mean_ms', 'mean', 'media_ms', 'mean_latency_ms'):
                        if k in row and row[k] != '':
                            try:
                                mean = float(row[k])
                            except Exception:
                                mean = None
                            break
                    if mean is None:
                        for v in row.values():
                            try:
                                mean = float(v)
                                break
                            except Exception:
                                continue
                    cnt = None
                    for k in ('count', 'n', 'samples'):
                        if k in row and row[k] != '':
                            try:
                                cnt = int(float(row[k]))
                            except Exception:
                                cnt = None
                            break
                    if mean is not None:
                        cval = cnt if cnt is not None else 1
                        pairs.append((mean, cval))
                        if cval > 0:
                            for mk in ('median_ms', 'median', 'mediana'):
                                if mk in row and row[mk] != '':
                                    try:
                                        med = float(row[mk])
                                        medians_with_counts.append((med, cval))
                                    except Exception:
                                        pass
                                    break
        except Exception:
            continue
    return pairs, medians_with_counts


def weighted_mean(pairs):
    total = 0.0
    cnt = 0
    for mean, c in pairs:
        cval = c if c is not None else 1
        total += mean * cval
        cnt += cval
    if cnt == 0:
        return 0.0, 0
    return (total / cnt), cnt


def median_of_means(pairs):
    vals = [m for m, _ in pairs if m is not None]
    if not vals:
        return 0.0
    return statistics.median(vals)


def median_of_medians(medians):
    if not medians:
        return 0.0
    return statistics.median(medians)


def read_ecdf(ecdf_pattern):
    for path in glob.glob(ecdf_pattern):
        try:
            data = []
            with open(path, newline='') as f:
                r = csv.reader(f)
                _ = next(r, None)
                for row in r:
                    try:
                        a = float(row[0])
                        b = float(row[1])
                        data.append((a, b))
                    except Exception:
                        continue
            if data:
                data.sort()
                return data
        except Exception:
            continue
    return None


def compute_cdf_le(data, threshold):
    if not data:
        return 0.0
    last = 0.0
    for rtt, cdf in data:
        if rtt <= threshold:
            last = cdf
        else:
            break
    return last


def approximate_pxx(data, p):
    if not data:
        return 0
    for rtt, cdf in data:
        if cdf >= p:
            return rtt
    return data[-1][0]


def read_odte_components(odte_csv):
    if not odte_csv or not os.path.exists(odte_csv):
        return {}
    try:
        with open(odte_csv, newline='') as f:
            r = csv.DictReader(f)
            tvals = []
            rvals = []
            avals = []
            for row in r:
                try:
                    middts_sent = int(float(row.get('middts_sent_count', 0) or 0))
                except Exception:
                    middts_sent = 0
                try:
                    sim_sent = int(float(row.get('sim_sent_count', 0) or 0))
                except Exception:
                    sim_sent = 0
                for key in row.keys():
                    k = key.lower()
                    val = row.get(key)
                    if val in (None, ''):
                        continue
                    if k.startswith('t'):
                        if 's2m' in k and sim_sent > 0:
                            try:
                                tvals.append(float(val))
                            except Exception:
                                pass
                        elif 'm2s' in k and middts_sent > 0:
                            try:
                                tvals.append(float(val))
                            except Exception:
                                pass
                    elif k.startswith('r'):
                        if 's2m' in k and sim_sent > 0:
                            try:
                                rvals.append(float(val))
                            except Exception:
                                pass
                        elif 'm2s' in k and middts_sent > 0:
                            try:
                                rvals.append(float(val))
                            except Exception:
                                pass
                    elif k == 'a':
                        try:
                            avals.append(float(val))
                        except Exception:
                            pass
            out = {}
            if tvals:
                out['mean_T'] = sum(tvals) / len(tvals)
                out['median_T'] = statistics.median(tvals)
            if rvals:
                out['mean_R'] = sum(rvals) / len(rvals)
                out['median_R'] = statistics.median(rvals)
            if avals:
                out['mean_A'] = sum(avals) / len(avals)
                out['median_A'] = statistics.median(avals)
            return out
    except Exception:
        return {}


def append_summary(summary_path, fields):
    print("# Computed run metrics (from _compute_run_metrics.py)")
    for k, v in fields.items():
        print(f"{k}: {v}")
    try:
        with open(summary_path, 'a') as f:
            for k, v in fields.items():
                f.write(f"{k}: {v}\n")
        return True
    except Exception as e:
        print(f"Failed to append summary: {e}", file=sys.stderr)
        try:
            fallback = os.path.basename(summary_path) + ".computed.txt"
            with open(fallback, 'w') as f:
                f.write("# Computed run metrics (fallback file)\n")
                for k, v in fields.items():
                    f.write(f"{k}: {v}\n")
            print(f"Wrote fallback computed metrics to: {fallback}")
        except Exception as e2:
            print(f"Also failed to write fallback file: {e2}", file=sys.stderr)
        return False


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--reports-dir', required=True)
    p.add_argument('--profile', required=True)
    p.add_argument('--summary', required=True)
    p.add_argument('--odte', required=False, default='')
    p.add_argument('--min-count', required=False, default=5, type=int, help='Minimum samples per sensor to include in median-of-medians')
    args = p.parse_args()
    out = {}
    s2m_pairs, s2m_medians_with_counts = read_per_sensor_stats(os.path.join(args.reports_dir, '*simulator_to_middts*.csv'))
    mean_s2m, s2m_count = weighted_mean(s2m_pairs)
    filtered_s2m_medians = [m for m, c in s2m_medians_with_counts if c >= args.min_count]
    all_s2m_medians = [m for m, _ in s2m_medians_with_counts]
    if filtered_s2m_medians:
        median_s2m = median_of_medians(filtered_s2m_medians)
    elif all_s2m_medians:
        median_s2m = median_of_medians(all_s2m_medians)
    else:
        median_s2m = median_of_means(s2m_pairs)
    out['mean_S2M_ms'] = round(mean_s2m, 3)
    out['median_S2M_ms'] = round(median_s2m, 3)
    out['S2M_total_count'] = s2m_count
    m2s_pairs, m2s_medians_with_counts = read_per_sensor_stats(os.path.join(args.reports_dir, '*middts_to_simulator*.csv'))
    mean_m2s, m2s_count = weighted_mean(m2s_pairs)
    filtered_m2s_medians = [m for m, c in m2s_medians_with_counts if c >= args.min_count]
    all_m2s_medians = [m for m, _ in m2s_medians_with_counts]
    if filtered_m2s_medians:
        median_m2s = median_of_medians(filtered_m2s_medians)
    elif all_m2s_medians:
        median_m2s = median_of_medians(all_m2s_medians)
    else:
        median_m2s = median_of_means(m2s_pairs)
    out['mean_M2S_ms'] = round(mean_m2s, 3)
    out['median_M2S_ms'] = round(median_m2s, 3)
    out['M2S_total_count'] = m2s_count
    ecdf = read_ecdf(os.path.join(args.reports_dir, '*ecdf_rtt_*.csv'))
    if ecdf:
        p95 = approximate_pxx(ecdf, 0.95)
        cdf200 = compute_cdf_le(ecdf, 200)
        out['P95_ms'] = int(round(p95))
        out['cdf_le_200'] = round(cdf200, 6)
        median_overall = approximate_pxx(ecdf, 0.5)
        out['median_overall_ms'] = round(median_overall, 3)
    odte_comp = read_odte_components(args.odte)
    for k, v in odte_comp.items():
        if isinstance(v, float):
            out[k] = round(v, 6) if 'mean' in k or 'median' in k else v
        else:
            out[k] = v
    append_summary(args.summary, out)


if __name__ == '__main__':
    main()
