#!/usr/bin/env python3
"""Render the LaTeX evaluation section from generated CSV reports and host info.

This file is the canonical implementation (moved from scripts/render_article.py)
so callers should invoke `scripts/reports/render_article.py` directly.
"""
import sys
import os
from pathlib import Path
import json
import subprocess
import glob
import shutil
import pandas as pd
from jinja2 import Environment, FileSystemLoader
import re
import html


def find_latest_generated_reports(base: Path) -> Path:
    env_dir = os.environ.get('REPORTS_DIR')
    if env_dir:
        p = Path(env_dir)
        if p.exists():
            return p
    candidates = sorted(base.glob('results/*/generated_reports'), key=lambda p: p.stat().st_mtime, reverse=True)
    return candidates[0] if candidates else None


def read_host_info(project_root: Path):
    info = {}
    try:
        info['kernel'] = os.popen('uname -a').read().strip()
        info['cpu_model'] = os.popen("lscpu | grep 'Model name' || true").read().strip().split(':',1)[-1].strip()
        info['cpus'] = int(os.popen('nproc --all').read().strip() or 0)
        mem_kb = int(open('/proc/meminfo').read().split('MemTotal:')[1].split()[0])
        info['total_ram_gb'] = round(mem_kb/1024/1024, 2)
        st = os.statvfs(str(project_root))
        size_gb = (st.f_blocks * st.f_frsize) / (1024**3)
        info['disk_size_gb'] = round(size_gb, 2)
        rota = 'unknown'
        if os.path.exists('/sys/block/sda/queue/rotational'):
            rota = open('/sys/block/sda/queue/rotational').read().strip()
        info['disk_rota'] = rota
    except Exception as e:
        print('Warning: could not collect full host info:', e, file=sys.stderr)
    return info


def compute_aggregates(generated: Path):
    results = {}
    s2m_pattern = str(generated / '*latencia_stats_simulator_to_middts_*.csv')
    m2s_pattern = str(generated / '*latencia_stats_middts_to_simulator_*.csv')
    odte_pattern = str(generated / '*odte_*.csv')

    s2m_files = sorted(glob.glob(s2m_pattern))
    m2s_files = sorted(glob.glob(m2s_pattern))
    odte_files = sorted(glob.glob(odte_pattern))

    def aggregate_latency(files):
        if not files:
            return {'active_sensors': 0, 'total_msgs': 0, 'weighted_mean_ms': 0.0, 'weighted_p95_ms': 0.0}
        df = pd.concat((pd.read_csv(f) for f in files), ignore_index=True)
        df = df[df.get('count', 'count') > 0]
        total_msgs = int(df['count'].sum()) if 'count' in df.columns else 0
        active = int((df['count'] > 0).sum())
        if total_msgs > 0:
            weighted_mean = (df['mean_ms'] * df['count']).sum() / total_msgs
            weighted_p95 = (df['p95_ms'] * df['count']).sum() / total_msgs
        else:
            weighted_mean = weighted_p95 = 0.0
        return {'active_sensors': active, 'total_msgs': total_msgs, 'weighted_mean_ms': weighted_mean, 'weighted_p95_ms': weighted_p95}

    s2m = aggregate_latency(s2m_files)
    m2s = aggregate_latency(m2s_files)

    results.update({
        's2m_active_sensors': s2m['active_sensors'],
        's2m_total_msgs': s2m['total_msgs'],
        's2m_weighted_mean_ms': s2m['weighted_mean_ms'],
        's2m_weighted_p95_ms': s2m['weighted_p95_ms'],
        'm2s_active_sensors': m2s['active_sensors'],
        'm2s_total_msgs': m2s['total_msgs'],
        'm2s_weighted_mean_ms': m2s['weighted_mean_ms'],
        'm2s_weighted_p95_ms': m2s['weighted_p95_ms'],
    })

    if odte_files:
        odf = pd.concat((pd.read_csv(f) for f in odte_files), ignore_index=True)
        configured = len(odf)
        active_s2m = int((odf.get('sim_sent', 0) > 0).sum()) if 'sim_sent' in odf.columns else 0
        active_m2s = int((odf.get('middts_sent', 0) > 0).sum()) if 'middts_sent' in odf.columns else 0
        bidir = int(((odf.get('sim_sent', 0) > 0) & (odf.get('middts_sent', 0) > 0)).sum()) if 'sim_sent' in odf.columns and 'middts_sent' in odf.columns else 0
        A_col = None
        for c in ['A%', 'A']:
            if c in odf.columns:
                A_col = c
                break
        if A_col is not None:
            odte_avg_A = float(odf[A_col].mean())
            weight_col = None
            for wc in ['middts_sent_count', 'middts_sent', 'sim_sent_count', 'sim_sent']:
                if wc in odf.columns:
                    weight_col = wc
                    break
            if weight_col is not None:
                total = odf[weight_col].sum()
                odte_weighted_A = (odf[A_col] * odf[weight_col]).sum() / total if total > 0 else odte_avg_A
            else:
                odte_weighted_A = odte_avg_A
            odte_avg_A = odte_avg_A * 100.0
            odte_weighted_A = odte_weighted_A * 100.0
        else:
            odte_avg_A = odte_weighted_A = 0.0

        results.update({
            'odte_configured_sensors': configured,
            'odte_active_s2m': active_s2m,
            'odte_active_m2s': active_m2s,
            'odte_bidirectional': bidir,
            'odte_avg_A_pct': odte_avg_A,
            'odte_weighted_A_pct': odte_weighted_A,
        })
    else:
        results.update({
            'odte_configured_sensors': 0,
            'odte_active_s2m': 0,
            'odte_active_m2s': 0,
            'odte_bidirectional': 0,
            'odte_avg_A_pct': 0.0,
            'odte_weighted_A_pct': 0.0,
        })

    return results


