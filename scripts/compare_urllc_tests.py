#!/usr/bin/env python3
"""
Comparação Inteligente entre Múltiplos Testes URLLC
Identifica tendências, melhorias e regressões entre testes
"""

import pandas as pd
import numpy as np
import sys
import os
from pathlib import Path
import json
from datetime import datetime

def parse_test_timestamp(test_dir_name):
    """Extrai timestamp do nome do diretório de teste"""
    try:
        # Format: test_20251006T004352Z_urllc
        parts = test_dir_name.split('_')
        if len(parts) >= 2:
            timestamp_str = parts[1]  # 20251006T004352Z
            # Convert to datetime for sorting
            return datetime.strptime(timestamp_str, '%Y%m%dT%H%M%SZ')
    except:
        pass
    return datetime.min

def analyze_single_test(test_dir):
    """Análise condensada de um único teste"""
    reports_dir = test_dir / "generated_reports"
    odte_files = list(reports_dir.glob("*odte*.csv"))
    s2m_files = list(reports_dir.glob("*simulator_to_middts*.csv"))
    m2s_files = list(reports_dir.glob("*middts_to_simulator*.csv"))
    
    if not odte_files:
        return None
    
    # ODTE Analysis
    df = pd.read_csv(odte_files[0])
    total_sensors = len(df)
    sensors_with_s2m = (df['sim_sent_count'] > 0).sum()
    sensors_with_m2s = (df['middts_sent_count'] > 0).sum()
    sensors_bidirectional = ((df['sim_sent_count'] > 0) & (df['middts_sent_count'] > 0)).sum()
    odte_general = df['A'].mean()
    odte_bidirectional = df[(df['sim_sent_count'] > 0) & (df['middts_sent_count'] > 0)]['A'].mean() if sensors_bidirectional > 0 else 0
    
    result = {
        'test_dir': test_dir.name,
        'timestamp': parse_test_timestamp(test_dir.name),
        'total_sensors': total_sensors,
        'sensors_s2m': sensors_with_s2m,
        'sensors_m2s': sensors_with_m2s,
        'sensors_bidirectional': sensors_bidirectional,
        'odte_general': odte_general,
        'odte_bidirectional': odte_bidirectional,
        's2m_latency_avg': 0,
        'm2s_latency_avg': 0,
        's2m_p95': 0,
        'm2s_p95': 0,
        'urllc_s2m_compliance': 0,
        'urllc_m2s_compliance': 0
    }
    
    # Latency Analysis
    if s2m_files:
        s2m_df = pd.read_csv(s2m_files[0])
        s2m_active = s2m_df[s2m_df['count'] > 0]
        if len(s2m_active) > 0:
            result['s2m_latency_avg'] = s2m_active['mean_ms'].mean()
            result['s2m_p95'] = s2m_active['p95_ms'].mean()
            result['urllc_s2m_compliance'] = (s2m_active['p95_ms'] < 200).sum() / len(s2m_active) * 100
    
    if m2s_files:
        m2s_df = pd.read_csv(m2s_files[0])
        m2s_active = m2s_df[m2s_df['count'] > 0]
        if len(m2s_active) > 0:
            result['m2s_latency_avg'] = m2s_active['mean_ms'].mean()
            result['m2s_p95'] = m2s_active['p95_ms'].mean()
            result['urllc_m2s_compliance'] = (m2s_active['p95_ms'] < 200).sum() / len(m2s_active) * 100
    
    return result

def format_change(old_val, new_val, higher_is_better=True, unit=""):
    """Formata mudança percentual com emoji indicativo"""
    if old_val == 0 and new_val == 0:
        return "➖ sem mudança"
    if old_val == 0:
        return f"🆕 {new_val:.1f}{unit}"
    
    change_pct = (new_val - old_val) / old_val * 100
    change_abs = new_val - old_val
    
    if abs(change_pct) < 1.0:
        emoji = "➖"  # stable
        direction = "estável"
    elif (change_pct > 0 and higher_is_better) or (change_pct < 0 and not higher_is_better):
        emoji = "✅"  # improvement
        direction = "melhor" if higher_is_better else "menor"
    else:
        emoji = "⚠️"  # worse
        direction = "pior" if higher_is_better else "maior"
    
    return f"{emoji} {direction} ({change_pct:+.1f}%, {change_abs:+.1f}{unit})"

