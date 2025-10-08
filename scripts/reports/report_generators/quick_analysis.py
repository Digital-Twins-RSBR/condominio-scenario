#!/usr/bin/env python3
"""
Quick analysis tool for URLLC performance metrics without visualization dependencies.
Provides comprehensive text-based analysis of the generated reports.

Usage: python3 scripts/reports/report_generators/quick_analysis.py <generated_reports_dir>
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
    if ms < 1:
        return f"{ms:.3f}ms"
    elif ms < 1000:
        return f"{ms:.1f}ms"
    elif ms < 60000:
        return f"{ms/1000:.1f}s"
    else:
        return f"{ms/60000:.1f}min"


def analyze_urllc_performance(reports_dir):
    """Analyze URLLC performance and return detailed report"""
    
    # Find latest files
    def latest(pattern):
        files = [os.path.join(reports_dir, f) for f in os.listdir(reports_dir) if f.startswith(pattern)]
        files = [f for f in files if os.path.isfile(f)]
        if not files:
            return None
        return sorted(files, key=os.path.getmtime)[-1]

    lat_m2s_file = latest('urllc_latencia_stats_middts_to_simulator_')
    lat_s2m_file = latest('urllc_latencia_stats_simulator_to_middts_')
    odte_file = latest('urllc_odte_')
    windows_file = latest('urllc_windows_')
    summary_file = latest('../summary_urllc_')

    # Load data
    lat_m2s = read_csv_dict(lat_m2s_file) if lat_m2s_file else []
    lat_s2m = read_csv_dict(lat_s2m_file) if lat_s2m_file else []
    odte_data = read_csv_dict(odte_file) if odte_file else []
    windows_data = read_csv_dict(windows_file) if windows_file else []

    # Filter active sensors
    lat_m2s_active = [row for row in lat_m2s if safe_int(row.get('count', 0)) > 0]
    lat_s2m_active = [row for row in lat_s2m if safe_int(row.get('count', 0)) > 0]

    print("=" * 80)
    print("🏯 URLLC PERFORMANCE ANALYSIS REPORT")
    print("=" * 80)
    print()

    # Basic info
    if summary_file and os.path.exists(summary_file):
        print("📋 EXPERIMENT SUMMARY:")
        with open(summary_file, 'r') as f:
            for line in f:
                if line.strip():
                    print(f"   {line.strip()}")
        print()

    # Latency Analysis
    if lat_s2m_active and lat_m2s_active:
        print("📈 LATENCY ANALYSIS:")
        print("-" * 40)
        
        # S2M stats
        s2m_means = [safe_float(row['mean_ms']) for row in lat_s2m_active]
        s2m_p95s = [safe_float(row['p95_ms']) for row in lat_s2m_active]
        s2m_p99s = [safe_float(row['p99_ms']) for row in lat_s2m_active]
        
        s2m_avg = sum(s2m_means) / len(s2m_means)
        s2m_p95_avg = sum(s2m_p95s) / len(s2m_p95s)
        s2m_p99_avg = sum(s2m_p99s) / len(s2m_p99s)
        
        print(f"📊 Sensor → Middleware (S2M):")
        print(f"   • Active sensors: {len(lat_s2m_active)}")
        print(f"   • Average latency: {format_ms_to_readable(s2m_avg)}")
        print(f"   • P95 latency: {format_ms_to_readable(s2m_p95_avg)}")
        print(f"   • P99 latency: {format_ms_to_readable(s2m_p99_avg)}")
        print(f"   • Min latency: {format_ms_to_readable(min(s2m_means))}")
        print(f"   • Max latency: {format_ms_to_readable(max(s2m_means))}")
        
        # M2S stats
        m2s_means = [safe_float(row['mean_ms']) for row in lat_m2s_active]
        m2s_p95s = [safe_float(row['p95_ms']) for row in lat_m2s_active]
        m2s_p99s = [safe_float(row['p99_ms']) for row in lat_m2s_active]
        
        m2s_avg = sum(m2s_means) / len(m2s_means)
        m2s_p95_avg = sum(m2s_p95s) / len(m2s_p95s)
        m2s_p99_avg = sum(m2s_p99s) / len(m2s_p99s)
        
        print()
        print(f"📉 Middleware → Simulator (M2S):")
        print(f"   • Active sensors: {len(lat_m2s_active)}")
        print(f"   • Average latency: {format_ms_to_readable(m2s_avg)}")
        print(f"   • P95 latency: {format_ms_to_readable(m2s_p95_avg)}")
        print(f"   • P99 latency: {format_ms_to_readable(m2s_p99_avg)}")
        print(f"   • Min latency: {format_ms_to_readable(min(m2s_means))}")
        print(f"   • Max latency: {format_ms_to_readable(max(m2s_means))}")
        print()

        # Performance evaluation
        print("🎯 URLLC PERFORMANCE EVALUATION:")
        print("-" * 40)
        print(f"   Target: < 1ms (Ultra-Reliable Low Latency Communication)")
        print()
        
        if s2m_avg < 1:
            print("   ✅ S2M Performance: EXCELLENT (meets URLLC target)")
        elif s2m_avg < 10:
            print("   ✅ S2M Performance: GOOD (close to URLLC target)")
        elif s2m_avg < 100:
            print("   ⚠️  S2M Performance: ACCEPTABLE (for testing)")
        else:
            print("   ❌ S2M Performance: POOR (exceeds reasonable limits)")
        
        if m2s_avg < 1:
            print("   ✅ M2S Performance: EXCELLENT (meets URLLC target)")
        elif m2s_avg < 10:
            print("   ✅ M2S Performance: GOOD (close to URLLC target)")
        elif m2s_avg < 100:
            print("   ⚠️  M2S Performance: ACCEPTABLE (for testing)")
        elif m2s_avg < 1000:
            print("   ❌ M2S Performance: POOR (high latency)")
        else:
            print("   🚨 M2S Performance: CRITICAL (extreme latency)")
        
        print()
        
        # Ratio analysis
        latency_ratio = m2s_avg / s2m_avg if s2m_avg > 0 else float('inf')
        print("📈 PERFORMANCE RATIO:")
        print(f"   • M2S/S2M ratio: {latency_ratio:.1f}x")
        if latency_ratio > 1000:
            print("   🚨 CRITICAL: M2S latency is extremely higher than S2M")
        elif latency_ratio > 100:
            print("   ❌ PROBLEM: Significant asymmetry in communication")
        elif latency_ratio > 10:
            print("   ⚠️  WARNING: Notable difference in directions")
        else:
            print("   ✅ BALANCED: Similar performance in both directions")
        print()

    # ODTE Analysis
    if odte_data:
        print("📊 ODTE (On-time Data Transmission Efficiency) ANALYSIS:")
        print("-" * 40)
        
        active_odte = [row for row in odte_data if safe_float(row.get('ODTE_s2m', 0)) > 0 or safe_float(row.get('ODTE_m2s', 0)) > 0]
        
        odte_s2m_values = [safe_float(row.get('ODTE_s2m', 0)) for row in active_odte]
        odte_m2s_values = [safe_float(row.get('ODTE_m2s', 0)) for row in active_odte]
        
        if odte_s2m_values:
            print(f"   • S2M ODTE average: {sum(odte_s2m_values)/len(odte_s2m_values):.3f}")
            print(f"   • S2M ODTE range: {min(odte_s2m_values):.3f} - {max(odte_s2m_values):.3f}")
        
        if odte_m2s_values:
            print(f"   • M2S ODTE average: {sum(odte_m2s_values)/len(odte_m2s_values):.3f}")
            print(f"   • M2S ODTE range: {min(odte_m2s_values):.3f} - {max(odte_m2s_values):.3f}")
        
        print(f"   • Active sensors: {len(active_odte)}")
        print()

    # Time series analysis
    if windows_data:
        print("📈 TIME SERIES ANALYSIS:")
        print("-" * 40)
        
        odte_means = [safe_float(row.get('ODTE_mean', 0)) for row in windows_data]
        t_means = [safe_float(row.get('T_mean', 0)) for row in windows_data]
        r_means = [safe_float(row.get('R_mean', 0)) for row in windows_data]
        
        print(f"   • Total time windows: {len(windows_data)}")
        print(f"   • ODTE stability: {min(odte_means):.3f} - {max(odte_means):.3f}")
        print(f"   • Average throughput: {sum(t_means)/len(t_means):.3f}")
        print(f"   • Average reliability: {sum(r_means)/len(r_means):.3f}")
        
        # Check for stability
        odte_std = math.sqrt(sum((x - sum(odte_means)/len(odte_means))**2 for x in odte_means) / len(odte_means))
        if odte_std < 0.01:
            print("   ✅ ODTE stability: EXCELLENT (very stable)")
        elif odte_std < 0.05:
            print("   ✅ ODTE stability: GOOD (stable)")
        elif odte_std < 0.1:
            print("   ⚠️  ODTE stability: MODERATE (some variation)")
        else:
            print("   ❌ ODTE stability: POOR (high variation)")
        print()

    # Problem diagnosis
    print("🔍 PROBLEM DIAGNOSIS:")
    print("-" * 40)
    
    problems_found = []
    recommendations = []
    
    if lat_s2m_active and lat_m2s_active:
        s2m_avg = sum(safe_float(row['mean_ms']) for row in lat_s2m_active) / len(lat_s2m_active)
        m2s_avg = sum(safe_float(row['mean_ms']) for row in lat_m2s_active) / len(lat_m2s_active)
        
        if s2m_avg > 100:
            problems_found.append("High S2M latency (sensor to middleware)")
            recommendations.append("Check sensor network configuration and processing")
        
        if m2s_avg > 1000:
            problems_found.append("Critical M2S latency (middleware to simulator)")
            recommendations.append("Investigate middleware processing bottlenecks")
            recommendations.append("Check return network path configuration")
            recommendations.append("Monitor middleware resource usage (CPU/Memory)")
        
        if m2s_avg / s2m_avg > 100:
            problems_found.append("Severe asymmetry in communication paths")
            recommendations.append("Compare network configurations for both directions")
    
    total_sensors = len(lat_s2m) if lat_s2m else 0
    active_sensors = len(lat_s2m_active) if lat_s2m_active else 0
    
    if total_sensors > 0 and active_sensors / total_sensors < 0.8:
        problems_found.append(f"Low sensor activity rate ({active_sensors}/{total_sensors})")
        recommendations.append("Check sensor connectivity and configuration")
    
    if problems_found:
        print("   ❌ ISSUES IDENTIFIED:")
        for i, problem in enumerate(problems_found, 1):
            print(f"      {i}. {problem}")
        print()
        print("   🔧 RECOMMENDATIONS:")
        for i, rec in enumerate(recommendations, 1):
            print(f"      {i}. {rec}")
    else:
        print("   ✅ No critical issues detected")
    
    print()
    print("=" * 80)
    return len(problems_found) == 0


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    
    reports_dir = sys.argv[1]
    if not os.path.isdir(reports_dir):
        print(f'❌ Reports directory not found: {reports_dir}')
        print('   Run "make odte" first to generate reports')
        sys.exit(2)
    
    success = analyze_urllc_performance(reports_dir)
    
    if success:
        print('✅ OVERALL STATUS: ACCEPTABLE')
    else:
        print('❌ OVERALL STATUS: ISSUES DETECTED')
    
    # Always exit 0 for make compatibility - issues are expected in analysis
    sys.exit(0)


if __name__ == '__main__':
    main()