def compute_test_summary(generated_dir: Path):
    agg = compute_aggregates(generated_dir)
    test_dir = generated_dir.parent
    test_name = test_dir.name
    m = re.search(r'_(urllc|eMBB|embb|best_effort|best-effort)$', test_name, re.IGNORECASE)
    profile = None
    if m:
        profile = m.group(1).lower()
        if profile == 'embb':
            profile = 'eMBB'
    else:
        if 'urllc' in test_name.lower():
            profile = 'urllc'
        elif 'emb' in test_name.lower():
            profile = 'eMBB'
        elif 'best' in test_name.lower():
            profile = 'best_effort'
        else:
            profile = 'unknown'

    summary = {
        'test_name': test_name,
        'profile': profile,
        'generated_dir': str(generated_dir),
        's2m_total_msgs': agg.get('s2m_total_msgs', 0),
        's2m_p95': agg.get('s2m_weighted_p95_ms', 0.0),
        'm2s_p95': agg.get('m2s_weighted_p95_ms', 0.0),
        'odte_weighted_A_pct': agg.get('odte_weighted_A_pct', 0.0),
        'comment': ''
    }
    return summary


def discover_all_tests(base: Path):
    tests = []
    for gen in sorted(base.glob('results/*/generated_reports')):
        tests.append(compute_test_summary(gen))
    return tests


def pick_best_per_profile(tests):
    grouped = {}
    for t in tests:
        grouped.setdefault(t['profile'], []).append(t)

    best = []
    for profile, items in grouped.items():
        try:
            latency_ok = [it for it in items if float(it.get('s2m_p95') or 1e9) < 200.0]
        except Exception:
            latency_ok = []

        if latency_ok:
            items_sorted = sorted(latency_ok, key=lambda x: (-x.get('odte_weighted_A_pct', 0.0), x.get('s2m_p95', float('inf'))))
        else:
            items_sorted = sorted(items, key=lambda x: (-x.get('odte_weighted_A_pct', 0.0), x.get('s2m_p95', float('inf'))))

        chosen = items_sorted[0]
        best.append({
            'name': profile,
            'test_name': chosen['test_name'],
            's2m_total_msgs': chosen.get('s2m_total_msgs', 0),
            's2m_p95': chosen.get('s2m_p95', 0.0),
            'm2s_p95': chosen.get('m2s_p95', 0.0),
            'odte_weighted_A_pct': chosen.get('odte_weighted_A_pct', 0.0),
            'generated_dir': chosen.get('generated_dir', ''),
            'comment': ''
        })
    return best