def compare_tests(tests_data):
    """Compara testes e identifica tendências"""
    print(f"\n📊 COMPARAÇÃO ENTRE TESTES URLLC")
    print("=" * 60)
    
    # Sort by timestamp
    tests_data.sort(key=lambda x: x['timestamp'])
    
    if len(tests_data) < 2:
        print("⚠️ Apenas um teste encontrado. Comparação não possível.")
        return
    
    print(f"📅 Período analisado: {tests_data[0]['timestamp'].strftime('%Y-%m-%d %H:%M')} → {tests_data[-1]['timestamp'].strftime('%Y-%m-%d %H:%M')}")
    print(f"🔢 Total de testes: {len(tests_data)}")
    
    # Compare first vs last
    first_test = tests_data[0]
    last_test = tests_data[-1]
    
    print(f"\n🔍 COMPARAÇÃO DETALHADA:")
    print(f"   📁 Teste mais antigo: {first_test['test_dir']}")
    print(f"   📁 Teste mais recente: {last_test['test_dir']}")
    
    print(f"\n📈 PERFORMANCE (LATÊNCIAS):")
    print(f"   S2M Latência Média: {last_test['s2m_latency_avg']:.1f}ms ← {first_test['s2m_latency_avg']:.1f}ms")
    print(f"   {format_change(first_test['s2m_latency_avg'], last_test['s2m_latency_avg'], False, 'ms')}")
    print(f"   M2S Latência Média: {last_test['m2s_latency_avg']:.1f}ms ← {first_test['m2s_latency_avg']:.1f}ms")
    print(f"   {format_change(first_test['m2s_latency_avg'], last_test['m2s_latency_avg'], False, 'ms')}")
    
    print(f"\n🎯 URLLC COMPLIANCE:")
    print(f"   S2M (<200ms P95): {last_test['urllc_s2m_compliance']:.1f}% ← {first_test['urllc_s2m_compliance']:.1f}%")
    print(f"   {format_change(first_test['urllc_s2m_compliance'], last_test['urllc_s2m_compliance'], True, '%')}")
    print(f"   M2S (<200ms P95): {last_test['urllc_m2s_compliance']:.1f}% ← {first_test['urllc_m2s_compliance']:.1f}%")
    print(f"   {format_change(first_test['urllc_m2s_compliance'], last_test['urllc_m2s_compliance'], True, '%')}")
    
    print(f"\n📊 ODTE (EFICIÊNCIA):")
    print(f"   ODTE Geral: {last_test['odte_general']:.3f} ← {first_test['odte_general']:.3f}")
    print(f"   {format_change(first_test['odte_general'], last_test['odte_general'], True, '')}")
    print(f"   ODTE Bidirectional: {last_test['odte_bidirectional']:.3f} ← {first_test['odte_bidirectional']:.3f}")
    print(f"   {format_change(first_test['odte_bidirectional'], last_test['odte_bidirectional'], True, '')}")
    
    print(f"\n🔌 CONECTIVIDADE:")
    print(f"   Sensores S2M: {last_test['sensors_s2m']}/{last_test['total_sensors']} ← {first_test['sensors_s2m']}/{first_test['total_sensors']}")
    print(f"   {format_change(first_test['sensors_s2m'], last_test['sensors_s2m'], True, ' sensores')}")
    print(f"   Sensores M2S: {last_test['sensors_m2s']}/{last_test['total_sensors']} ← {first_test['sensors_m2s']}/{first_test['total_sensors']}")
    print(f"   {format_change(first_test['sensors_m2s'], last_test['sensors_m2s'], True, ' sensores')}")
    
    # Trend analysis
    print(f"\n📈 ANÁLISE DE TENDÊNCIAS:")
    if len(tests_data) >= 3:
        # Check if performance is improving over time
        s2m_trend = [t['s2m_latency_avg'] for t in tests_data if t['s2m_latency_avg'] > 0]
        m2s_trend = [t['m2s_latency_avg'] for t in tests_data if t['m2s_latency_avg'] > 0]
        odte_trend = [t['odte_general'] for t in tests_data]
        
        if len(s2m_trend) >= 3:
            s2m_improving = s2m_trend[-1] < s2m_trend[0]  # Lower is better
            print(f"   S2M: {'✅ Melhorando' if s2m_improving else '⚠️ Degradando'} ao longo do tempo")
        
        if len(m2s_trend) >= 3:
            m2s_improving = m2s_trend[-1] < m2s_trend[0]  # Lower is better
            print(f"   M2S: {'✅ Melhorando' if m2s_improving else '⚠️ Degradando'} ao longo do tempo")
        
        if len(odte_trend) >= 3:
            odte_improving = odte_trend[-1] > odte_trend[0]  # Higher is better
            print(f"   ODTE: {'✅ Melhorando' if odte_improving else '⚠️ Degradando'} ao longo do tempo")
    
    # Overall assessment
    print(f"\n🏆 AVALIAÇÃO GERAL:")
    improvements = 0
    total_metrics = 0
    
    metrics_analysis = [
        (first_test['s2m_latency_avg'], last_test['s2m_latency_avg'], False, "S2M Latency"),
        (first_test['m2s_latency_avg'], last_test['m2s_latency_avg'], False, "M2S Latency"),
        (first_test['urllc_s2m_compliance'], last_test['urllc_s2m_compliance'], True, "S2M Compliance"),
        (first_test['urllc_m2s_compliance'], last_test['urllc_m2s_compliance'], True, "M2S Compliance"),
        (first_test['odte_general'], last_test['odte_general'], True, "ODTE"),
    ]
    
    for old_val, new_val, higher_better, name in metrics_analysis:
        if old_val > 0 and new_val > 0:  # Only count if both have valid data
            total_metrics += 1
            change_pct = (new_val - old_val) / old_val * 100
            if (change_pct > 1 and higher_better) or (change_pct < -1 and not higher_better):
                improvements += 1
    
    if total_metrics > 0:
        improvement_rate = improvements / total_metrics * 100
        if improvement_rate >= 60:
            status = "✅ SISTEMA MELHORANDO"
        elif improvement_rate >= 40:
            status = "➖ SISTEMA ESTÁVEL"
        else:
            status = "⚠️ ATENÇÃO NECESSÁRIA"
        
        print(f"   {status} ({improvements}/{total_metrics} métricas melhoraram)")
    
