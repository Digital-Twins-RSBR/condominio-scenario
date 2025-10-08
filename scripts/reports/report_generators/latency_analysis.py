#!/usr/bin/env python3
"""
Análise detalhada de latências para investigar causas de alta latência.
Integrado ao workflow make odte-full para diagnóstico automático.
"""
import csv
import sys
import os
import subprocess
from datetime import datetime
from collections import defaultdict
import statistics

def analyze_latency_causes(reports_dir):
    """Analisa as causas das latências altas nos relatórios ODTE."""
    
    print("="*60)
    print("🔍 ANÁLISE DETALHADA DE LATÊNCIAS")
    print("="*60)
    
    # Arquivos necessários
    files = os.listdir(reports_dir)
    s2m_file = os.path.join(reports_dir, [f for f in files if '_latencia_stats_simulator_to_middts_' in f and f.endswith('.csv')][0])
    m2s_file = os.path.join(reports_dir, [f for f in files if '_latencia_stats_middts_to_simulator_' in f and f.endswith('.csv')][0])
    odte_file = os.path.join(reports_dir, [f for f in files if '_odte_' in f and f.endswith('.csv')][0])
    
    # Análise S2M (Simulator to Middleware)
    print("\n📊 S2M (Simulator → Middleware)")
    print("-" * 40)
    s2m_stats = analyze_direction_stats(s2m_file, "S2M")
    
    # Análise M2S (Middleware to Simulator)  
    print("\n📊 M2S (Middleware → Simulator)")
    print("-" * 40)
    m2s_stats = analyze_direction_stats(m2s_file, "M2S")
    
    # Análise de conectividade
    print("\n🔌 ANÁLISE DE CONECTIVIDADE")
    print("-" * 40)
    connectivity_analysis(odte_file)
    
    # Diagnóstico de gargalos
    print("\n⚠️ DIAGNÓSTICO DE GARGALOS")
    print("-" * 40)
    diagnose_bottlenecks(s2m_stats, m2s_stats)
    
    # Recomendações
    print("\n💡 RECOMENDAÇÕES DE OTIMIZAÇÃO")
    print("-" * 40)
    provide_recommendations(s2m_stats, m2s_stats)
    
    print("\n" + "="*60)

def analyze_direction_stats(csv_file, direction):
    """Analisa estatísticas de latência para uma direção específica."""
    
    stats = {
        'active_sensors': 0,
        'total_sensors': 0,
        'latencies': [],
        'within_target': 0,
        'target_ms': 200
    }
    
    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            stats['total_sensors'] += 1
            count = int(row['count'])
            if count > 0:
                stats['active_sensors'] += 1
                mean_ms = float(row['mean_ms'])
                stats['latencies'].append(mean_ms)
                if mean_ms < stats['target_ms']:
                    stats['within_target'] += 1
    
    # Estatísticas calculadas
    if stats['latencies']:
        stats['mean'] = statistics.mean(stats['latencies'])
        stats['median'] = statistics.median(stats['latencies'])
        stats['min'] = min(stats['latencies'])
        stats['max'] = max(stats['latencies'])
        if len(stats['latencies']) > 1:
            stats['stdev'] = statistics.stdev(stats['latencies'])
        else:
            stats['stdev'] = 0
    else:
        stats.update({'mean': 0, 'median': 0, 'min': 0, 'max': 0, 'stdev': 0})
    
    # Impressão dos resultados
    connectivity_pct = (stats['active_sensors'] / stats['total_sensors'] * 100) if stats['total_sensors'] > 0 else 0
    target_pct = (stats['within_target'] / stats['active_sensors'] * 100) if stats['active_sensors'] > 0 else 0
    
    print(f"   Sensores ativos: {stats['active_sensors']}/{stats['total_sensors']} ({connectivity_pct:.1f}%)")
    
    if stats['active_sensors'] > 0:
        print(f"   Latência média: {stats['mean']:.1f}ms")
        print(f"   Mediana: {stats['median']:.1f}ms")
        print(f"   Mín/Máx: {stats['min']:.1f}ms / {stats['max']:.1f}ms")
        print(f"   Desvio padrão: {stats['stdev']:.1f}ms")
        print(f"   Dentro da meta (<200ms): {stats['within_target']}/{stats['active_sensors']} ({target_pct:.1f}%)")
        
        # Classificação de performance
        if target_pct >= 80:
            status = "✅ EXCELENTE"
        elif target_pct >= 60:
            status = "⚠️  BOM"
        elif target_pct >= 40:
            status = "🟡 REGULAR" 
        elif target_pct >= 20:
            status = "🔴 RUIM"
        else:
            status = "❌ CRÍTICO"
        
        print(f"   Status: {status}")
    else:
        print("   ❌ NENHUMA COMUNICAÇÃO DETECTADA")
    
    return stats

