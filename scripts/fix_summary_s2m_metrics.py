#!/usr/bin/env python3
"""
Fix S2M/M2S metrics in summary files by extracting values from latency_analysis.txt.
This is called after _compute_run_metrics.py to override inconsistent summary values.
"""
import sys
import re
from pathlib import Path


def extract_section_metrics(section_text, prefix):
    """Extract count/mean/p50/p95 from one latency section and map to summary keys."""
    metrics = {}

    count_match = re.search(r'Count:\s*(\d+)', section_text)
    if count_match:
        count_value = count_match.group(1)
        metrics[f'{prefix}_total_count'] = count_value
        metrics[f'{prefix}_matched_pairs'] = count_value

    mean_match = re.search(r'Mean:\s*([\d.]+)', section_text)
    if mean_match:
        metrics[f'mean_{prefix}_ms'] = mean_match.group(1)

    p50_match = re.search(r'P50:\s*([\d.]+)', section_text)
    if p50_match:
        metrics[f'median_{prefix}_ms'] = p50_match.group(1)

    p95_match = re.search(r'P95:\s*([\d.]+)', section_text)
    if p95_match:
        metrics[f'P95_{prefix}_ms'] = p95_match.group(1)

    return metrics


def extract_correlation_m2s_metrics(correlation_file):
    """Extract M2S metrics from latency_analysis_correlation.txt (correlation_id-based)."""
    if not Path(correlation_file).exists():
        return {}
    
    metrics = {}
    with open(correlation_file, 'r') as f:
        content = f.read()
    
    # Extract M2S sent count from "Total commands sent: 167"
    sent_match = re.search(r'Total commands sent:\s*(\d+)', content)
    if sent_match:
        metrics['M2S_sent_count'] = sent_match.group(1)
    
    # Extract unique eventual delivery count from "Eventual Delivery (≤2000ms): 122 (73.05%)"
    # This is correlation-id based and avoids inflated totals when duplicate responses exist.
    delivery_match = re.search(r'Eventual Delivery.*?(\d+)\s*\((\d+\.\d+)%\)', content)
    if delivery_match:
        delivered_count = delivery_match.group(1)
        metrics['M2S_received_count'] = delivered_count
        metrics['M2S_matched_pairs'] = delivered_count
        metrics['M2S_total_count'] = delivered_count
        metrics['R_m2s_event_percent'] = delivery_match.group(2)
    
    # Keep total raw responses as auxiliary metric (may include duplicates/retries)
    total_resp_match = re.search(r'Total responses received:\s*(\d+)', content)
    if total_resp_match:
        metrics['M2S_total_responses_raw'] = total_resp_match.group(1)
    
    # Extract M2S latencies from "All Delivery Latencies (eventual)" section
    latency_section_match = re.search(r'📊 All Delivery Latencies \(eventual\).*?(?=📊|\Z)', content, re.DOTALL)
    if latency_section_match:
        latency_text = latency_section_match.group(0)
        
        count_match = re.search(r'Count:\s*(\d+)', latency_text)
        if count_match and 'M2S_matched_pairs' not in metrics:
            metrics['M2S_matched_pairs'] = count_match.group(1)
            metrics['M2S_total_count'] = count_match.group(1)
        
        mean_match = re.search(r'Mean:\s*([\d.]+)', latency_text)
        if mean_match:
            metrics['mean_M2S_ms'] = mean_match.group(1)
        
        p50_match = re.search(r'P50:\s*([\d.]+)', latency_text)
        if p50_match:
            metrics['median_M2S_ms'] = p50_match.group(1)
        
        p95_match = re.search(r'P95:\s*([\d.]+)', latency_text)
        if p95_match:
            metrics['P95_M2S_ms'] = p95_match.group(1)
            metrics['P95_ms'] = p95_match.group(1)  # Legacy key
    
    return metrics


