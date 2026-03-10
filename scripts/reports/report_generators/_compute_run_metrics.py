#!/usr/bin/env python3
"""Moved implementation of _compute_run_metrics.py
Canonical location for report computation helpers used by generators.
"""
import argparse
import csv
import glob
import os
import re
import statistics
import sys


def _normalize_request_id(raw):
    if raw is None:
        return ''
    req = str(raw).strip()
    req = req.strip('"')
    while len(req) >= 2 and req.startswith('"') and req.endswith('"'):
        req = req[1:-1].strip()
    return req


def _looks_like_uuid(raw):
    if not raw:
        return False
    value = str(raw).strip().strip('"')
    return bool(re.match(r'^[0-9a-fA-F-]{32,36}$', value))


def read_raw_export_metrics(device_csv='', latency_csv=''):
    out = {}
    s2m_received = 0
    m2s_sent = 0
    m2s_received = 0

    # S2M count from device_data export
    if device_csv and os.path.exists(device_csv):
        try:
            with open(device_csv, newline='') as f:
                r = csv.DictReader(f)
                for row in r:
                    if row.get('direction') == 'S2M' and row.get('_field') == 'received_timestamp':
                        s2m_received += 1
        except Exception:
            pass

    # M2S latency pairing by correlation_id (unique per command-response pair).
    # sent rows: sensor=<uuid>, correlation_id=<uuid>, dt_id=<int>, source=middts
    # received rows: sensor='middts' (column-shift), correlation_id=<uuid>, dt_id=<sensor_uuid>
    m2s_sent_map = {}   # {corr_id: sent_ts_ms}
    m2s_recv_map = {}   # {corr_id: recv_ts_ms}  (first occurrence wins)
    if latency_csv and os.path.exists(latency_csv):
        try:
            with open(latency_csv, newline='') as f:
                for row in csv.DictReader(f):
                    if row.get('direction') != 'M2S':
                        continue
                    field = row.get('_field')
                    if field not in ('sent_timestamp', 'received_timestamp'):
                        continue
                    corr_id = row.get('correlation_id') or row.get('request_id') or ''
                    if not corr_id:
                        continue
                    corr_id = _normalize_request_id(corr_id)
                    try:
                        ts = int(float(row.get('_value', '0')))
                    except (ValueError, TypeError):
                        continue
                    if field == 'sent_timestamp':
                        m2s_sent += 1
                        if corr_id not in m2s_sent_map:
                            m2s_sent_map[corr_id] = ts
                    elif field == 'received_timestamp':
                        m2s_received += 1
                        if corr_id not in m2s_recv_map:
                            m2s_recv_map[corr_id] = ts
        except Exception:
            pass

    m2s_lat = []
    for corr_id, sent_ts in m2s_sent_map.items():
        if corr_id in m2s_recv_map:
            dt_s = (m2s_recv_map[corr_id] - sent_ts) / 1000.0  # seconds
            if 0 <= dt_s < 60:  # sanity: < 60s
                m2s_lat.append(dt_s)

    lat_used = m2s_lat
    pairs_used = len(m2s_lat)

    # Calculate S2M latency from device_data (sent_timestamp + received_timestamp)
    # Use FIFO matching per sensor to handle multiple events per sensor correctly.
    # S2M CSV rows have a column-shift: sensor UUID lands in request_id, sensor=middts.
    s2m_lat = []
    s2m_sent_count = 0
    if device_csv and os.path.exists(device_csv):
        try:
            from collections import deque
            sent_by_sensor = {}
            recv_by_sensor = {}
            with open(device_csv, newline='') as f:
                for row in csv.DictReader(f):
                    if row.get('direction') != 'S2M':
                        continue
                    sensor = row.get('sensor', '')
                    req = row.get('request_id', '')
                    source = row.get('source', '')

                    # Recover real sensor UUID when columns are shifted
                    if (not source) and str(sensor).strip() in ('middts', 'simulator') and _looks_like_uuid(req):
                        sensor = str(req).strip().strip('"')

                    field = row.get('_field', '')
                    try:
                        ts = int(float(row.get('_value', '0')))
                    except (ValueError, TypeError):
                        continue

                    if field == 'sent_timestamp':
                        sent_by_sensor.setdefault(sensor, []).append(ts)
                        s2m_sent_count += 1
                    elif field == 'received_timestamp':
                        recv_by_sensor.setdefault(sensor, []).append(ts)

            # FIFO pairing per sensor: match each sent with earliest recv >= sent
            for sensor in sent_by_sensor:
                if sensor not in recv_by_sensor:
                    continue
                sent_q = deque(sorted(sent_by_sensor[sensor]))
                recv_q = deque(sorted(recv_by_sensor[sensor]))
                while sent_q and recv_q:
                    sv = sent_q[0]
                    rv = recv_q[0]
                    if rv >= sv:
                        dt = (rv - sv) / 1000.0  # ms -> seconds
                        if 0 <= dt < 10:  # sanity: < 10s
                            s2m_lat.append(dt)
                        sent_q.popleft()
                        recv_q.popleft()
                    else:
                        recv_q.popleft()  # orphan recv before any sent
        except Exception:
            pass

    # Keep legacy keys expected by summaries (but now calculated!)
    if s2m_lat:
        s2m_lat.sort()
        out['mean_S2M_ms'] = round(sum(s2m_lat) / len(s2m_lat) * 1000.0, 3)  # Convert to ms
        out['median_S2M_ms'] = round(statistics.median(s2m_lat) * 1000.0, 3)  # Convert to ms
    else:
        out['mean_S2M_ms'] = 0.0
        out['median_S2M_ms'] = 0.0
    out['S2M_total_count'] = s2m_received
    out['S2M_sent_count'] = s2m_sent_count
    out['S2M_matched_pairs'] = len(s2m_lat)

    if lat_used:
        lat_used.sort()
        n = len(lat_used)
        mean_s = sum(lat_used) / n
        out['mean_M2S_ms'] = round(mean_s * 1000.0, 3)
        out['median_M2S_ms'] = round(statistics.median(lat_used) * 1000.0, 3)
        out['P50_M2S_ms'] = round(lat_used[n // 2] * 1000.0, 3)
        out['P95_M2S_ms'] = round(lat_used[int(n * 0.95)] * 1000.0, 3)
        out['P99_M2S_ms'] = round(lat_used[int(n * 0.99)] * 1000.0, 3)
        cv_m2s = statistics.stdev(lat_used) / mean_s if n > 1 else 0
        out['CV_M2S_pct'] = round(cv_m2s * 100, 2)
        # AoT Mean = M2S mean latency (freshness of digital twin state)
        # Twin Fidelity = fraction of M2S commands that got a response
        out['aot_mean_ms'] = out['mean_M2S_ms']
        out['aot_p95_ms'] = out['P95_M2S_ms']
        out['twin_fidelity_pct'] = round(pairs_used * 100.0 / m2s_sent, 2) if m2s_sent > 0 else 0.0
    else:
        out['mean_M2S_ms'] = 0.0
        out['median_M2S_ms'] = 0.0
        out['P95_M2S_ms'] = 0.0
        out['aot_mean_ms'] = 0.0
        out['aot_p95_ms'] = 0.0
        out['twin_fidelity_pct'] = 0.0

    # S2M percentiles (lat array already in seconds)
    if s2m_lat:
        n = len(s2m_lat)
        out['P50_S2M_ms'] = round(s2m_lat[n // 2] * 1000.0, 3)
        out['P95_S2M_ms'] = round(s2m_lat[int(n * 0.95)] * 1000.0, 3)
        out['P99_S2M_ms'] = round(s2m_lat[int(n * 0.99)] * 1000.0, 3)
        mean_s2m = sum(s2m_lat) / n
        cv_s2m = statistics.stdev(s2m_lat) / mean_s2m if n > 1 else 0
        out['CV_S2M_pct'] = round(cv_s2m * 100, 2)

    out['M2S_total_count'] = m2s_received
    out['M2S_sent_count'] = m2s_sent
    out['M2S_received_count'] = m2s_received
    out['M2S_matched_pairs'] = pairs_used
    out['R_m2s_event_percent'] = round(m2s_received * 100.0 / m2s_sent, 3) if m2s_sent > 0 else 0.0
    out['R_m2s_pair_percent'] = round(pairs_used * 100.0 / m2s_sent, 3) if m2s_sent > 0 else 0.0

    return out


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
    p.add_argument('--device-csv', required=False, default='')
    p.add_argument('--latency-csv', required=False, default='')
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

    # Always run raw CSV analysis when CSVs are available.
    # Per-sensor stats (from generated_reports) provide better mean/count if available.
    # Raw CSV pairing provides matched_pairs, percentiles, AoT/TF which per-sensor stats lack.
    if args.device_csv and args.latency_csv:
        raw = read_raw_export_metrics(args.device_csv, args.latency_csv)
        if out.get('S2M_total_count', 0) == 0 and out.get('M2S_total_count', 0) == 0:
            # No generated reports at all — full fallback
            out.update(raw)
        else:
            # Supplement with pair-level insights only available from raw CSV
            supplement_keys = [
                'S2M_matched_pairs', 'S2M_sent_count', 'mean_S2M_ms', 'median_S2M_ms',
                'P50_S2M_ms', 'P95_S2M_ms', 'P99_S2M_ms', 'CV_S2M_pct',
                'M2S_matched_pairs', 'M2S_sent_count', 'M2S_received_count',
                'R_m2s_pair_percent', 'mean_M2S_ms', 'median_M2S_ms',
                'P50_M2S_ms', 'P95_M2S_ms', 'P99_M2S_ms', 'CV_M2S_pct',
                'aot_mean_ms', 'aot_p95_ms', 'twin_fidelity_pct',
            ]
            for key in supplement_keys:
                if key in raw:
                    out[key] = raw[key]

    append_summary(args.summary, out)


if __name__ == '__main__':
    main()