def collect_plots_and_details_for_profile(profile_entry, repo: Path):
    gen_dir = profile_entry.get('generated_dir')
    if not gen_dir:
        profile_entry['plots'] = []
        profile_entry['details'] = []
        return profile_entry

    gpath = Path(gen_dir)
    plots_dir = gpath / 'plots'
    profile_dirname = str(profile_entry.get('name', 'unknown')).lower().replace(' ', '_')
    plots = []
    if plots_dir.exists():
        imgs = list(plots_dir.glob('*.png'))
    else:
        imgs = []

    if imgs:
        out_plots_dir = repo / 'article' / 'plots' / profile_dirname
        if out_plots_dir.exists():
            try:
                shutil.rmtree(out_plots_dir)
            except Exception:
                pass
        out_plots_dir.mkdir(parents=True, exist_ok=True)
        for f in imgs:
            dest = out_plots_dir / f.name
            try:
                shutil.copy2(f, dest)
                plots.append({'path': str(Path('article') / 'plots' / profile_dirname / f.name), 'name': f.name})
            except Exception:
                pass

    details = []
    for odf in sorted(gpath.glob('*odte_*.csv')):
        try:
            df = pd.read_csv(str(odf))
            sim_col = None
            middts_col = None
            A_col = None
            for c in df.columns:
                lc = c.lower()
                if 'sim_sent' in lc:
                    sim_col = c
                if 'middts_sent' in lc or 'middts_sent_count' in lc:
                    middts_col = c
                if c in ('A', 'A%'):
                    A_col = c
            for _, r in df.iterrows():
                details.append({
                    'sensor': r.get('sensor', ''),
                    'sim_sent': int(r.get(sim_col, 0) or 0),
                    'middts_sent': int(r.get(middts_col, 0) or 0),
                    'A_pct': float(r.get(A_col, 0.0) or 0.0) * 100.0,
                    'ODTE_m2s_capped': float(r.get('ODTE_m2s_capped', 0.0) or 0.0)
                })
        except Exception:
            continue

    profile_entry['plots'] = plots
    profile_entry['details'] = sorted(details, key=lambda x: (-x['sim_sent'], -x['A_pct']))
    return profile_entry


def snapshot_generated_reports(profiles, repo: Path):
    base_out = repo / 'article' / 'data'
    base_out.mkdir(parents=True, exist_ok=True)
    for p in profiles:
        gen_dir = p.get('generated_dir')
        if not gen_dir:
            print(f"No generated_dir for profile {p.get('name')}, skipping snapshot")
            continue
        src = Path(gen_dir)
        if not src.exists():
            print(f"Generated reports dir not found: {src}, skipping")
            continue
        prof_name = str(p.get('name','unknown')).lower().replace(' ', '_')
        test_name = str(p.get('test_name','unknown')).replace(' ', '_')
        dst = base_out / prof_name / test_name
        if dst.exists():
            try:
                shutil.rmtree(dst)
            except Exception as e:
                print('Warning: could not remove existing snapshot', dst, e)
        try:
            shutil.copytree(src, dst)
            print(f'Copied generated reports for {prof_name} -> {dst}')
        except Exception as e:
            print(f'Warning: failed to copy {src} to {dst}:', e)


