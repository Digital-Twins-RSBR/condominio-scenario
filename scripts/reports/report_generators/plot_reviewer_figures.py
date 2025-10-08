#!/usr/bin/env python3
"""Canonical: Generate reviewer-friendly figures from experiment CSV exports.

This is the moved implementation previously at `scripts/plot_reviewer_figures.py`.
"""
import os
import sys
import glob
import pandas as pd
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from shutil import copyfile
from matplotlib import image as mpimg

try:
    from services.topology.topology_visualizer import TopologyVisualizer
except Exception:
    TopologyVisualizer = None

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
RESULTS_GLOB = os.path.join(ROOT, 'results', 'test_*')
PLOTS_DIR = os.path.join(ROOT, 'scripts', 'reports', 'article', 'plots')
os.makedirs(PLOTS_DIR, exist_ok=True)

PROFILES = ['urllc', 'embb', 'best_effort']

def find_latest_test(profile):
    pattern = os.path.join(ROOT, 'results', f'test_*_{profile}')
    dirs = glob.glob(pattern)
    if not dirs:
        return None
    dirs.sort()
    return dirs[-1]

def read_raw_csv(test_dir):
    candidates = glob.glob(os.path.join(test_dir, '*.csv'))
    for c in candidates:
        if os.path.basename(c).startswith('generated_reports'):
            continue
        return c
    return candidates[0] if candidates else None

def extract_samples_from_raw(csv_path):
    samples = {'S2M': [], 'M2S': []}
    try:
        with open(csv_path, 'r') as f:
            lines = f.readlines()
        header_idx = None
        header_cols = None
        for i, line in enumerate(lines):
            if 'direction' in line and ('sensor' in line or 'device' in line):
                header_idx = i
                header_cols = [c.strip() for c in line.strip().lstrip(',').split(',')]
                break
        if header_idx is None:
            return samples
        data_lines = []
        for ln in lines[header_idx+1:]:
            if 'direction' in ln and ('sensor' in ln or 'device' in ln):
                break
            if ln.strip() == '':
                continue
            data_lines.append(ln)
        if not data_lines:
            return samples
        from io import StringIO
        data_csv = ''.join(data_lines)
        df = pd.read_csv(StringIO(data_csv), names=header_cols, header=None, dtype=str, engine='python')
        col_map = {c.lower(): c for c in df.columns}
        measurement_col = None
        field_col = None
        value_col = None
        direction_col = None
        sensor_col = None
        for k, v in col_map.items():
            if 'measurement' in k:
                measurement_col = v
            if 'field' == k or '_field' in k:
                field_col = v
            if 'value' in k or '_value' in k:
                value_col = v
            if 'direction' in k:
                direction_col = v
            if 'sensor' in k or 'device' in k:
                sensor_col = v
        if measurement_col is None or field_col is None or value_col is None or direction_col is None:
            return samples
        lat_df = df[df[measurement_col].fillna('').str.contains('latency', na=False)]
        if lat_df.empty:
            return samples
        numeric = pd.to_numeric(lat_df[value_col], errors='coerce')
        if numeric.notna().sum() > 0:
            lat_df['_numval'] = numeric
            for _, row in lat_df.iterrows():
                d = str(row.get(direction_col, '') or '')
                val = row.get('_numval')
                if pd.isna(val):
                    continue
                v = float(val)
                if v > 1e10:
                    continue
                if v > 1e6:
                    continue
                if 'S2M' in d:
                    samples['S2M'].append(v)
                elif 'M2S' in d:
                    samples['M2S'].append(v)
    except Exception:
        return {'S2M': [], 'M2S': []}
    return samples

def read_ecdf_csv(test_dir, profile):
    pattern = os.path.join(test_dir, 'generated_reports', f'{profile}_ecdf_rtt_*.csv')
    matches = glob.glob(pattern)
    if not matches:
        return None
    matches.sort()
    try:
        df = pd.read_csv(matches[-1])
        if df.shape[0] == 0:
            return None
        return df
    except Exception:
        return None

