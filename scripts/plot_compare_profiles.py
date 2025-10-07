#!/usr/bin/env python3
"""Generate comparative plots for URLLC/eMBB/best_effort using the latest summaries.
Saves outputs to article/plots/compare_profiles.{png,pdf,csv}.
"""
import os
import glob
import math
import csv
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import pandas as pd

RESULTS_DIR = "results"
PROFILES = ["urllc", "embb", "best_effort"]
OUT_DIR = "article/plots"
os.makedirs(OUT_DIR, exist_ok=True)


def read_summary(path):
    d = {}
    try:
        with open(path, "r") as f:
            for ln in f:
                ln = ln.strip()
                if not ln or ":" not in ln:
                    continue
                k, v = ln.split(":", 1)
                k = k.strip()
                v = v.strip()
                # try parse numeric
                try:
                    if v.replace('.', '', 1).isdigit():
                        if "." in v:
                            d[k] = float(v)
                        else:
                            d[k] = int(v)
                    else:
                        # handle floats with leading/trailing spaces or scientific notation
                        d[k] = float(v)
                except Exception:
                    d[k] = v
    except FileNotFoundError:
        pass
    return d


def find_latest_summary(profile):
    pattern = os.path.join(RESULTS_DIR, "test_*_{}".format(profile))
    dirs = sorted(glob.glob(pattern))
    if not dirs:
        return None, None
    latest = dirs[-1]
    # find summary file inside
    summary_files = glob.glob(os.path.join(latest, "summary_*"))
    if not summary_files:
        return latest, None
    return latest, summary_files[-1]


def collect():
    rows = {}
    for p in PROFILES:
        ddir, sf = find_latest_summary(p)
        if sf is None:
            rows[p] = {}
            continue
        vals = read_summary(sf)
        rows[p] = vals
    return rows


def build_dataframe(rows):
    # keys we care about
    keys = [
        "median_S2M_ms", "median_M2S_ms", "P95_ms", "cdf_le_200",
        "mean_S2M_ms", "mean_M2S_ms",
        "mean_R", "median_R", "mean_A", "median_A",
        # Timeless indicator (T) - can be present in summary as mean_T / median_T
        "mean_T", "median_T",
        "S2M_total_count", "M2S_total_count", "median_overall_ms"
    ]
    df = pd.DataFrame(index=PROFILES, columns=keys, dtype=float)
    for p in PROFILES:
        r = rows.get(p, {}) or {}
        for k in keys:
            try:
                df.at[p, k] = float(r.get(k, float('nan')))
            except Exception:
                df.at[p, k] = float('nan')
    return df


def write_csv(df, path):
    path_tmp = path
    with open(path_tmp, 'w', newline='') as f:
        w = csv.writer(f)
        cols = ['profile'] + list(df.columns)
        w.writerow(cols)
        for p in df.index:
            row = [p]
            for c in df.columns:
                v = df.at[p, c]
                if isinstance(v, float) and (pd.isna(v) or math.isnan(v)):
                    row.append('')
                else:
                    row.append(v)
            w.writerow(row)


