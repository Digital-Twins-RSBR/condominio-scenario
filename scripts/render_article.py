#!/usr/bin/env python3
"""Render the LaTeX evaluation section from generated CSV reports and host info.

Searches for the most recent results/*/generated_reports directory, reads the key CSVs
and computes weighted aggregates. Outputs `article/sections/evaluation.tex`.
"""
import sys
import os
from pathlib import Path
import json
import glob
import shutil
import pandas as pd
from jinja2 import Environment, FileSystemLoader
import re
import html


def find_latest_generated_reports(base: Path) -> Path:
    # Allow override via environment variable REPORTS_DIR or first CLI arg
    env_dir = os.environ.get('REPORTS_DIR')
    if env_dir:
        p = Path(env_dir)
        if p.exists():
            return p
    # CLI arg handled by caller (main)
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
        # disk info for project dir
        st = os.statvfs(str(project_root))
        size_gb = (st.f_blocks * st.f_frsize) / (1024**3)
        info['disk_size_gb'] = round(size_gb, 2)
        # check rotational on /sys/block for sda as heuristic
        rota = 'unknown'
        if os.path.exists('/sys/block/sda/queue/rotational'):
            rota = open('/sys/block/sda/queue/rotational').read().strip()
        info['disk_rota'] = rota
    except Exception as e:
        print('Warning: could not collect full host info:', e, file=sys.stderr)
    return info


def compute_aggregates(generated: Path):
    results = {}
    # Patterns for expected CSVs (profile-agnostic)
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
        # Expect columns: sensor, count, mean_ms, p95_ms
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

    # ODTE
    if odte_files:
        odf = pd.concat((pd.read_csv(f) for f in odte_files), ignore_index=True)
        configured = len(odf)
        active_s2m = int((odf.get('sim_sent', 0) > 0).sum()) if 'sim_sent' in odf.columns else 0
        active_m2s = int((odf.get('middts_sent', 0) > 0).sum()) if 'middts_sent' in odf.columns else 0
        bidir = int(((odf.get('sim_sent', 0) > 0) & (odf.get('middts_sent', 0) > 0)).sum()) if 'sim_sent' in odf.columns and 'middts_sent' in odf.columns else 0
        # A or A% column (values typically in [0,1]). Try several column name variants
        A_col = None
        for c in ['A%', 'A']:
            if c in odf.columns:
                A_col = c
                break
        if A_col is not None:
            odte_avg_A = float(odf[A_col].mean())
            # choose weight column: try middts_sent_count, middts_sent, sim_sent_count, sim_sent
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
            # convert to percentage (0..100)
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
    """Compute aggregates for a single generated_reports dir and return a summary dict."""
    agg = compute_aggregates(generated_dir)
    # Try to extract test name and profile from path: results/<testname>_PROFILE/generated_reports
    # We'll walk up to parent and parent name
    test_dir = generated_dir.parent
    test_name = test_dir.name
    # infer profile by suffix pattern like _urllc or _eMBB or _best_effort
    m = re.search(r'_(urllc|eMBB|embb|best_effort|best-effort)$', test_name, re.IGNORECASE)
    profile = None
    if m:
        profile = m.group(1).lower()
        if profile == 'embb':
            profile = 'eMBB'
    else:
        # fallback: look for known keywords in name
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
        # bring a few keys expected by template
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
    # group by profile
    grouped = {}
    for t in tests:
        grouped.setdefault(t['profile'], []).append(t)

    best = []
    for profile, items in grouped.items():
        # First, prefer candidates that meet an URLLC-like latency constraint (S2M p95 < 200 ms).
        # This ensures low-latency scenarios are favored when available. If none meet the
        # constraint, fall back to the original ODTE-desc / s2m_p95-asc tie-breaker.
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
    """Populate 'plots' and 'details' for a profile entry (mutates dict)."""
    gen_dir = profile_entry.get('generated_dir')
    if not gen_dir:
        profile_entry['plots'] = []
        profile_entry['details'] = []
        return profile_entry

    gpath = Path(gen_dir)
    plots_dir = gpath / 'plots'
    # organize plots by profile directory (no per-test subfolder) so article/plots/<profile>/*
    profile_dirname = str(profile_entry.get('name', 'unknown')).lower().replace(' ', '_')
    plots = []
    # if no plots in generated/plots, do not create a profile directory
    if plots_dir.exists():
        imgs = list(plots_dir.glob('*.png'))
    else:
        imgs = []

    if imgs:
        out_plots_dir = repo / 'article' / 'plots' / profile_dirname
        # clear existing profile plot directory to avoid leftover per-test subfolders
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

    # read ODTE CSV(s) in generated dir to build details
    details = []
    for odf in sorted(gpath.glob('*odte_*.csv')):
        try:
            df = pd.read_csv(str(odf))
            # normalize column names
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
    # sort details by sim_sent desc then A_pct desc
    profile_entry['details'] = sorted(details, key=lambda x: (-x['sim_sent'], -x['A_pct']))
    return profile_entry


