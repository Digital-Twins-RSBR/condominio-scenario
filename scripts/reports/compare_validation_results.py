#!/usr/bin/env python3
"""
compare_validation_results.py - Compara resultados da bateria de validação do artigo
Extrai métricas de correlation analysis e gera tabela comparativa
"""

import os
import sys
import re
from pathlib import Path
from typing import Dict, List, Tuple


def extract_metrics_from_correlation_file(filepath: str) -> Dict[str, any]:
    """
    Extrai métricas do arquivo latency_analysis_correlation.txt
    """
    metrics = {
        'total_commands': 0,
        'sla_count': 0,
        'sla_percent': 0.0,
        'delivery_count': 0,
        'delivery_percent': 0.0,
        'timeout_count': 0,
        'timeout_percent': 0.0,
        'loss_count': 0,
        'loss_percent': 0.0,
        'mean_latency': 0.0,
        'p50_latency': 0.0,
        'p95_latency': 0.0,
        'p99_latency': 0.0,
        'max_latency': 0.0,
        'cv_percent': 0.0,
        'retry_overhead': 0.0,
        'mean_retries': 0.0
    }
    
    if not os.path.exists(filepath):
        return metrics
    
    with open(filepath, 'r') as f:
        content = f.read()
    
    # Extract Total commands sent
    match = re.search(r'Total commands sent:\s+(\d+)', content)
    if match:
        metrics['total_commands'] = int(match.group(1))
    
    # Extract SLA Compliance
    match = re.search(r'SLA Compliance \(≤150ms\):\s+(\d+)\s+\(([\d.]+)%\)', content)
    if match:
        metrics['sla_count'] = int(match.group(1))
        metrics['sla_percent'] = float(match.group(2))
    
    # Extract Eventual Delivery
    match = re.search(r'Eventual Delivery \(≤2000ms\):\s+(\d+)\s+\(([\d.]+)%\)', content)
    if match:
        metrics['delivery_count'] = int(match.group(1))
        metrics['delivery_percent'] = float(match.group(2))
    
    # Extract Timeout
    match = re.search(r'Timeout \(>2000ms\):\s+(\d+)\s+\(([\d.]+)%\)', content)
    if match:
        metrics['timeout_count'] = int(match.group(1))
        metrics['timeout_percent'] = float(match.group(2))
    
    # Extract Loss
    match = re.search(r'Loss \(never received\):\s+(\d+)\s+\(([\d.]+)%\)', content)
    if match:
        metrics['loss_count'] = int(match.group(1))
        metrics['loss_percent'] = float(match.group(2))
    
    # Extract Retry overhead
    match = re.search(r'Retry overhead:\s+([-\d.]+)%', content)
    if match:
        metrics['retry_overhead'] = float(match.group(1))
    
    # Extract Mean retries
    match = re.search(r'Mean retries per command:\s+([\d.]+)', content)
    if match:
        metrics['mean_retries'] = float(match.group(1))
    
    # Extract Latencies (from "All Delivery Latencies" section)
    latency_section = re.search(
        r'📊 All Delivery Latencies \(eventual\)\s+'
        r'Count:\s+(\d+)\s+'
        r'Mean:\s+([\d.]+)\s+'
        r'P50:\s+([\d.]+)\s+'
        r'P95:\s+([\d.]+)\s+'
        r'P99:\s+([\d.]+)\s+'
        r'Max:\s+([\d.]+)\s+'
        r'CV:\s+([\d.]+)%',
        content
    )
    
    if latency_section:
        metrics['mean_latency'] = float(latency_section.group(2))
        metrics['p50_latency'] = float(latency_section.group(3))
        metrics['p95_latency'] = float(latency_section.group(4))
        metrics['p99_latency'] = float(latency_section.group(5))
        metrics['max_latency'] = float(latency_section.group(6))
        metrics['cv_percent'] = float(latency_section.group(7))
    
    return metrics


def find_test_directories(validation_dir: str) -> List[Tuple[int, str, str]]:
    """
    Encontra diretórios de teste na pasta de validação
    Retorna lista de (test_num, test_name, full_path)
    """
    tests = []
    
    for entry in sorted(os.listdir(validation_dir)):
        full_path = os.path.join(validation_dir, entry)
        if not os.path.isdir(full_path):
            continue
        
        # Match test{N}_test_TIMESTAMP_PROFILE pattern
        match = re.match(r'test(\d+)_test_\d+Z_(\w+)', entry)
        if match:
            test_num = int(match.group(1))
            profile = match.group(2)
            tests.append((test_num, profile, full_path))
    
    return sorted(tests, key=lambda x: x[0])