def read_odte_csv(test_dir, profile):
    pattern = os.path.join(test_dir, 'generated_reports', f'{profile}_odte_*.csv')
    matches = glob.glob(pattern)
    if not matches:
        return None
    matches.sort()
    try:
        df = pd.read_csv(matches[-1])
        return df
    except Exception:
        return None

def plot_cdfs(all_samples):
    fig, ax = plt.subplots(1,1, figsize=(6,4))
    prop_cycle = plt.rcParams.get('axes.prop_cycle')
    colors = prop_cycle.by_key().get('color', [])
    profiles = list(all_samples.keys())
    for i, profile in enumerate(profiles):
        dirs = all_samples[profile]
        color = colors[i % len(colors)] if colors else None
        s2m = np.array(dirs.get('S2M', []))
        if s2m.size:
            x = np.sort(s2m)
            y = np.arange(1, len(x)+1)/len(x)
            ax.plot(x, y, label=f'{profile} S2M', color=color, linestyle='-')
        m2s = np.array(dirs.get('M2S', []))
        if m2s.size:
            x = np.sort(m2s)
            y = np.arange(1, len(x)+1)/len(x)
            ax.plot(x, y, label=f'{profile} M2S', color=color, linestyle='--')
        rtt = None
        if 'RTT' in dirs and dirs.get('RTT') is not None:
            rtt = np.array(dirs.get('RTT', []))
        elif '__ecdf_samples' in dirs and dirs.get('__ecdf_samples') is not None:
            rtt = np.array(dirs.get('__ecdf_samples', []))
        if rtt is not None and rtt.size:
            x = np.sort(rtt)
            y = np.arange(1, len(x)+1)/len(x)
            ax.plot(x, y, label=f'{profile} RTT', color=color, linestyle='-.')
    ax.axvline(200, color='k', linestyle=':', linewidth=1)
    ax.text(200*1.05, 0.1, '200 ms', rotation=90, va='bottom')
    ax.set_xlabel('RTT (ms)')
    ax.set_ylabel('ECDF')
    ax.set_xscale('log')
    ax.set_xlim(left=1)
    ax.legend(fontsize='small')
    fig.tight_layout()
    out_png = os.path.join(PLOTS_DIR, 'fig6_cdfs.png')
    fig.savefig(out_png, dpi=200)
    plt.close(fig)

def plot_boxplots(all_samples):
    data = []
    labels = []
    for profile, dirs in all_samples.items():
        for dname in ['S2M', 'M2S', 'RTT']:
            vals = dirs.get(dname, [])
            if vals is None:
                continue
            if isinstance(vals, (list, tuple, np.ndarray)) and len(vals) >= 3:
                data.append(vals)
                labels.append(f'{profile}\n{dname}')
    if not data:
        return
    fig, ax = plt.subplots(1,1, figsize=(8,4))
    ax.boxplot(data, labels=labels, showfliers=False)
    ax.set_yscale('log')
    ax.set_ylabel('RTT (ms)')
    fig.tight_layout()
    out_png = os.path.join(PLOTS_DIR, 'fig6_boxplots.png')
    fig.savefig(out_png, dpi=200)
    plt.close(fig)

def plot_odte(odte_stats):
    profiles = []
    means = []
    medians = []
    for p, s in odte_stats.items():
        profiles.append(p)
        means.append(s.get('mean_A', np.nan))
        medians.append(s.get('median_A', np.nan))
    x = np.arange(len(profiles))
    width = 0.35
    fig, ax = plt.subplots(figsize=(6,3))
    ax.bar(x - width/2, means, width, label='mean A%')
    ax.bar(x + width/2, medians, width, label='median A%')
    ax.set_xticks(x)
    ax.set_xticklabels(profiles)
    ax.set_ylabel('A% (ODTE)')
    ax.set_ylim(0,100)
    ax.legend()
    fig.tight_layout()
    out_png = os.path.join(PLOTS_DIR, 'fig7_odte_bars.png')
    fig.savefig(out_png, dpi=200)
    plt.close(fig)