def run_all_plots(repo: Path):
    script = repo / 'scripts' / 'plots' / 'generate_all_plots.sh'
    if not script.exists():
        print('Plot generator script not found:', script)
        return
    try:
        print('Running plot generator...')
        subprocess.run(['sh', str(script)], cwd=str(repo), check=False)
    except Exception as e:
        print('Warning: plot generation failed:', e)


def run_topology_generators(repo: Path):
    topo_out = repo / 'topology_output'
    topo_out.mkdir(parents=True, exist_ok=True)
    plots_dir = repo / 'article' / 'plots'
    plots_dir.mkdir(parents=True, exist_ok=True)

    viz = repo / 'services' / 'topology' / 'topology_visualizer.py'
    if viz.exists():
        try:
            print('Running topology_visualizer.py...')
            subprocess.run([sys.executable, str(viz), '--sims', '6', '--output', str(topo_out), '--filename', 'condominio_topology'], cwd=str(repo), check=False)
        except Exception as e:
            print('Warning: topology_visualizer failed:', e)

    live = repo / 'services' / 'topology' / 'live_topology_capture.py'
    if live.exists():
        try:
            print('Running live_topology_capture.py --report...')
            subprocess.run([sys.executable, str(live), '--report', '--output', str(topo_out)], cwd=str(repo), check=False)
        except Exception as e:
            print('Warning: live_topology_capture failed:', e)

    for fname in ('condominio_topology_main.png', 'condominio_topology_hierarchical.png'):
        f = topo_out / fname
        if f.exists():
            try:
                shutil.copy2(f, plots_dir / f.name)
                print('Copied topology image to article/plots/', f.name)
            except Exception as e:
                print('Warning: failed to copy topology image', f, e)


def compute_latency_stats_for_test(generated_dir: Path):
    g = Path(generated_dir)
    s2m_files = sorted(g.glob('*latencia_stats_simulator_to_middts_*.csv'))
    m2s_files = sorted(g.glob('*latencia_stats_middts_to_simulator_*.csv'))
    def stats(files):
        if not files:
            return {'mean_ms':0.0,'p95_ms':0.0,'compliance_pct':0.0}
        df = pd.concat((pd.read_csv(f) for f in files), ignore_index=True)
        if 'count' in df.columns and df['count'].sum()>0:
            total = df['count'].sum()
            mean = (df['mean_ms'] * df['count']).sum() / total
            p95 = (df['p95_ms'] * df['count']).sum() / total
            compliant = df[df['p95_ms'] < 200]
            compliance_pct = (compliant['count'].sum() / total)*100.0
        else:
            mean = df['mean_ms'].mean() if 'mean_ms' in df.columns else 0.0
            p95 = df['p95_ms'].mean() if 'p95_ms' in df.columns else 0.0
            compliance_pct = 0.0
        return {'mean_ms':mean,'p95_ms':p95,'compliance_pct':compliance_pct}
    s2m = stats(s2m_files)
    m2s = stats(m2s_files)
    return {'s2m_mean_ms':s2m['mean_ms'],'s2m_p95':s2m['p95_ms'],'s2m_compliance_pct':s2m['compliance_pct'],
            'm2s_mean_ms':m2s['mean_ms'],'m2s_p95':m2s['p95_ms'],'m2s_compliance_pct':m2s['compliance_pct']}


