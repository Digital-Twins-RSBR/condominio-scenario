#!/usr/bin/env python3
"""
Generate ODTE and latency reports from an Influx-exported CSV.

Usage: python3 scripts/report_generators/generate_reports_from_export.py <input_csv> <profile> [out_dir]

Produces files in the provided out_dir (default: results/) with names similar to the Flux reports:
- <profile>_odte_<ts>.csv
- <profile>_latencia_stats_middts_to_simulator_<ts>.csv
- <profile>_latencia_stats_simulator_to_middts_<ts>.csv

This is the offline equivalent of the Flux reports: it parses the raw Influx CSV export
and computes per-sensor latencies, T/R/A and ODTE.
"""
import csv
import sys
import os
from datetime import datetime, timezone
from collections import defaultdict
import statistics
import math

AVAIL_INTERVAL = 10.0  # seconds
DEADLINE_S = 0.2


def iso_to_epoch(s):
    if not s:
        return None
    try:
        if s.endswith('Z'):
            s = s[:-1]
            try:
                dt = datetime.strptime(s, '%Y-%m-%dT%H:%M:%S.%f')
            except ValueError:
                dt = datetime.strptime(s, '%Y-%m-%dT%H:%M:%S')
            dt = dt.replace(tzinfo=timezone.utc)
            return dt.timestamp()
        else:
            dt = datetime.fromisoformat(s)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.timestamp()
    except Exception:
        return None


def read_export(csv_path):
    rows = []
    header = None
    with open(csv_path, newline='') as f:
        reader = csv.reader(f)
        for r in reader:
            # detect header rows containing the Influx '_measurement' column
            if any(cell.strip() == '_measurement' for cell in r):
                header = [h.strip() for h in r]
                continue
            if header is None:
                continue
            if len(r) < len(header):
                r += [''] * (len(header) - len(r))
            rec = dict(zip(header, r))
            rows.append(rec)
    return header, rows


def build_time_lists(rows):
    middts_sent = defaultdict(list)
    sim_recv = defaultdict(list)
    sim_sent = defaultdict(list)
    middts_recv = defaultdict(list)
    events_time_by_sensor = defaultdict(list)
    start_ts = None
    stop_ts = None
    for r in rows:
        meas = r.get('_measurement', '')
        if meas != 'device_data':
            continue
        sensor = r.get('sensor', '')
        source = r.get('source', '')
        field = r.get('_field', '')
        val = r.get('_value', '')
        t_iso = r.get('_time', '')
        t_epoch = iso_to_epoch(t_iso)
        if t_epoch is not None:
            events_time_by_sensor[sensor].append(t_epoch)
            if start_ts is None or t_epoch < start_ts:
                start_ts = t_epoch
            if stop_ts is None or t_epoch > stop_ts:
                stop_ts = t_epoch
        try:
            num = int(val) if val != '' else None
        except Exception:
            try:
                num = int(float(val))
            except Exception:
                num = None
        if field == 'sent_timestamp' and source == 'middts' and num is not None:
            middts_sent[sensor].append(num)
        if field == 'received_timestamp' and source == 'simulator' and num is not None:
            sim_recv[sensor].append(num)
        if field == 'sent_timestamp' and source == 'simulator' and num is not None:
            sim_sent[sensor].append(num)
        if field == 'received_timestamp' and source == 'middts' and num is not None:
            middts_recv[sensor].append(num)

    for d in (middts_sent, sim_recv, sim_sent, middts_recv):
        for k in d:
            d[k].sort()

    return {
        'middts_sent': middts_sent,
        'sim_recv': sim_recv,
        'sim_sent': sim_sent,
        'middts_recv': middts_recv,
        'events_time_by_sensor': events_time_by_sensor,
        'start_ts': start_ts,
        'stop_ts': stop_ts,
    }