def generate_comparison_table(tests: List[Tuple[int, str, str, Dict]]) -> str:
    """
    Gera tabela comparativa em Markdown
    """
    lines = []
    lines.append("# Article Validation Results - Comparative Analysis")
    lines.append("")
    lines.append(f"**Generated:** {os.popen('date').read().strip()}")
    lines.append("")
    
    # Main comparison table
    lines.append("## Delivery Metrics Comparison")
    lines.append("")
    lines.append("| Test | Profile | Total Cmds | SLA ≤150ms | Delivery % | Loss % | Mean Lat (ms) | P95 Lat (ms) |")
    lines.append("|------|---------|------------|------------|------------|--------|---------------|--------------|")
    
    for test_num, profile, _, metrics in tests:
        lines.append(
            f"| {test_num} | {profile:15} | {metrics['total_commands']:6} | "
            f"{metrics['sla_count']:4} ({metrics['sla_percent']:5.2f}%) | "
            f"{metrics['delivery_percent']:6.2f}% | "
            f"{metrics['loss_percent']:6.2f}% | "
            f"{metrics['mean_latency']:7.2f} | "
            f"{metrics['p95_latency']:7.2f} |"
        )
    
    lines.append("")
    
    # Latency distribution table
    lines.append("## Latency Distribution")
    lines.append("")
    lines.append("| Test | Profile | Mean | P50 | P95 | P99 | Max | CV % |")
    lines.append("|------|---------|------|-----|-----|-----|-----|------|")
    
    for test_num, profile, _, metrics in tests:
        lines.append(
            f"| {test_num} | {profile:15} | "
            f"{metrics['mean_latency']:6.2f} | "
            f"{metrics['p50_latency']:6.2f} | "
            f"{metrics['p95_latency']:6.2f} | "
            f"{metrics['p99_latency']:6.2f} | "
            f"{metrics['max_latency']:6.2f} | "
            f"{metrics['cv_percent']:5.2f}% |"
        )
    
    lines.append("")
    
    # Retry analysis
    lines.append("## Retry Analysis")
    lines.append("")
    lines.append("| Test | Profile | Mean Retries | Retry Overhead % |")
    lines.append("|------|---------|--------------|------------------|")
    
    for test_num, profile, _, metrics in tests:
        lines.append(
            f"| {test_num} | {profile:15} | "
            f"{metrics['mean_retries']:4.2f} | "
            f"{metrics['retry_overhead']:6.2f}% |"
        )
    
    lines.append("")
    
    # Validation against article baseline
    lines.append("## Validation Against Article Baseline")
    lines.append("")
    lines.append("**Article Claim:** URLLC achieves 97.44% M2S delivery")
    lines.append("")
    
    # Find URLLC tests
    urllc_tests = [(n, p, m) for n, p, _, m in tests if 'urllc' in p.lower()]
    
    if urllc_tests:
        lines.append("### URLLC Results (Current vs Article)")
        lines.append("")
        lines.append("| Test | Duration | Delivery % | Delta vs Article | Status |")
        lines.append("|------|----------|------------|------------------|--------|")
        
        for test_num, profile, metrics in urllc_tests:
            delta = metrics['delivery_percent'] - 97.44
            status = "✅ PASS" if metrics['delivery_percent'] >= 90.0 else "⚠️ WARN" if metrics['delivery_percent'] >= 80.0 else "❌ FAIL"
            
            lines.append(
                f"| {test_num} | {profile} | "
                f"{metrics['delivery_percent']:5.2f}% | "
                f"{delta:+6.2f}% | "
                f"{status} |"
            )
        
        lines.append("")
    
    # Infrastructure constraint validation
    lines.append("## Infrastructure Constraint Validation")
    lines.append("")
    lines.append("**Article Claim:** Non-URLLC profiles show degraded delivery due to TB timeout constraint")
    lines.append("")
    lines.append("- eMBB expected: ~13-14% (baseline), improvement with adaptive")
    lines.append("- Best-Effort expected: ~8% (baseline), improvement with adaptive")
    lines.append("")
    
    # Find eMBB and BE tests
    embb_tests = [(n, p, m) for n, p, _, m in tests if 'embb' in p.lower()]
    be_tests = [(n, p, m) for n, p, _, m in tests if 'effort' in p.lower()]
    
    if embb_tests:
        lines.append("### eMBB Results")
        lines.append("")
        lines.append("| Test | Profile | Delivery % | Status |")
        lines.append("|------|---------|------------|--------|")
        
        for test_num, profile, metrics in embb_tests:
            expected_range = (10.0, 20.0) if 'baseline' in profile.lower() else (25.0, 60.0)
            in_range = expected_range[0] <= metrics['delivery_percent'] <= expected_range[1]
            status = "✅ In Range" if in_range else "⚠️ Out of Range"
            
            lines.append(
                f"| {test_num} | {profile} | "
                f"{metrics['delivery_percent']:5.2f}% | "
                f"{status} |"
            )
        
        lines.append("")
    
    if be_tests:
        lines.append("### Best-Effort Results")
        lines.append("")
        lines.append("| Test | Profile | Delivery % | Status |")
        lines.append("|------|---------|------------|--------|")
        
        for test_num, profile, metrics in be_tests:
            expected_range = (5.0, 15.0) if 'baseline' in profile.lower() else (15.0, 50.0)
            in_range = expected_range[0] <= metrics['delivery_percent'] <= expected_range[1]
            status = "✅ In Range" if in_range else "⚠️ Out of Range"
            
            lines.append(
                f"| {test_num} | {profile} | "
                f"{metrics['delivery_percent']:5.2f}% | "
                f"{status} |"
            )
        
        lines.append("")
    
    # Go/No-Go decision
    lines.append("## Go/No-Go Decision for Article Submission")
    lines.append("")
    
    criteria = []
    
    # Check URLLC ≥90%
    urllc_pass = any(m['delivery_percent'] >= 90.0 for _, _, m in urllc_tests)
    criteria.append((urllc_pass, "URLLC ≥ 90% delivery", "✅ PASS" if urllc_pass else "❌ FAIL"))
    
    # Check eMBB baseline in range
    embb_baseline = [m for _, p, m in embb_tests if 'baseline' in p.lower()]
    embb_pass = any(10.0 <= m['delivery_percent'] <= 20.0 for m in embb_baseline) if embb_baseline else False
    criteria.append((embb_pass, "eMBB baseline 10-20%", "✅ PASS" if embb_pass else "⚠️ WARN"))
    
    # Check BE baseline in range
    be_baseline = [m for _, p, m in be_tests if 'baseline' in p.lower()]
    be_pass = any(5.0 <= m['delivery_percent'] <= 15.0 for m in be_baseline) if be_baseline else False
    criteria.append((be_pass, "Best-Effort baseline 5-15%", "✅ PASS" if be_pass else "⚠️ WARN"))
    
    lines.append("| Criterion | Status | Result |")
    lines.append("|-----------|--------|--------|")
    
    for passed, criterion, status in criteria:
        lines.append(f"| {criterion} | {status} | {'Met' if passed else 'Not Met'} |")
    
    lines.append("")
    
    all_pass = all(passed for passed, _, _ in criteria)
    
    if all_pass:
        lines.append("### ✅ **GO** - Article ready for submission")
        lines.append("")
        lines.append("All validation criteria met. Results support article claims.")
    else:
        lines.append("### ⚠️ **NO-GO** - Investigation required")
        lines.append("")
        lines.append("Some validation criteria not met. Review failing tests before submission.")
    
    return "\n".join(lines)


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 compare_validation_results.py <validation_dir>")
        print("Example: python3 compare_validation_results.py outputs/results/article_validation_20260303/")
        sys.exit(1)
    
    validation_dir = sys.argv[1]
    
    if not os.path.isdir(validation_dir):
        print(f"Error: Directory not found: {validation_dir}")
        sys.exit(1)
    
    print(f"Analyzing validation results from: {validation_dir}")
    print("")
    
    # Find test directories
    tests = find_test_directories(validation_dir)
    
    if not tests:
        print("Error: No test directories found in validation directory")
        sys.exit(1)
    
    print(f"Found {len(tests)} test directories")
    print("")
    
    # Extract metrics from each test
    test_data = []
    
    for test_num, profile, test_dir in tests:
        print(f"Processing Test {test_num} ({profile})...")
        
        # Find latency_analysis_correlation.txt
        corr_file = os.path.join(test_dir, 'latency_analysis_correlation.txt')
        
        if not os.path.exists(corr_file):
            print(f"  Warning: No correlation analysis file found")
            metrics = {}
        else:
            metrics = extract_metrics_from_correlation_file(corr_file)
            print(f"  Total commands: {metrics['total_commands']}, Delivery: {metrics['delivery_percent']:.2f}%")
        
        test_data.append((test_num, profile, test_dir, metrics))
    
    print("")
    print("Generating comparison report...")
    
    # Generate comparison table
    report = generate_comparison_table(test_data)
    
    # Save report
    report_file = os.path.join(validation_dir, 'COMPARISON_REPORT.md')
    with open(report_file, 'w') as f:
        f.write(report)
    
    print(f"Report saved to: {report_file}")
    print("")
    print("=" * 80)
    print(report)
    print("=" * 80)


if __name__ == '__main__':
    main()