def compute_reliability_availability_for_test(generated_dir: Path):
    g = Path(generated_dir)
    odte_files = sorted(g.glob('*odte_*.csv'))
    if not odte_files:
        return {'s2m_reliability':0.0,'m2s_reliability':0.0,'A_avg_pct':0.0,'A_weighted_pct':0.0,'odte_operational_pct':0.0,'odte_bidirectional_pct':0.0,'odte_std_pct':0.0}
    odf = pd.concat((pd.read_csv(f) for f in odte_files), ignore_index=True)
    sim_col = next((c for c in odf.columns if 'sim_sent' in c.lower()), None)
    middts_col = next((c for c in odf.columns if 'middts_sent' in c.lower()), None)
    sim_recv = next((c for c in odf.columns if 'sim_to_middts_received' in c.lower() or 'sim_to_middts' in c.lower()), None)
    middts_recv = next((c for c in odf.columns if 'middts_to_sim_received' in c.lower() or 'middts_to_sim' in c.lower()), None)
    sim_sent = odf[sim_col].sum() if sim_col in odf.columns else 0
    middts_sent = odf[middts_col].sum() if middts_col in odf.columns else 0
    sim_recv_sum = odf[sim_recv].sum() if sim_recv in odf.columns else 0
    middts_recv_sum = odf[middts_recv].sum() if middts_recv in odf.columns else 0
    s2m_rel = (sim_recv_sum / sim_sent) if sim_sent>0 else 0.0
    m2s_rel = (middts_recv_sum / middts_sent) if middts_sent>0 else 0.0
    A_col = next((c for c in odf.columns if c in ('A','A%')), None)
    if A_col:
        A_vals = odf[A_col].astype(float)
        if A_vals.max() <= 1.0:
            A_vals_pct = A_vals * 100.0
        else:
            A_vals_pct = A_vals
        A_avg = float(A_vals_pct.mean())
        weight_col = middts_col if middts_col in odf.columns else (sim_col if sim_col in odf.columns else None)
        if weight_col:
            total = odf[weight_col].sum()
            A_weighted = float((A_vals_pct * odf[weight_col]).sum() / total) if total>0 else A_avg
        else:
            A_weighted = A_avg
    else:
        A_avg = A_weighted = 0.0
    op_col = next((c for c in odf.columns if 'ODTE' in c and 'm2s' not in c and 's2m' not in c), None)
    odte_vals = odf[[c for c in odf.columns if 'ODTE' in c and ('m2s' in c or 's2m' in c or c=='ODTE')]] if any('ODTE' in c for c in odf.columns) else pd.DataFrame()
    odte_operational = None
    if 'ODTE_m2s' in odf.columns:
        odte_operational = float(odf['ODTE_m2s'].mean())*100.0 if odf['ODTE_m2s'].max()<=1.0 else float(odf['ODTE_m2s'].mean())
    elif 'ODTE_s2m' in odf.columns:
        odte_operational = float(odf['ODTE_s2m'].mean())*100.0 if odf['ODTE_s2m'].max()<=1.0 else float(odf['ODTE_s2m'].mean())
    else:
        odte_operational = A_avg
    if 'ODTE_m2s_capped' in odf.columns:
        odte_bidir = float(odf['ODTE_m2s_capped'].mean())*100.0 if odf['ODTE_m2s_capped'].max()<=1.0 else float(odf['ODTE_m2s_capped'].mean())
    else:
        odte_bidir = A_weighted
    odte_std = 0.0
    if 'ODTE_m2s' in odf.columns:
        vals = odf['ODTE_m2s'].astype(float)
        if vals.max()<=1.0:
            odte_std = float(vals.std()*100.0)
        else:
            odte_std = float(vals.std())

    return {'s2m_reliability': s2m_rel, 'm2s_reliability': m2s_rel, 'A_avg_pct': A_avg, 'A_weighted_pct': A_weighted,
            'odte_operational_pct': odte_operational, 'odte_bidirectional_pct': odte_bidir, 'odte_std_pct': odte_std}


