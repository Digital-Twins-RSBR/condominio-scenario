#!/usr/bin/env python3
"""
Enhanced visualization tool for URLLC analysis with focus on key metrics and problem identification.

Usage: python3 scripts/reports/report_generators/enhanced_visualize.py <generated_reports_dir>

Produces enhanced PNGs in <generated_reports_dir>/plots/:
- urllc_latency_comparison.png - Compares S2M vs M2S latencies
- urllc_problem_analysis.png - Highlights the performance issues
- urllc_odte_analysis.png - ODTE metrics over time and per sensor
- urllc_comprehensive_dashboard.png - All key metrics in one view
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


def safe_int(s):
    try:
        return int(s)
    except Exception:
        return 0


def read_csv_dict(path):
    if not os.path.exists(path):
        return []
    with open(path, newline='') as f:
        r = csv.DictReader(f)
        return list(r)


def format_ms_to_readable(ms):
    """Convert milliseconds to human readable format"""
    if ms < 1000:
        return f"{ms:.1f}ms"
    elif ms < 60000:
        return f"{ms/1000:.1f}s"
    else:
        return f"{ms/60000:.1f}min"


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

    # find latest files
    def latest(pattern):
        files = [os.path.join(d, f) for f in os.listdir(d) if f.startswith(pattern)]
        files = [f for f in files if os.path.isfile(f)]
        if not files:
            return None
        return sorted(files, key=os.path.getmtime)[-1]

    odte_file = latest('urllc_odte_')
    ecdf_file = latest('urllc_ecdf_rtt_')
    windows_file = latest('urllc_windows_')
    lat_m2s_file = latest('urllc_latencia_stats_middts_to_simulator_')
    lat_s2m_file = latest('urllc_latencia_stats_simulator_to_middts_')

    # Try importing matplotlib; if unavailable, print an instruction
    try:
        import matplotlib.pyplot as plt
        import numpy as np
        plt.style.use('default')
    except Exception as e:
        print('matplotlib/numpy not available. To generate plots install them:')
        print('  sudo pip3 install matplotlib numpy')
        sys.exit(3)

    # Read data
    lat_m2s = read_csv_dict(lat_m2s_file) if lat_m2s_file else []
    lat_s2m = read_csv_dict(lat_s2m_file) if lat_s2m_file else []
    odte_data = read_csv_dict(odte_file) if odte_file else []
    windows_data = read_csv_dict(windows_file) if windows_file else []
    ecdf_data = read_csv_dict(ecdf_file) if ecdf_file else []

    # Filter active sensors
    lat_m2s_active = [row for row in lat_m2s if safe_int(row.get('count', 0)) > 0]
    lat_s2m_active = [row for row in lat_s2m if safe_int(row.get('count', 0)) > 0]

    # 1. LATENCY COMPARISON PLOT
    if lat_m2s_active and lat_s2m_active:
        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(15, 6))
        
        # S2M latencies (should be low)
        sensors_s2m = [row['sensor'][-8:] for row in lat_s2m_active]  # short sensor ID
        means_s2m = [safe_float(row['mean_ms']) for row in lat_s2m_active]
        p95_s2m = [safe_float(row['p95_ms']) for row in lat_s2m_active]
        p99_s2m = [safe_float(row['p99_ms']) for row in lat_s2m_active]
        
        x_pos = range(len(sensors_s2m))
        width = 0.25
        
        ax1.bar([x - width for x in x_pos], means_s2m, width, label='Mean', color='green', alpha=0.7)
        ax1.bar(x_pos, p95_s2m, width, label='P95', color='orange', alpha=0.7)
        ax1.bar([x + width for x in x_pos], p99_s2m, width, label='P99', color='red', alpha=0.7)
        
        ax1.set_xlabel('Sensor')
        ax1.set_ylabel('Latency (ms)')
        ax1.set_title('Sensor → Middleware Latencies\n(GOOD: Low values)')
        ax1.set_xticks(x_pos)
        ax1.set_xticklabels(sensors_s2m, rotation=45, fontsize=8)
        ax1.legend()
        ax1.grid(True, alpha=0.3)
        ax1.axhline(y=1, color='blue', linestyle='--', alpha=0.5, label='URLLC Target (1ms)')
        
        # M2S latencies (problematic - very high)
        sensors_m2s = [row['sensor'][-8:] for row in lat_m2s_active]
        means_m2s = [safe_float(row['mean_ms']) for row in lat_m2s_active]
        p95_m2s = [safe_float(row['p95_ms']) for row in lat_m2s_active]
        p99_m2s = [safe_float(row['p99_ms']) for row in lat_m2s_active]
        
        x_pos2 = range(len(sensors_m2s))
        
        ax2.bar([x - width for x in x_pos2], [m/1000 for m in means_m2s], width, label='Mean', color='darkred', alpha=0.7)
        ax2.bar(x_pos2, [p/1000 for p in p95_m2s], width, label='P95', color='red', alpha=0.7)
        ax2.bar([x + width for x in x_pos2], [p/1000 for p in p99_m2s], width, label='P99', color='orange', alpha=0.7)
        
        ax2.set_xlabel('Sensor')
        ax2.set_ylabel('Latency (seconds)')
        ax2.set_title('Middleware → Simulator Latencies\n(PROBLEM: Very high values)')
        ax2.set_xticks(x_pos2)
        ax2.set_xticklabels(sensors_m2s, rotation=45, fontsize=8)
        ax2.legend()
        ax2.grid(True, alpha=0.3)
        ax2.axhline(y=0.001, color='blue', linestyle='--', alpha=0.5, label='URLLC Target (1ms)')
        
        plt.tight_layout()
        out = os.path.join(plots_dir, 'urllc_latency_comparison.png')
        plt.savefig(out, bbox_inches='tight', dpi=300)
        plt.close()
        print(f'✅ Wrote {out}')

    # 2. PROBLEM ANALYSIS DASHBOARD
    if lat_m2s_active and lat_s2m_active:
        fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=(16, 12))
        
        # Calculate summary statistics
        s2m_mean_avg = sum(safe_float(row['mean_ms']) for row in lat_s2m_active) / len(lat_s2m_active)
        m2s_mean_avg = sum(safe_float(row['mean_ms']) for row in lat_m2s_active) / len(lat_m2s_active)
        
        # Problem severity visualization
        categories = ['Sensor→Middleware', 'Middleware→Simulator']
        latencies = [s2m_mean_avg, m2s_mean_avg/1000]  # Convert M2S to seconds
        colors = ['green', 'red']
        
        bars = ax1.bar(categories, latencies, color=colors, alpha=0.7)
        ax1.set_ylabel('Average Latency')
        ax1.set_title('URLLC Performance Problem Analysis')
        ax1.axhline(y=0.001, color='blue', linestyle='--', label='URLLC Target (1ms)')
        ax1.set_yscale('log')
        ax1.legend()
        ax1.grid(True, alpha=0.3)
        
        # Add value labels on bars
        for bar, val in zip(bars, [s2m_mean_avg, m2s_mean_avg]):
            height = bar.get_height()
            ax1.text(bar.get_x() + bar.get_width()/2., height*1.1,
                    format_ms_to_readable(val), ha='center', va='bottom', fontweight='bold')
        
        # ODTE over time
        if windows_data:
            times = list(range(len(windows_data)))
            odte_means = [safe_float(row.get('ODTE_mean', 0)) for row in windows_data]
            t_means = [safe_float(row.get('T_mean', 0)) for row in windows_data]
            r_means = [safe_float(row.get('R_mean', 0)) for row in windows_data]
            
            ax2.plot(times, odte_means, 'b-', marker='o', label='ODTE', linewidth=2)
            ax2.plot(times, t_means, 'r--', label='Throughput', alpha=0.7)
            ax2.plot(times, r_means, 'g--', label='Reliability', alpha=0.7)
            ax2.set_xlabel('Time Window (10s intervals)')
            ax2.set_ylabel('Metric Value')
            ax2.set_title('ODTE Metrics Over Time')
            ax2.legend()
            ax2.grid(True, alpha=0.3)
        
        # Latency distribution (if ECDF available)
        if ecdf_data:
            rtts = [safe_float(row.get('rtt_ms', 0)) for row in ecdf_data]
            cdfs = [safe_float(row.get('cdf', 0)) for row in ecdf_data]
            ax3.plot(rtts, cdfs, 'b-', linewidth=2)
            ax3.set_xlabel('RTT (ms)')
            ax3.set_ylabel('CDF')
            ax3.set_title('RTT Distribution (ECDF)')
            ax3.set_xscale('log')
            ax3.grid(True, alpha=0.3)
            ax3.axvline(x=1, color='red', linestyle='--', label='URLLC Target (1ms)')
            ax3.legend()
        
        # Active sensors summary
        active_sensors = len(lat_s2m_active)
        total_sensors = len(lat_s2m)  # includes inactive
        success_rate = (active_sensors / total_sensors * 100) if total_sensors > 0 else 0
        
        ax4.pie([active_sensors, total_sensors - active_sensors], 
                labels=[f'Active ({active_sensors})', f'Inactive ({total_sensors - active_sensors})'],
                colors=['lightgreen', 'lightcoral'], autopct='%1.1f%%', startangle=90)
        ax4.set_title(f'Sensor Activity Status\n({success_rate:.1f}% active)')
        
        # Add summary text
        summary_text = f"""