def extract_latency_metrics(latency_file):
    """Extract S2M and M2S metrics from latency_analysis.txt."""
    if not Path(latency_file).exists():
        return None
    
    metrics = {}
    with open(latency_file, 'r') as f:
        content = f.read()
    
    # Find S2M Latencies section
    s2m_match = re.search(r'📊 S2M Latencies.*?(?=📊|\Z)', content, re.DOTALL)
    if s2m_match:
        metrics.update(extract_section_metrics(s2m_match.group(0), 'S2M'))

    # Find M2S Latencies section
    m2s_match = re.search(r'📊 M2S Latencies.*?(?=📊|\Z)', content, re.DOTALL)
    if m2s_match:
        metrics.update(extract_section_metrics(m2s_match.group(0), 'M2S'))
        # Keep legacy key aligned with M2S p95 for backward-compatible consumers.
        if 'P95_M2S_ms' in metrics:
            metrics['P95_ms'] = metrics['P95_M2S_ms']

    # Extract key ratios from the Summary section when available
    summary_match = re.search(r'📊 Summary.*?(?=📊|\Z)', content, re.DOTALL)
    if summary_match:
        summary_section = summary_match.group(0)
        r_event_match = re.search(r'R_m2s_event_percent:\s*([\d.]+)', summary_section)
        if r_event_match:
            metrics['R_m2s_event_percent'] = r_event_match.group(1)
        r_pair_match = re.search(r'R_m2s_pair_percent:\s*([\d.]+)', summary_section)
        if r_pair_match:
            metrics['R_m2s_pair_percent'] = r_pair_match.group(1)
    
    return metrics if metrics else None


def update_summary(summary_file, latency_metrics):
    """Update summary file with corrected latency metrics."""
    if not Path(summary_file).exists():
        print(f"ERROR: Summary file not found: {summary_file}")
        return False
    
    with open(summary_file, 'r') as f:
        content = f.read()
    
    original_content = content
    
    # Replace each metric (or append if not present)
    for key, value in latency_metrics.items():
        # Pattern: "key: any_value" (handles both 0.0 and already-set values)
        pattern = rf'^{key}:\s*[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?'
        replacement = f'{key}: {value}'
        if re.search(pattern, content, flags=re.MULTILINE):
            content = re.sub(pattern, replacement, content, flags=re.MULTILINE)
        else:
            if not content.endswith('\n'):
                content += '\n'
            content += replacement + '\n'
    
    # Check if replacements were made
    if content == original_content:
        print(f"WARNING: No replacements made. Summary might not have expected format.")
        return False
    
    with open(summary_file, 'w') as f:
        f.write(content)
    
    return True


def main():
    if len(sys.argv) < 2:
        print("Usage: fix_summary_s2m_metrics.py <summary_file> [latency_analysis_file]")
        print("\nIf latency_analysis_file not provided, looks for it in same directory as summary")
        sys.exit(1)
    
    summary_file = sys.argv[1]
    
    # Find latency_analysis.txt
    if len(sys.argv) > 2:
        latency_file = sys.argv[2]
    else:
        # Look in same directory as summary
        summary_dir = Path(summary_file).parent
        latency_file = summary_dir / 'latency_analysis.txt'
    
    # Also check for correlation file in same directory
    correlation_file = Path(latency_file).parent / 'latency_analysis_correlation.txt'
    
    print(f"📝 Fixing latency metrics in summary...")
    print(f"   Summary: {summary_file}")
    print(f"   Latency: {latency_file}")
    print(f"   Correlation: {correlation_file}")
    
    # Extract metrics from latency_analysis.txt (S2M + M2S if available)
    latency_metrics = extract_latency_metrics(str(latency_file))
    if not latency_metrics:
        latency_metrics = {}
    
    # Extract M2S metrics from correlation analysis (more accurate, takes priority)
    correlation_metrics = extract_correlation_m2s_metrics(correlation_file)
    if correlation_metrics:
        print(f"✅ Found correlation-based M2S metrics: {correlation_metrics}")
        # Merge with priority to correlation (overwrites any M2S from latency_analysis)
        latency_metrics.update(correlation_metrics)
    
    if not latency_metrics:
        print(f"❌ Could not extract any metrics from {latency_file} or {correlation_file}")
        sys.exit(1)
    
    print(f"✅ Final metrics to apply: {latency_metrics}")
    
    # Update summary
    if update_summary(summary_file, latency_metrics):
        print(f"✅ Summary updated successfully!")
        print(f"\n   {latency_metrics}")
        sys.exit(0)
    else:
        print(f"❌ Failed to update summary")
        sys.exit(1)


if __name__ == '__main__':
    main()