def render_section_5_3(repo: Path, profiles):
    urllc = next((p for p in profiles if p['name'] in ('urllc','URLLC')), None)
    embb = next((p for p in profiles if p['name'].lower().startswith('emb')), None)
    ur = {'test_name': 'n/a', 'plots': []}
    eb = {'test_name': 'n/a', 'plots': []}
    if urllc:
        ur = urllc
        lat = compute_latency_stats_for_test(ur.get('generated_dir',''))
        rel = compute_reliability_availability_for_test(ur.get('generated_dir',''))
        ur_ctx = {
            'test_name': ur['test_name'],
            'plots': ur.get('plots',[]),
            's2m_mean_ms': lat['s2m_mean_ms'], 's2m_p95': lat['s2m_p95'], 's2m_compliance_pct': lat['s2m_compliance_pct'],
            'm2s_mean_ms': lat['m2s_mean_ms'], 'm2s_p95': lat['m2s_p95'], 'm2s_compliance_pct': lat['m2s_compliance_pct'],
            's2m_reliability': rel['s2m_reliability'], 'm2s_reliability': rel['m2s_reliability'],
            'A_avg_pct': rel['A_avg_pct'], 'A_weighted_pct': rel['A_weighted_pct'],
            'odte_operational_pct': rel['odte_operational_pct'], 'odte_bidirectional_pct': rel['odte_bidirectional_pct']
        }
    else:
        ur_ctx = ur
    if embb:
        eb = embb
        lat = compute_latency_stats_for_test(eb.get('generated_dir',''))
        rel = compute_reliability_availability_for_test(eb.get('generated_dir',''))
        eb_ctx = {
            'test_name': eb['test_name'],
            'plots': eb.get('plots',[]),
            's2m_mean_ms': lat['s2m_mean_ms'], 's2m_p95': lat['s2m_p95'], 's2m_compliance_pct': lat['s2m_compliance_pct'],
            'm2s_mean_ms': lat['m2s_mean_ms'], 'm2s_p95': lat['m2s_p95'], 'm2s_compliance_pct': lat['m2s_compliance_pct'],
            's2m_reliability': rel['s2m_reliability'], 'm2s_reliability': rel['m2s_reliability'],
            'A_avg_pct': rel['A_avg_pct'], 'A_weighted_pct': rel['A_weighted_pct'],
            'odte_operational_pct': rel['odte_operational_pct'], 'odte_std_pct': rel['odte_std_pct']
        }
    else:
        eb_ctx = eb

    def ensure_keys(ctx: dict):
        defaults = {
            'test_name': 'n/a', 'plots': [],
            's2m_mean_ms': 0.0, 's2m_p95': 0.0, 's2m_compliance_pct': 0.0,
            'm2s_mean_ms': 0.0, 'm2s_p95': 0.0, 'm2s_compliance_pct': 0.0,
            's2m_reliability': 0.0, 'm2s_reliability': 0.0,
            'A_avg_pct': 0.0, 'A_weighted_pct': 0.0,
            'odte_operational_pct': 0.0, 'odte_bidirectional_pct': 0.0, 'odte_std_pct': 0.0,
        }
        for k, v in defaults.items():
            if k not in ctx:
                ctx[k] = v
        if 'plots' not in ctx or ctx.get('plots') is None:
            ctx['plots'] = []
        return ctx

    ur_ctx = ensure_keys(ur_ctx)
    eb_ctx = ensure_keys(eb_ctx)

    discussion_text = extract_section_5_3_text(repo)
    tpl = repo / 'article' / 'section_5_3.tex.j2'
    out = repo / 'article' / 'sections' / '5_3_results_and_discussion.tex'
    context = {'urllc': ur_ctx, 'embb': eb_ctx, 'discussion': discussion_text}
    render(tpl, context, out)
    print('Wrote', out)