def main():
    if len(sys.argv) < 2:
        print("Usage: python3 compare_urllc_tests.py <results_directory>")
        print("Example: python3 compare_urllc_tests.py results/")
        sys.exit(1)
    
    results_dir = Path(sys.argv[1])
    
    # Find all URLLC test directories
    urllc_tests = list(results_dir.glob("test_*_urllc"))
    
    if not urllc_tests:
        print(f"❌ Nenhum teste URLLC encontrado em {results_dir}")
        sys.exit(1)
    
    print(f"🔍 Encontrados {len(urllc_tests)} testes URLLC")
    
    # Analyze each test
    tests_data = []
    for test_dir in urllc_tests:
        print(f"   Analisando {test_dir.name}...")
        test_result = analyze_single_test(test_dir)
        if test_result:
            tests_data.append(test_result)
    
    if not tests_data:
        print("❌ Nenhum teste válido encontrado")
        sys.exit(1)
    
    print(f"✅ {len(tests_data)} testes analisados com sucesso")
    
    # Perform comparison
    compare_tests(tests_data)
    
    # Summary table
    print(f"\n📋 TABELA RESUMO:")
    print("=" * 100)
    print(f"{'Teste':<25} {'S2M(ms)':<8} {'M2S(ms)':<8} {'ODTE':<6} {'S2M%':<6} {'M2S%':<6} {'Bi':<3}")
    print("-" * 100)
    
    for test in sorted(tests_data, key=lambda x: x['timestamp']):
        print(f"{test['test_dir']:<25} "
              f"{test['s2m_latency_avg']:>7.1f} "
              f"{test['m2s_latency_avg']:>7.1f} "
              f"{test['odte_general']:>5.1%} "
              f"{test['urllc_s2m_compliance']:>5.0f} "
              f"{test['urllc_m2s_compliance']:>5.0f} "
              f"{test['sensors_bidirectional']:>2}")

if __name__ == "__main__":
    main()