def plot(df):
    out_png = os.path.join(OUT_DIR, "compare_profiles.png")
    out_csv = os.path.join(OUT_DIR, "compare_profiles.csv")
    # per-panel outputs
    out_latency_png = os.path.join(OUT_DIR, "compare_profiles_latency.png")
    out_cdf200_png = os.path.join(OUT_DIR, "compare_profiles_cdf200.png")
    out_ra_t_png = os.path.join(OUT_DIR, "compare_profiles_ra_t.png")

    # make the figure wider to leave room for plots; legend will be saved separately
    fig, axes = plt.subplots(1, 3, figsize=(18,5))
    fig.suptitle("Profiles comparison: URLLC / eMBB / best_effort (includes Timeless)", fontsize=14)

    # Latency plot (log scale) - median S2M and M2S
    ax = axes[0]
    w = 0.35
    x = list(range(len(df.index)))
    m_s2m = df["median_S2M_ms"].values
    m_m2s = df["median_M2S_ms"].values
    ax.bar([i - w/2 for i in x], m_s2m, width=w, label="median S2M (ms)")
    ax.bar([i + w/2 for i in x], m_m2s, width=w, label="median M2S (ms)")
    ax.set_xticks(x)
    ax.set_xticklabels(df.index)
    ax.set_yscale("log")
    ax.set_ylabel("Latency (ms) - log scale")
    ax.legend(fontsize=8)
    for i, v in enumerate(m_s2m):
        try:
            if not math.isnan(v):
                ax.text(i - w/2, max(1e-2, v)*1.05, f"{v:.0f}", ha='center', va='bottom', fontsize=8)
        except Exception:
            pass
    for i, v in enumerate(m_m2s):
        try:
            if not math.isnan(v):
                ax.text(i + w/2, max(1e-2, v)*1.05, f"{v:.0f}", ha='center', va='bottom', fontsize=8)
        except Exception:
            pass

    # cdf <= 200ms
    ax = axes[1]
    cdf = df["cdf_le_200"].fillna(0).values
    colors = ["#2ca02c","#ff7f0e","#1f77b4"]
    ax.bar(df.index, cdf, color=colors)
    ax.set_ylim(0,1.05)
    ax.set_ylabel("CDF(RTT ≤ 200 ms)")
    for i, v in enumerate(cdf):
        try:
            ax.text(i, v + 0.03, f"{v:.2f}", ha='center')
        except Exception:
            pass

    # Reliability / Availability + Timeless + ODTE (all in one panel)
    ax = axes[2]
    # bar grouping: mean_R, median_R, mean_A, median_A on left y-axis (0..1)
    # and mean_T, median_T on right y-axis (ms)
    x = list(range(len(df.index)))
    w = 0.12
    mean_R = df["mean_R"].values
    median_R = df["median_R"].values
    mean_A = df["mean_A"].values
    median_A = df["median_A"].values
    mean_T = df.get("mean_T", pd.Series([float('nan')] * len(df.index))).values
    median_T = df.get("median_T", pd.Series([float('nan')] * len(df.index))).values

    # Left axis bars (R and A)
    ax.bar([i - 2.5*w for i in x], mean_R, width=w, label="mean R")
    ax.bar([i - 1.5*w for i in x], median_R, width=w, label="median R")
    ax.bar([i - 0.5*w for i in x], mean_A, width=w, label="mean A")
    ax.bar([i + 0.5*w for i in x], median_A, width=w, label="median A")
    ax.set_xticks(x)
    ax.set_xticklabels(df.index)
    ax.set_ylim(0,1.05)
    # single compact Y label per user request
    ax.set_ylabel("T × R × A")
    # Right axis for Timeless (ms) - create before constructing legend
    ax2 = ax.twinx()
    ax2.bar([i + 1.5*w for i in x], mean_T, width=w, color='#7f7f7f', label='mean T (ms)')
    ax2.bar([i + 2.5*w for i in x], median_T, width=w, color='#c7c7c7', label='median T (ms)')
    ax2.set_ylabel('Timeless (ms)')
    # collect legend handles; we'll place a single legend below the subplots
    handles_main, labels_main = ax.get_legend_handles_labels()
    handles2_main, labels2_main = ax2.get_legend_handles_labels()
    combined_handles = handles_main + handles2_main
    combined_labels = labels_main + labels2_main
    # annotate mean R and mean A values, clamped inside axis upper limit
    ytop = ax.get_ylim()[1]
    for i, v in enumerate(mean_R):
        try:
            if not math.isnan(v):
                y = min(v + 0.02, ytop * 0.92)
                ax.text(i - 2.5*w, y, f"{v:.2f}", ha='center', fontsize=8)
        except Exception:
            pass
    for i, v in enumerate(mean_A):
        try:
            if not math.isnan(v):
                y = min(v + 0.02, ytop * 0.92)
                ax.text(i - 0.5*w, y, f"{v:.2f}", ha='center', fontsize=8)
        except Exception:
            pass

    # annotate Timeless values
    for i, v in enumerate(mean_T):
        try:
            if not math.isnan(v):
                ax2.text(i + 1.5*w, v + (v * 0.03 if v > 1 else 0.5), f"{v:.1f}", ha='center', fontsize=8)
        except Exception:
            pass
    for i, v in enumerate(median_T):
        try:
            if not math.isnan(v):
                ax2.text(i + 2.5*w, v + (v * 0.03 if v > 1 else 0.5), f"{v:.1f}", ha='center', fontsize=8)
        except Exception:
            pass
    # do not draw per-axis legend here; reserve bottom area and place a single caption legend
    plt.tight_layout(rect=[0,0.05,0.98,0.95])
    # place a single legend below the subplots (inside the image)
    try:
        fig.legend(combined_handles, combined_labels, loc='lower center', ncol=3, fontsize=9)
    except Exception:
        pass
    # Save the combined overview PNG
    fig.savefig(out_png, dpi=150)
    # Also save each panel individually by drawing them into separate small figures
    try:
        # Panel 0: latency
        fig0, ax0 = plt.subplots(1,1, figsize=(6,4))
        ax0.bar([i - w/2 for i in x], m_s2m, width=w, label="median S2M (ms)")
        ax0.bar([i + w/2 for i in x], m_m2s, width=w, label="median M2S (ms)")
        ax0.set_xticks(x)
        ax0.set_xticklabels(df.index)
        ax0.set_yscale("log")
        ax0.set_ylabel("Latency (ms) - log scale")
        ax0.legend(fontsize=8)
        fig0.tight_layout()
        fig0.savefig(out_latency_png, dpi=150)
        plt.close(fig0)

        # Panel 1: cdf <= 200ms
        fig1, ax1 = plt.subplots(1,1, figsize=(4,4))
        ax1.bar(df.index, cdf, color=colors)
        ax1.set_ylim(0,1.05)
        ax1.set_ylabel("CDF(RTT ≤ 200 ms)")
        ax1.set_title('CDF ≤ 200 ms')
        for i, v in enumerate(cdf):
            try:
                if not math.isnan(v):
                    ytop1 = ax1.get_ylim()[1]
                    y = min(v + 0.03, ytop1 * 0.92)
                    ax1.text(i, y, f"{v:.2f}", ha='center')
            except Exception:
                pass
        fig1.tight_layout()
        fig1.savefig(out_cdf200_png, dpi=150)
        plt.close(fig1)

        # Panel 2: R/A + Timeless
        fig2, ax2_main = plt.subplots(1,1, figsize=(8,4))
        # draw left axis bars
        ax2_main.bar([i - 2.5*w for i in x], mean_R, width=w, label="mean R")
        ax2_main.bar([i - 1.5*w for i in x], median_R, width=w, label="median R")
        ax2_main.bar([i - 0.5*w for i in x], mean_A, width=w, label="mean A")
        ax2_main.bar([i + 0.5*w for i in x], median_A, width=w, label="median A")
        ax2_main.set_xticks(x)
        ax2_main.set_xticklabels(df.index)
        ax2_main.set_ylim(0,1.05)
        ax2_main.set_ylabel("T × R × A")

        # Right axis for Timeless (ms)
        ax2_sec = ax2_main.twinx()
        ax2_sec.bar([i + 1.5*w for i in x], mean_T, width=w, color='#7f7f7f', label='mean T (ms)')
        ax2_sec.bar([i + 2.5*w for i in x], median_T, width=w, color='#c7c7c7', label='median T (ms)')
        ax2_sec.set_ylabel('Timeless (ms)')

        # annotate Timeless values on the secondary axis, clamped to axis top
        ytop2 = ax2_sec.get_ylim()[1]
        for i, v in enumerate(mean_T):
            try:
                if not math.isnan(v):
                    y = min(v + (v * 0.03 if v > 1 else 0.5), ytop2 * 0.92)
                    ax2_sec.text(i + 1.5*w, y, f"{v:.1f}", ha='center', fontsize=8)
            except Exception:
                pass
        for i, v in enumerate(median_T):
            try:
                if not math.isnan(v):
                    y = min(v + (v * 0.03 if v > 1 else 0.5), ytop2 * 0.92)
                    ax2_sec.text(i + 2.5*w, y, f"{v:.1f}", ha='center', fontsize=8)
            except Exception:
                pass

        # collect legend handles for per-panel legend below the figure
        handles1, labels1 = ax2_main.get_legend_handles_labels()
        handles2, labels2 = ax2_sec.get_legend_handles_labels()
        per_handles = handles1 + handles2
        per_labels = labels1 + labels2
        fig2.tight_layout(rect=[0,0.05,0.98,1])
        try:
            fig2.legend(per_handles, per_labels, loc='lower center', ncol=3, fontsize=8)
        except Exception:
            pass
        fig2.savefig(out_ra_t_png, dpi=150)
        plt.close(fig2)
    except Exception as e:
        print('Warning: failed to write per-panel images:', e)

    write_csv(df, out_csv)
    # Save an external legend image (compact, no numbers)
    try:
        if combined_handles:
            lg_fig = plt.figure(figsize=(2.0, 3.5))
            lg_ax = lg_fig.add_subplot(111)
            lg_ax.axis('off')
            # make legend only with labels (no numeric annotations); use small font
            lg = lg_fig.legend(combined_handles, combined_labels, loc='center', fontsize=8)
            lg_fig.tight_layout()
            out_legend = os.path.join(OUT_DIR, 'compare_profiles_legend.png')
            lg_fig.savefig(out_legend, dpi=150, bbox_inches='tight')
            plt.close(lg_fig)
            print('Saved external legend:', out_legend)
    except Exception as e:
        print('Warning: could not write external legend image:', e)

    print(f"Saved {out_png}, {out_csv} and per-panel PNGs in {OUT_DIR}")


def main():
    rows = collect()
    df = build_dataframe(rows)
    print("Collected summary values:")
    print(df)
    plot(df)

if __name__ == "__main__":
    main()