def extract_section_5_3_text(repo: Path) -> str:
    rtf_path = repo / 'article/article.rtf'
    if not rtf_path.exists():
        return ''
    raw = rtf_path.read_text(errors='ignore')
    start_idx = raw.lower().find('discussion and implications')
    if start_idx == -1:
        start_idx = raw.lower().find('5.3 results and discussion')
    if start_idx == -1:
        return ''
    snippet = raw[start_idx:]
    snippet = snippet.replace('\\rquote', "'")
    snippet = snippet.replace('\\endash', '--')
    snippet = snippet.replace('\\emdash', '---')
    snippet = snippet.replace('\\~', '\n\n')
    snippet = snippet.replace('\\par', '\n\n')
    snippet = re.sub(r'\\[a-zA-Z]+-?\d*', '', snippet)
    snippet = re.sub(r"\\'[0-9a-fA-F]{2}", "'", snippet)
    snippet = re.sub(r'\\u-?\d+\s*\??', '', snippet)
    snippet = snippet.replace('{', '').replace('}', '')
    snippet = re.sub(r'\b\w{0,6}rsid\w*\d*\b', '', snippet)
    snippet = re.sub(r'\barsid\w*\d*\b', '', snippet)
    snippet = re.sub(r'\n\s+\n', '\n\n', snippet)
    snippet = re.sub(r'[ \t]+', ' ', snippet)
    snippet = re.sub(r'[0-9a-fA-F]{80,}', '', snippet)
    snippet = re.sub(r'[A-Za-z0-9+/]{80,}={0,2}', '', snippet)
    snippet = re.sub(r'PK[\x00-\xFF]{0,200}', '', snippet)
    snippet = re.sub(r'(?:00){20,}', '', snippet)
    snippet = re.sub(r'<\?xml.*?\?>', '', snippet, flags=re.S)
    snippet = re.sub(r'<[^>]{200,}>', '', snippet)
    trunc_markers = []
    for mk in ['\\*', '\\* ', '504b0304', 'PK', '\\x']:
        i = snippet.find(mk)
        if i != -1:
            trunc_markers.append(i)
    if trunc_markers:
        cut_at = min(trunc_markers)
        pn = snippet.rfind('\n\n', 0, cut_at)
        if pn != -1 and pn > 100:
            snippet = snippet[:pn]
        else:
            snippet = snippet[:cut_at]
    text = snippet.strip()
    text = re.sub(r'(?m)^\s*[a-zA-Z]\s*$\n?', '', text)
    text = re.sub(r"'\s+([sS])\b", r"'\1", text)
    def latex_escape(s: str) -> str:
        s = s.replace('%', '\\%')
        s = s.replace('&', '\\&')
        s = s.replace('#', '\\#')
        s = s.replace('_', '\\_')
        s = s.replace('$', '\\$')
        return s
    text = latex_escape(text)
    text = re.sub(r'(\n\s*){3,}', '\n\n', text)
    return text


def render(template_path: Path, context: dict, out_path: Path):
    env = Environment(loader=FileSystemLoader(str(template_path.parent)), autoescape=False)
    tpl = env.get_template(template_path.name)
    out = tpl.render(**context)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(out)


def main():
    repo = Path(__file__).resolve().parents[1]
    generated = find_latest_generated_reports(repo)
    if generated is None:
        print('No generated_reports directory found under results/*', file=sys.stderr)
        sys.exit(2)

    host = read_host_info(repo)
    agg = compute_aggregates(generated)
    all_tests = discover_all_tests(repo)
    profiles = pick_best_per_profile(all_tests)
    profiles = [p for p in profiles if str(p.get('name','')).lower() != 'unknown']
    for i, p in enumerate(profiles):
        profiles[i] = collect_plots_and_details_for_profile(p, repo)

    host_ctx = {
        'kernel': host.get('kernel', 'unknown'),
        'cpu_model': host.get('cpu_model', 'unknown'),
        'cpus': host.get('cpus', 0),
        'total_ram_gb': host.get('total_ram_gb', 0.0),
        'disk': {
            'size_gb': host.get('disk_size_gb', 0.0),
            'rota': host.get('disk_rota', 'unknown')
        }
    }

    context = {
        'host': host_ctx,
        'disk': host_ctx.get('disk', {}),
        'results': agg,
        'profiles': profiles
    }

    tpl = repo / 'article' / 'article.tex.j2'
    out = repo / 'article' / 'sections' / 'evaluation.tex'
    render(tpl, context, out)
    print('Wrote', out)
    render_section_5_3(repo, profiles)


if __name__ == '__main__':
    main()