def match_sent_to_recv(sent_list_ms, recv_list_ms):
    # Default pairing: 1:1 sequential pairing where each sent is paired with
    # at most one recv (the next recv >= sent). This prevents multiple receives
    # from being attributed to the same sent (avoids R>1 artifacts).
    # Returns list of tuples (recv_ms, latency_ms).
    sent_sorted = sorted(sent_list_ms)
    recv_sorted = sorted(recv_list_ms)
    pairs = []
    si = 0
    ri = 0
    # advance through both lists pairing each sent to the next recv >= sent
    while si < len(sent_sorted) and ri < len(recv_sorted):
        s = sent_sorted[si]
        r = recv_sorted[ri]
        if r < s:
            # this recv happened before the current send, skip it
            ri += 1
            continue
        # r >= s: pair them
        lat = r - s
        if lat >= 0:
            pairs.append((r, lat))
        si += 1
        ri += 1
    return pairs


def compute_availability(events_time_by_sensor, start_ts, stop_ts, interval=AVAIL_INTERVAL):
    avail = {}
    if start_ts is None or stop_ts is None:
        return avail
    total_windows = int(((stop_ts - start_ts) // interval) + 1)
    for sensor, times in events_time_by_sensor.items():
        windows_with_event = set()
        for t in times:
            idx = int((t - start_ts) // interval)
            windows_with_event.add(idx)
        if total_windows > 0:
            avail[sensor] = len(windows_with_event) / float(total_windows)
        else:
            avail[sensor] = 0.0
    return avail


def percentile(sorted_list, p):
    # p in [0,100]
    if not sorted_list:
        return 0.0
    k = (len(sorted_list) - 1) * (p / 100.0)
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return float(sorted_list[int(k)])
    d0 = sorted_list[int(f)] * (c - k)
    d1 = sorted_list[int(c)] * (k - f)
    return float(d0 + d1)


def stats_from_latencies(lat_ms_list):
    if not lat_ms_list:
        return {'count': 0, 'mean': 0, 'median': 0, 'min': 0, 'max': 0, 'p95': 0, 'p99': 0, 'p999': 0, 'jitter': 0}
    s = sorted(lat_ms_list)
    mean = statistics.mean(s)
    median = statistics.median(s)
    jitter = statistics.pstdev(s) if len(s) > 1 else 0.0
    return {
        'count': len(s),
        'mean': mean,
        'median': median,
        'min': min(s),
        'max': max(s),
        'p95': percentile(s, 95),
        'p99': percentile(s, 99),
        'p999': percentile(s, 99.9),
        'jitter': jitter,
    }


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    inp = sys.argv[1]
    profile = sys.argv[2]
    out_dir = sys.argv[3] if len(sys.argv) > 3 else 'results'
    if not os.path.exists(inp):
        print('Input CSV not found:', inp)
        sys.exit(2)

    header, rows = read_export(inp)
    data = build_time_lists(rows)

    middts_sent = data['middts_sent']
    sim_recv = data['sim_recv']
    # sensors union across all lists
    sensors = set(list(middts_sent.keys()) + list(sim_recv.keys()) + list(data['events_time_by_sensor'].keys()) + list(data['sim_sent'].keys()) + list(data['middts_recv'].keys()))

    # produce paired lists for both directions using appropriate sent->recv matching
    middts_to_sim_pairs = {}
    middts_to_sim_lat = {}
    for s in sensors:
        sent = middts_sent.get(s, [])
        recv = sim_recv.get(s, [])
        pairs = match_sent_to_recv(sent, recv)
        middts_to_sim_pairs[s] = pairs
        middts_to_sim_lat[s] = [lat for (recv, lat) in pairs]

    sim_to_middts_pairs = {}
    sim_to_middts_lat = {}
    for s in sensors:
        sent = data['sim_sent'].get(s, [])
        recv = data['middts_recv'].get(s, [])
        pairs = match_sent_to_recv(sent, recv)
        sim_to_middts_pairs[s] = pairs
        sim_to_middts_lat[s] = [lat for (recv, lat) in pairs]

    # Sent/received counts per direction
    sent_counts_m2s = {s: len(middts_sent.get(s, [])) for s in sensors}
    recv_counts_m2s = {s: len(middts_to_sim_lat.get(s, [])) for s in sensors}
    sent_counts_s2m = {s: len(data['sim_sent'].get(s, [])) for s in sensors}
    recv_counts_s2m = {s: len(sim_to_middts_lat.get(s, [])) for s in sensors}

    # Timeliness (T) per direction
    T_table_m2s = {}
    T_table_s2m = {}
    for s in sensors:
        recs_m = middts_to_sim_lat.get(s, [])
        if recs_m:
            on_time = sum(1 for l in recs_m if (l / 1000.0) <= DEADLINE_S)
            T_table_m2s[s] = on_time / float(len(recs_m))
        else:
            T_table_m2s[s] = 0.0

        recs_s = sim_to_middts_lat.get(s, [])
        if recs_s:
            on_time_s = sum(1 for l in recs_s if (l / 1000.0) <= DEADLINE_S)
            T_table_s2m[s] = on_time_s / float(len(recs_s))
        else:
            T_table_s2m[s] = 0.0

    # Reliability (R) per direction
    R_table_m2s = {}
    R_table_s2m = {}
    for s in sensors:
        sentc = sent_counts_m2s.get(s, 0)
        recvc = recv_counts_m2s.get(s, 0)
        R_table_m2s[s] = (recvc / float(sentc)) if sentc > 0 else 0.0

        sentc2 = sent_counts_s2m.get(s, 0)
        recvc2 = recv_counts_s2m.get(s, 0)
        R_table_s2m[s] = (recvc2 / float(sentc2)) if sentc2 > 0 else 0.0

    A_table = compute_availability(data['events_time_by_sensor'], data['start_ts'], data['stop_ts'])

    ts = datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')
    results_dir = out_dir
    os.makedirs(results_dir, exist_ok=True)
    odte_out = os.path.join(results_dir, f'{profile}_odte_{ts}.csv')
    with open(odte_out, 'w', newline='') as f:
        w = csv.writer(f)
        # include capped R and ODTE columns (R capped at 1.0)
        w.writerow(['sensor', 'middts_sent_count', 'middts_to_sim_received_count', 'T_m2s', 'R_m2s', 'R_m2s_capped', 'sim_sent_count', 'sim_to_middts_received_count', 'T_s2m', 'R_s2m', 'R_s2m_capped', 'A', 'ODTE_m2s', 'ODTE_m2s_capped', 'ODTE_s2m', 'ODTE_s2m_capped'])
        for s in sorted(sensors):
            T_m = float(T_table_m2s.get(s, 0.0))
            R_m = float(R_table_m2s.get(s, 0.0))
            T_s = float(T_table_s2m.get(s, 0.0))
            R_s = float(R_table_s2m.get(s, 0.0))
            A = float(A_table.get(s, 0.0)) if s in A_table else 0.0
            # capped reliability (cap at 1.0)
            R_m_c = min(R_m, 1.0)
            R_s_c = min(R_s, 1.0)
            odte_m = T_m * R_m * A
            odte_m_c = T_m * R_m_c * A
            odte_s = T_s * R_s * A
            odte_s_c = T_s * R_s_c * A
            w.writerow([s, sent_counts_m2s.get(s, 0), recv_counts_m2s.get(s, 0), f'{T_m:.6f}', f'{R_m:.6f}', f'{R_m_c:.6f}', sent_counts_s2m.get(s, 0), recv_counts_s2m.get(s, 0), f'{T_s:.6f}', f'{R_s:.6f}', f'{R_s_c:.6f}', f'{A:.6f}', f'{odte_m:.9f}', f'{odte_m_c:.9f}', f'{odte_s:.9f}', f'{odte_s_c:.9f}'])

    # compute global ODTE weighted by sent_count per direction
    total_msgs_m2s = sum(v for v in sent_counts_m2s.values() if v > 0)
    total_msgs_s2m = sum(v for v in sent_counts_s2m.values() if v > 0)

    odte_global_m2s = 0.0
    if total_msgs_m2s > 0:
        weighted_sum_m = 0.0
        for s in sensors:
            sc = sent_counts_m2s.get(s, 0)
            if sc > 0:
                od = float(T_table_m2s.get(s, 0.0) * R_table_m2s.get(s, 0.0) * (A_table.get(s, 0.0) if s in A_table else 0.0))
                weighted_sum_m += od * sc
        odte_global_m2s = weighted_sum_m / float(total_msgs_m2s)

    odte_global_s2m = 0.0
    if total_msgs_s2m > 0:
        weighted_sum_s = 0.0
        for s in sensors:
            sc = sent_counts_s2m.get(s, 0)
            if sc > 0:
                od = float(T_table_s2m.get(s, 0.0) * R_table_s2m.get(s, 0.0) * (A_table.get(s, 0.0) if s in A_table else 0.0))
                weighted_sum_s += od * sc
        odte_global_s2m = weighted_sum_s / float(total_msgs_s2m)

    # combined global (weighted by total sent across both directions)
    total_msgs = total_msgs_m2s + total_msgs_s2m
    if total_msgs > 0:
        odte_global = ((odte_global_m2s * total_msgs_m2s) + (odte_global_s2m * total_msgs_s2m)) / float(total_msgs)
    else:
        odte_global = 0.0

    # per-window aggregation (AVAIL_INTERVAL windows)
    window_out = os.path.join(results_dir, f'{profile}_windows_{ts}.csv')
    with open(window_out, 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['window_start_iso', 'window_index', 'sensors_active', 'total_sent', 'total_received', 'T_mean', 'R_mean', 'A_mean', 'ODTE_mean'])
        start = data['start_ts']
        stop = data['stop_ts']
        if start is None or stop is None:
            # no events
            pass
        else:
            total_windows = int(((stop - start) // AVAIL_INTERVAL) + 1)
            for idx in range(total_windows):
                wstart = start + idx * AVAIL_INTERVAL
                wend = wstart + AVAIL_INTERVAL
                sensors_active = 0
                tot_sent = 0
                tot_recv = 0
                T_vals = []
                R_vals = []
                A_vals = []
                ODTE_vals = []
                # for each sensor compute counts within window
                for s in sensors:
                    # per-window sent/recv for middts->sim
                    sent_ts_m = [t for t in middts_sent.get(s, []) if (t/1000.0) >= wstart and (t/1000.0) < wend]
                    # recv times from simulator side that fall in window
                    recv_ts_m = [t for t in sim_recv.get(s, []) if (t/1000.0) >= wstart and (t/1000.0) < wend]
                    sc_m = len(sent_ts_m)
                    # latencies for middts->sim whose recv is in window
                    lat_pairs_m = match_sent_to_recv(middts_sent.get(s, []), sim_recv.get(s, []))
                    lat_in_window_m = [lat for (recv, lat) in lat_pairs_m if (recv/1000.0) >= wstart and (recv/1000.0) < wend]
                    rc_m = len(lat_in_window_m)

                    # per-window sent/recv for sim->middts
                    sent_ts_s = [t for t in data['sim_sent'].get(s, []) if (t/1000.0) >= wstart and (t/1000.0) < wend]
                    recv_ts_s = [t for t in data['middts_recv'].get(s, []) if (t/1000.0) >= wstart and (t/1000.0) < wend]
                    sc_s = len(sent_ts_s)
                    lat_pairs_s = match_sent_to_recv(data['sim_sent'].get(s, []), data['middts_recv'].get(s, []))
                    lat_in_window_s = [lat for (recv, lat) in lat_pairs_s if (recv/1000.0) >= wstart and (recv/1000.0) < wend]
                    rc_s = len(lat_in_window_s)

                    # mark sensor active if any sent in either direction in window
                    if sc_m > 0 or sc_s > 0:
                        sensors_active += 1
                    tot_sent += (sc_m + sc_s)
                    tot_recv += (rc_m + rc_s)

                    T_s_dir = (sum(1 for l in lat_in_window_m if (l/1000.0) <= DEADLINE_S) / float(rc_m)) if rc_m > 0 else 0.0
                    R_s_dir = (rc_m / float(sc_m)) if sc_m > 0 else 0.0
                    T_m_dir = (sum(1 for l in lat_in_window_s if (l/1000.0) <= DEADLINE_S) / float(rc_s)) if rc_s > 0 else 0.0
                    R_m_dir = (rc_s / float(sc_s)) if sc_s > 0 else 0.0

                    # choose a representative T,R for aggregation: average of both directions where defined
                    # A is sensor availability in the window (based on events presence)
                    A_s = 1.0 if len([t for t in data['events_time_by_sensor'].get(s, []) if (t >= wstart and t < wend)]) > 0 else 0.0

                    # For window aggregation, compute ODTE per direction and append both to lists
                    ODTE_m2s = T_s_dir * R_s_dir * A_s
                    ODTE_s2m = T_m_dir * R_m_dir * A_s
                    # Use mean of defined T values for aggregated T/R lists (fallback to 0)
                    T_vals.append((T_s_dir + T_m_dir) / 2.0)
                    R_vals.append((R_s_dir + R_m_dir) / 2.0)
                    A_vals.append(A_s)
                    ODTE_vals.append((ODTE_m2s + ODTE_s2m) / 2.0)
                T_mean = (sum(T_vals) / len(T_vals)) if T_vals else 0.0
                R_mean = (sum(R_vals) / len(R_vals)) if R_vals else 0.0
                A_mean = (sum(A_vals) / len(A_vals)) if A_vals else 0.0
                ODTE_mean = (sum(ODTE_vals) / len(ODTE_vals)) if ODTE_vals else 0.0
                w.writerow([datetime.fromtimestamp(wstart, tz=timezone.utc).isoformat(), idx, sensors_active, tot_sent, tot_recv, f'{T_mean:.6f}', f'{R_mean:.6f}', f'{A_mean:.6f}', f'{ODTE_mean:.6f}'])

    # ECDF of RTT (middts->sim) aggregated
    all_rtt = []
    for s in middts_to_sim_lat.values():
        all_rtt.extend(s)
    all_rtt_sorted = sorted(all_rtt)
    ecdf_out = os.path.join(results_dir, f'{profile}_ecdf_rtt_{ts}.csv')
    with open(ecdf_out, 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['rtt_ms', 'cdf'])
        n = len(all_rtt_sorted)
        for i, v in enumerate(all_rtt_sorted):
            w.writerow([v, (i+1)/float(n)])


    lat_m_ts = os.path.join(results_dir, f'{profile}_latencia_stats_middts_to_simulator_{ts}.csv')
    with open(lat_m_ts, 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['sensor', 'count', 'mean_ms', 'median_ms', 'min_ms', 'max_ms', 'p95_ms', 'p99_ms', 'p999_ms', 'jitter_ms'])
        for s in sorted(middts_to_sim_lat.keys()):
            stats = stats_from_latencies(middts_to_sim_lat[s])
            w.writerow([s, stats['count'], f"{stats['mean']:.3f}", f"{stats['median']:.3f}", stats['min'], stats['max'], f"{stats['p95']:.3f}", f"{stats['p99']:.3f}", f"{stats['p999']:.3f}", f"{stats['jitter']:.3f}"])

    lat_s_m_ts = os.path.join(results_dir, f'{profile}_latencia_stats_simulator_to_middts_{ts}.csv')
    with open(lat_s_m_ts, 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['sensor', 'count', 'mean_ms', 'median_ms', 'min_ms', 'max_ms', 'p95_ms', 'p99_ms', 'p999_ms', 'jitter_ms'])
        for s in sorted(sim_to_middts_lat.keys()):
            stats = stats_from_latencies(sim_to_middts_lat[s])
            w.writerow([s, stats['count'], f"{stats['mean']:.3f}", f"{stats['median']:.3f}", stats['min'], stats['max'], f"{stats['p95']:.3f}", f"{stats['p99']:.3f}", f"{stats['p999']:.3f}", f"{stats['jitter']:.3f}"])

    print('Generated:', odte_out, lat_m_ts, lat_s_m_ts)


if __name__ == '__main__':
    main()