URLLC PERFORMANCE SUMMARY:
        
[101m[30mURLLC Summary[0m
        
"""
        
        fig.text(0.02, 0.02, summary_text, fontsize=10, 
                bbox=dict(boxstyle="round,pad=0.5", facecolor="lightblue", alpha=0.8))
        
        plt.tight_layout()
        out = os.path.join(plots_dir, 'urllc_problem_analysis.png')
        plt.savefig(out, bbox_inches='tight', dpi=300)
        plt.close()
        print(f'✅ Wrote {out}')

    # 3. ODTE Analysis
    if odte_data:
        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(15, 6))
        
        # ODTE per sensor
        sensors = [row.get('sensor', '')[-8:] for row in odte_data]
        odte_s2m = [safe_float(row.get('ODTE_s2m', 0)) for row in odte_data]
        odte_m2s = [safe_float(row.get('ODTE_m2s', 0)) for row in odte_data]
        
        x_pos = range(len(sensors))
        width = 0.35
        
        ax1.bar([x - width/2 for x in x_pos], odte_s2m, width, label='S2M ODTE', color='green', alpha=0.7)
        ax1.bar([x + width/2 for x in x_pos], odte_m2s, width, label='M2S ODTE', color='red', alpha=0.7)
        ax1.set_xlabel('Sensor')
        ax1.set_ylabel('ODTE')
        ax1.set_title('ODTE per Sensor (by Direction)')
        ax1.set_xticks(x_pos)
        ax1.set_xticklabels(sensors, rotation=45, fontsize=8)
        ax1.legend()
        ax1.grid(True, alpha=0.3)
        
        # ODTE time series
        if windows_data:
            times = list(range(len(windows_data)))
            odte_means = [safe_float(row.get('ODTE_mean', 0)) for row in windows_data]
            ax2.plot(times, odte_means, 'b-', marker='o', linewidth=2, markersize=4)
            ax2.set_xlabel('Time Window (10s intervals)')
            ax2.set_ylabel('ODTE Mean')
            ax2.set_title('ODTE Evolution Over Time')
            ax2.grid(True, alpha=0.3)
            ax2.axhline(y=0.5, color='orange', linestyle='--', alpha=0.5, label='50% threshold')
            ax2.legend()
        
        plt.tight_layout()
        out = os.path.join(plots_dir, 'urllc_odte_analysis.png')
        plt.savefig(out, bbox_inches='tight', dpi=300)
        plt.close()
        print(f'✅ Wrote {out}')

    # Print summary analysis
    print("\n" + "="*60)
    print("🏯 URLLC ANALYSIS SUMMARY")
    print("="*60)
    
    if lat_s2m_active and lat_m2s_active:
        s2m_avg = sum(safe_float(row['mean_ms']) for row in lat_s2m_active) / len(lat_s2m_active)
        m2s_avg = sum(safe_float(row['mean_ms']) for row in lat_m2s_active) / len(lat_m2s_active)
        
        print(f"📈 Sensor → Middleware: {format_ms_to_readable(s2m_avg)} (avg)")
        print(f"📈 Middleware → Simulator: {format_ms_to_readable(m2s_avg)} (avg)")
        print(f"🎯 URLLC Target: < 1ms")
        print()
        
        if s2m_avg < 100:  # Reasonable for testing
            print("✅ S2M Performance: ACCEPTABLE (for testing environment)")
        else:
            print("⚠️  S2M Performance: HIGH (but functional)")
            
        if m2s_avg > 1000:  # Over 1 second is problematic
            print("❌ M2S Performance: CRITICAL PROBLEM")
            print("   └─ Middleware processing or return path bottleneck")
        else:
            print("✅ M2S Performance: OK")
            
        print()
        print("🔧 RECOMMENDATION:")
        if m2s_avg > 1000:
            print("   • Investigate middleware processing delays")
            print("   • Check return network path configuration")
            print("   • Monitor middleware resource usage")
            print("   • Verify simulator response handling")
    
    print(f"\n📁 All plots saved to: {plots_dir}")


if __name__ == '__main__':
    main()