def create_topology_placeholder():
    fig, ax = plt.subplots(figsize=(6,4))
    ax.axis('off')
    ax.text(0.5,0.6,'Topology Diagram Placeholder', ha='center', fontsize=14)
    ax.text(0.5,0.45,'Containers: simulators, middts, thingsboard, influxdb', ha='center')
    ax.text(0.5,0.35,'Link conditioning per profile: see scripts/slice/apply_slice.sh', ha='center')
    fig.tight_layout()
    out_png = os.path.join(PLOTS_DIR, 'fig5_topology_diagram.png')
    fig.savefig(out_png, dpi=200)
    plt.close(fig)

def create_topology_real(num_sims=6):
    if TopologyVisualizer is None:
        create_topology_placeholder()
        return
    try:
        outdir = os.path.join(ROOT, 'topology_output')
        viz = TopologyVisualizer(num_sims=num_sims, output_dir=outdir)
        outputs = viz.export_to_formats(base_filename='condominio_topology')
        png_candidate = next((p for p in outputs if p.endswith('_main.png')), None)
        hier_png = next((p for p in outputs if p.endswith('_hierarchical.png')), None)
        if png_candidate and os.path.exists(png_candidate):
            dst_png = os.path.join(PLOTS_DIR, 'fig5_topology_diagram.png')
            copyfile(png_candidate, dst_png)
            if hier_png and os.path.exists(hier_png):
                dst_hier = os.path.join(PLOTS_DIR, 'fig5_topology_diagram_hierarchical.png')
                copyfile(hier_png, dst_hier)
            return
    except Exception as e:
        print('Topology visualizer failed:', e)
    create_topology_placeholder()

def main():
    all_samples = {}
    odte_stats = {}
    for profile in PROFILES:
        test_dir = find_latest_test(profile)
        if not test_dir:
            print('no test for', profile)
            continue
        raw = read_raw_csv(test_dir)
        samples = {'S2M': [], 'M2S': []}
        if raw:
            s = extract_samples_from_raw(raw)
            for k in s:
                vals = np.array(s[k], dtype=float)
                if vals.size and vals.mean() > 1e3:
                    vals = vals / 1e3
                samples[k] = vals.tolist()
        ecdf = read_ecdf_csv(test_dir, profile)
        if ecdf is not None and 'rtt_ms' in ecdf.columns:
            try:
                x = ecdf['rtt_ms'].astype(float).values
                c = ecdf['cdf'].astype(float).values
                mask = (~np.isnan(x)) & (~np.isnan(c))
                x = x[mask]
                c = c[mask]
                if x.size and c.size:
                    order = np.argsort(c)
                    c = c[order]
                    x = x[order]
                    probs = np.linspace(0.0005, 0.9995, 2000)
                    try:
                        samples_recon = np.interp(probs, c, x)
                        samples['__ecdf_samples'] = samples_recon.tolist()
                    except Exception:
                        pass
            except Exception:
                pass
        odte = read_odte_csv(test_dir, profile)
        if odte is not None and 'A' in odte.columns:
            meanA = odte['A'].mean()*100 if odte['A'].mean() <= 1.0 else odte['A'].mean()
            medianA = odte['A'].median()*100 if odte['A'].median() <=1.0 else odte['A'].median()
            odte_stats[profile] = {'mean_A': meanA, 'median_A': medianA}
        else:
            odte_stats[profile] = {'mean_A': np.nan, 'median_A': np.nan}
        all_samples[profile] = samples
    print('Plotting CDFs...')
    plot_cdfs(all_samples)
    print('Plotting boxplots...')
    plot_boxplots(all_samples)
    print('Plotting ODTE bars...')
    plot_odte(odte_stats)
    print('Creating topology placeholder...')
    create_topology_real(num_sims=6)
    print('Plots saved under', PLOTS_DIR)

if __name__ == '__main__':
    main()