def connectivity_analysis(odte_file):
    """Analisa problemas de conectividade entre sensores."""
    
    s2m_active = 0
    m2s_active = 0
    total_sensors = 0
    
    with open(odte_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            total_sensors += 1
            if int(row['sim_sent_count']) > 0:
                s2m_active += 1
            if int(row['middts_sent_count']) > 0:
                m2s_active += 1
    
    s2m_pct = (s2m_active / total_sensors * 100) if total_sensors > 0 else 0
    m2s_pct = (m2s_active / total_sensors * 100) if total_sensors > 0 else 0
    
    print(f"   Total de sensores: {total_sensors}")
    print(f"   S2M ativos: {s2m_active} ({s2m_pct:.1f}%)")
    print(f"   M2S ativos: {m2s_active} ({m2s_pct:.1f}%)")
    
    if s2m_pct < 50:
        print("   ⚠️  Baixa conectividade S2M - verificar MQTT publishers")
    if m2s_pct < 50:
        print("   ⚠️  Baixa conectividade M2S - verificar MQTT RPC")

def diagnose_bottlenecks(s2m_stats, m2s_stats):
    """Identifica gargalos específicos baseado nas estatísticas."""
    
    issues = []
    
    # Análise S2M
    if s2m_stats['active_sensors'] > 0:
        if s2m_stats['mean'] > 300:
            issues.append("🔴 S2M: Latência muito alta (>300ms) - verificar sobrecarga ThingsBoard")
        elif s2m_stats['mean'] > 200:
            issues.append("🟡 S2M: Latência acima da meta - verificar processamento middleware")
        
        if s2m_stats['stdev'] > 100:
            issues.append("🟡 S2M: Alta variabilidade - verificar instabilidade de rede")
    else:
        issues.append("❌ S2M: Sem comunicação - verificar MQTT publishers")
    
    # Análise M2S
    if m2s_stats['active_sensors'] > 0:
        if m2s_stats['mean'] > 1000:
            issues.append("🔴 M2S: Latência crítica (>1s) - verificar timeouts RPC")
        elif m2s_stats['mean'] > 500:
            issues.append("🟡 M2S: Latência alta - verificar conectividade MQTT")
        
        if m2s_stats['stdev'] > 500:
            issues.append("🟡 M2S: Variabilidade extrema - verificar retry logic")
    else:
        issues.append("❌ M2S: Sem comunicação - verificar MQTT RPC subscribers")
    
    # Problemas de conectividade
    s2m_connectivity = (s2m_stats['active_sensors'] / s2m_stats['total_sensors'] * 100) if s2m_stats['total_sensors'] > 0 else 0
    m2s_connectivity = (m2s_stats['active_sensors'] / m2s_stats['total_sensors'] * 100) if m2s_stats['total_sensors'] > 0 else 0
    
    if s2m_connectivity < 80:
        issues.append(f"🟡 S2M: Conectividade baixa ({s2m_connectivity:.1f}%)")
    if m2s_connectivity < 80:
        issues.append(f"🟡 M2S: Conectividade baixa ({m2s_connectivity:.1f}%)")
    
    if not issues:
        print("   ✅ Nenhum gargalo crítico identificado")
    else:
        for issue in issues:
            print(f"   {issue}")

def provide_recommendations(s2m_stats, m2s_stats):
    """Fornece recomendações específicas baseadas nas métricas."""
    
    recommendations = []
    
    # Recomendações S2M
    if s2m_stats['active_sensors'] > 0 and s2m_stats['mean'] > 200:
        recommendations.append("⚡ Reduzir HEARTBEAT_INTERVAL de 5s para 3s ou 2s")
        recommendations.append("⚙️ Otimizar processamento de telemetria no middleware")
        if s2m_stats['stdev'] > 100:
            recommendations.append("🔧 Implementar buffer/queue para suavizar latências")
    
    # Recomendações M2S
    if m2s_stats['active_sensors'] > 0 and m2s_stats['mean'] > 500:
        recommendations.append("🚀 Reduzir timeout MQTT de 10s para 5s")
        recommendations.append("🔁 Implementar retry com backoff exponencial otimizado")
        recommendations.append("💾 Adicionar cache local para RPC responses")
    
    # Recomendações de conectividade
    s2m_connectivity = (s2m_stats['active_sensors'] / s2m_stats['total_sensors'] * 100) if s2m_stats['total_sensors'] > 0 else 0
    m2s_connectivity = (m2s_stats['active_sensors'] / m2s_stats['total_sensors'] * 100) if m2s_stats['total_sensors'] > 0 else 0
    
    if s2m_connectivity < 80:
        recommendations.append("🔎 Verificar configuração MQTT publishers nos simuladores")
    if m2s_connectivity < 80:
        recommendations.append("📡 Verificar configuração MQTT RPC subscribers")
    
    # Recomendações específicas por cenário
    if s2m_stats.get('mean', 0) < 200 and m2s_stats.get('mean', 0) > 1000:
        recommendations.append("🎯 Foco na otimização M2S - S2M já está próximo da meta")
    elif s2m_stats.get('mean', 0) > 200 and m2s_stats.get('mean', 0) < 500:
        recommendations.append("🎯 Foco na otimização S2M - M2S está melhor")
    
    if not recommendations:
        recommendations.append("✅ Sistema funcionando dentro dos parâmetros esperados")
    
    for i, rec in enumerate(recommendations, 1):
        print(f"   {i}. {rec}")

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 latency_analysis.py <reports_dir>")
        sys.exit(1)
    
    reports_dir = sys.argv[1]
    
    if not os.path.exists(reports_dir):
        print(f"❌ Reports directory not found: {reports_dir}")
        sys.exit(1)
    
    analyze_latency_causes(reports_dir)

if __name__ == "__main__":
    main()