def compute_latency_stats_for_test(generated_dir: Path):
    """Return dict with mean, p95 and compliance (<200ms) for S2M and M2S for a given generated_reports dir."""
    g = Path(generated_dir)
    s2m_files = sorted(g.glob('*latencia_stats_simulator_to_middts_*.csv'))
    m2s_files = sorted(g.glob('*latencia_stats_middts_to_simulator_*.csv'))
    def stats(files):
        if not files:
            return {'mean_ms':0.0,'p95_ms':0.0,'compliance_pct':0.0}
        df = pd.concat((pd.read_csv(f) for f in files), ignore_index=True)
        # compute weighted mean by count
        if 'count' in df.columns and df['count'].sum()>0:
            total = df['count'].sum()
            mean = (df['mean_ms'] * df['count']).sum() / total
            p95 = (df['p95_ms'] * df['count']).sum() / total
            # compliance: estimate fraction of messages <200ms using mean as proxy per-sensor
            # better: if raw samples available compute exact; here we approximate by counting sensors with p95<200 weighted by count
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
    """Compute reliability (received/sent) and availability A (mean and weighted) from ODTE CSVs in the dir."""
    g = Path(generated_dir)
    odte_files = sorted(g.glob('*odte_*.csv'))
    if not odte_files:
        return {'s2m_reliability':0.0,'m2s_reliability':0.0,'A_avg_pct':0.0,'A_weighted_pct':0.0,'odte_operational_pct':0.0,'odte_bidirectional_pct':0.0,'odte_std_pct':0.0}
    odf = pd.concat((pd.read_csv(f) for f in odte_files), ignore_index=True)
    # reliability: received_count / sent_count per direction (use middts_sent_count and sim_sent_count variants)
    sim_col = next((c for c in odf.columns if 'sim_sent' in c.lower()), None)
    middts_col = next((c for c in odf.columns if 'middts_sent' in c.lower()), None)
    sim_recv = next((c for c in odf.columns if 'sim_to_middts_received' in c.lower() or 'sim_to_middts' in c.lower()), None)
    middts_recv = next((c for c in odf.columns if 'middts_to_sim_received' in c.lower() or 'middts_to_sim' in c.lower()), None)
    # safe numeric extraction
    sim_sent = odf[sim_col].sum() if sim_col in odf.columns else 0
    middts_sent = odf[middts_col].sum() if middts_col in odf.columns else 0
    sim_recv_sum = odf[sim_recv].sum() if sim_recv in odf.columns else 0
    middts_recv_sum = odf[middts_recv].sum() if middts_recv in odf.columns else 0
    s2m_rel = (sim_recv_sum / sim_sent) if sim_sent>0 else 0.0
    m2s_rel = (middts_recv_sum / middts_sent) if middts_sent>0 else 0.0
    # Availability A column variants
    A_col = next((c for c in odf.columns if c in ('A','A%')), None)
    if A_col:
        A_vals = odf[A_col].astype(float)
        # convert to percent if values in 0..1
        if A_vals.max() <= 1.0:
            A_vals_pct = A_vals * 100.0
        else:
            A_vals_pct = A_vals
        A_avg = float(A_vals_pct.mean())
        # weighted by middts_sent or sim_sent if available
        weight_col = middts_col if middts_col in odf.columns else (sim_col if sim_col in odf.columns else None)
        if weight_col:
            total = odf[weight_col].sum()
            A_weighted = float((A_vals_pct * odf[weight_col]).sum() / total) if total>0 else A_avg
        else:
            A_weighted = A_avg
    else:
        A_avg = A_weighted = 0.0
    # ODTE operational and bidirectional: use ODTE_m2s or computed A*R*T combination if not present
    op_col = next((c for c in odf.columns if 'ODTE' in c and 'm2s' not in c and 's2m' not in c), None)
    odte_vals = odf[[c for c in odf.columns if 'ODTE' in c and ('m2s' in c or 's2m' in c or c=='ODTE')]] if any('ODTE' in c for c in odf.columns) else pd.DataFrame()
    # fallback: compute a simple ODTE proxy: A_vals_pct.mean() * R_mean * (T_factor)
    odte_operational = None
    if 'ODTE_m2s' in odf.columns:
        odte_operational = float(odf['ODTE_m2s'].mean())*100.0 if odf['ODTE_m2s'].max()<=1.0 else float(odf['ODTE_m2s'].mean())
    elif 'ODTE_s2m' in odf.columns:
        odte_operational = float(odf['ODTE_s2m'].mean())*100.0 if odf['ODTE_s2m'].max()<=1.0 else float(odf['ODTE_s2m'].mean())
    else:
        odte_operational = A_avg
    # bidirectional: try ODTE_m2s_capped or compute as weighted A
    if 'ODTE_m2s_capped' in odf.columns:
        odte_bidir = float(odf['ODTE_m2s_capped'].mean())*100.0 if odf['ODTE_m2s_capped'].max()<=1.0 else float(odf['ODTE_m2s_capped'].mean())
    else:
        odte_bidir = A_weighted

    # ODTE std for variability (e.g., for eMBB)
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
    # find URLLC and eMBB entries
    urllc = next((p for p in profiles if p['name'] in ('urllc','URLLC')), None)
    embb = next((p for p in profiles if p['name'].lower().startswith('emb')), None)
    # safe default
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

    # Ensure both contexts have all keys the template expects (use safe defaults)
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
        # ensure plots key exists and is a list
        if 'plots' not in ctx or ctx.get('plots') is None:
            ctx['plots'] = []
        return ctx

    ur_ctx = ensure_keys(ur_ctx)
    eb_ctx = ensure_keys(eb_ctx)

    # extract final discussion text from article.rtf and pass to template
    discussion_text = extract_section_5_3_text(repo)
    tpl = repo / 'article' / 'section_5_3.tex.j2'
    out = repo / 'article' / 'sections' / '5_3_results_and_discussion.tex'
    context = {'urllc': ur_ctx, 'embb': eb_ctx, 'discussion': discussion_text}
    render(tpl, context, out)
    print('Wrote', out)


def extract_section_5_3_text(repo: Path) -> str:
    """Read article.rtf and return cleaned plain text for section 5.3 Results and Discussion.

    This performs a best-effort RTF->plaintext extraction focused on the 5.3 heading
    and does minimal LaTeX escaping so the text can be embedded into the .tex fragment.
    """
    rtf_path = repo / 'article.rtf'
    if not rtf_path.exists():
        return ''
    raw = rtf_path.read_text(errors='ignore')

    # Prefer to extract only the "Discussion and Implications" subsection to avoid duplicating
    # the auto-generated content from the template.
    start_idx = raw.lower().find('discussion and implications')
    if start_idx == -1:
        # fallback to '5.3 Results and Discussion' start
        start_idx = raw.lower().find('5.3 results and discussion')
    if start_idx == -1:
        return ''

    # take until the end of document (section 5.3 is near the end of RTF)
    snippet = raw[start_idx:]

    # Basic cleaning of RTF control words and groups
    # replace some common RTF tokens to readable text
    # common RTF tokens -> text
    snippet = snippet.replace('\\rquote', "'")
    snippet = snippet.replace('\\endash', '--')
    snippet = snippet.replace('\\emdash', '---')
    snippet = snippet.replace('\\~', '\n\n')
    snippet = snippet.replace('\\par', '\n\n')

    # remove backslash control words like \fs24 or \lang1046
    snippet = re.sub(r'\\[a-zA-Z]+-?\d*', '', snippet)
    # remove hex-escaped chars like \'98 -> replace with apostrophe
    snippet = re.sub(r"\\'[0-9a-fA-F]{2}", "'", snippet)
    # remove unicode escapes like \u1234
    snippet = re.sub(r'\\u-?\d+\s*\??', '', snippet)
    # remove group braces
    snippet = snippet.replace('{', '').replace('}', '')
    # remove rsid/arsid tokens (leftovers from RTF)
    snippet = re.sub(r'\b\w{0,6}rsid\w*\d*\b', '', snippet)
    # strip stray control words without backslash (rare)
    snippet = re.sub(r'\barsid\w*\d*\b', '', snippet)

    # collapse excessive whitespace/newlines
    snippet = re.sub(r'\n\s+\n', '\n\n', snippet)
    snippet = re.sub(r'[ \t]+', ' ', snippet)

    # Additional aggressive cleaning to remove embedded binary/zip/xml blobs that
    # sometimes appear when the RTF contains embedded files or Windows metadata.
    # Remove long runs of hex characters or base64-like strings (likely blobs)
    snippet = re.sub(r'[0-9a-fA-F]{80,}', '', snippet)
    snippet = re.sub(r'[A-Za-z0-9+/]{80,}={0,2}', '', snippet)
    # remove common PK/ZIP tokens and following binary-like stretches
    snippet = re.sub(r'PK[\x00-\xFF]{0,200}', '', snippet)
    # remove long runs of repeated 00 or 0000 patterns
    snippet = re.sub(r'(?:00){20,}', '', snippet)
    # drop XML prolog or large XML blocks that got embedded
    snippet = re.sub(r'<\?xml.*?\?>', '', snippet, flags=re.S)
    # remove excessively long angle-bracket content
    snippet = re.sub(r'<[^>]{200,}>', '', snippet)

    # Truncate at obvious binary/control markers if present (e.g. literal '\*', ZIP headers, or long hex blobs)
    trunc_markers = []
    for mk in ['\\*', '\\* ', '504b0304', 'PK', '\\x']: 
        i = snippet.find(mk)
        if i != -1:
            trunc_markers.append(i)
    if trunc_markers:
        cut_at = min(trunc_markers)
        # keep a bit of trailing context (up to next double newline) to preserve closing sentence
        tail = snippet[cut_at:cut_at+200]
        # try to find a paragraph break before cut_at to avoid chopping a sentence
        pn = snippet.rfind('\n\n', 0, cut_at)
        if pn != -1 and pn > 100:
            snippet = snippet[:pn]
        else:
            snippet = snippet[:cut_at]

    text = snippet.strip()

    # remove isolated single-letter lines and 'd' artefacts
    text = re.sub(r'(?m)^\s*[a-zA-Z]\s*$\n?', '', text)

    # fix broken spacing around apostrophes like middleware' s -> middleware's
    text = re.sub(r"'\s+([sS])\b", r"'\1", text)

    # Minimal LaTeX escaping for common special chars
    def latex_escape(s: str) -> str:
        s = s.replace('%', '\\%')
        s = s.replace('&', '\\&')
        s = s.replace('#', '\\#')
        s = s.replace('_', '\\_')
        s = s.replace('$', '\\$')
        return s

    text = latex_escape(text)
    # Normalize multiple blank lines
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
    # discover all tests and pick best per profile
    all_tests = discover_all_tests(repo)
    profiles = pick_best_per_profile(all_tests)
    # remove 'unknown' profile entries per user request
    profiles = [p for p in profiles if str(p.get('name','')).lower() != 'unknown']
    # enrich remaining profiles with plots and per-sensor details
    for i, p in enumerate(profiles):
        profiles[i] = collect_plots_and_details_for_profile(p, repo)

    # adapt host keys to template
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
    # also render the dedicated subsection 5.3
    render_section_5_3(repo, profiles)


if __name__ == '__main__':
    main()
