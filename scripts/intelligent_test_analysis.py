#!/usr/bin/env python3
"""
Análise Inteligente de Resultados URLLC
Detecta anomalias e fornece insights detalhados sobre performance
"""

import pandas as pd
import numpy as np
import sys
import os
from pathlib import Path

def analyze_odte_data(odte_file):
    """Análise profunda dos dados ODTE"""
    print(f"🔍 ANÁLISE INTELIGENTE DO TESTE URLLC")
    print(f"📁 Arquivo: {odte_file}")
    print("=" * 60)
    
    # Carregar dados
    df = pd.read_csv(odte_file)
    
    # Análise de sensores
    total_sensors = len(df)
    sensors_with_s2m = (df['sim_sent_count'] > 0).sum()
    sensors_with_m2s = (df['middts_sent_count'] > 0).sum()
    sensors_bidirectional = ((df['sim_sent_count'] > 0) & (df['middts_sent_count'] > 0)).sum()
    sensors_inactive = ((df['sim_sent_count'] == 0) & (df['middts_sent_count'] == 0)).sum()
    
    print(f"📊 ANÁLISE DE CONECTIVIDADE:")
    print(f"   Total de sensores configurados: {total_sensors}")
    print(f"   Sensores S2M ativos: {sensors_with_s2m} ({sensors_with_s2m/total_sensors*100:.1f}%)")
    print(f"   Sensores M2S ativos: {sensors_with_m2s} ({sensors_with_m2s/total_sensors*100:.1f}%)")
    print(f"   Sensores bidirecionais: {sensors_bidirectional} ({sensors_bidirectional/total_sensors*100:.1f}%)")
    print(f"   Sensores inativos: {sensors_inactive} ({sensors_inactive/total_sensors*100:.1f}%)")
    
    # ODTE Analysis
    odte_all = df['A'].mean()
    odte_active_only = df[df['A'] > 0]['A'].mean() if (df['A'] > 0).any() else 0
    odte_bidirectional = df[(df['sim_sent_count'] > 0) & (df['middts_sent_count'] > 0)]['A'].mean() if sensors_bidirectional > 0 else 0
    
    print(f"\n📈 ANÁLISE ODTE (EFICIÊNCIA):")
    print(f"   ODTE médio geral: {odte_all:.3f} ({odte_all*100:.1f}%)")
    print(f"   ODTE médio (sensores ativos): {odte_active_only:.3f} ({odte_active_only*100:.1f}%)")
    print(f"   ODTE médio (bidirecionais): {odte_bidirectional:.3f} ({odte_bidirectional*100:.1f}%)")
    
    # Detectar anomalias
    print(f"\n🚨 DETECÇÃO DE ANOMALIAS:")
    
    if sensors_inactive > total_sensors * 0.3:
        print(f"   ⚠️  ALTO NÚMERO DE SENSORES INATIVOS ({sensors_inactive}/{total_sensors})")
        print(f"       Possível problema: Configuração MQTT ou registro de dispositivos")
    
    if sensors_bidirectional < total_sensors * 0.2:
        print(f"   ⚠️  BAIXA COMUNICAÇÃO BIDIRECIONAL ({sensors_bidirectional}/{total_sensors})")
        print(f"       Possível problema: Middleware não conseguindo responder aos sensores")
    
    # Análise por simulador (baseado no padrão do UUID)
    df['simulator'] = df['sensor'].apply(lambda x: extract_simulator_from_uuid(x))
    sim_stats = df.groupby('simulator').agg({
        'sim_sent_count': 'sum',
        'middts_sent_count': 'sum',
        'A': 'mean'
    }).round(3)
    
    print(f"\n🤖 ANÁLISE POR SIMULADOR:")
    for sim, stats in sim_stats.iterrows():
        if sim != 'unknown':
            status = "✅" if stats['A'] > 0.8 else "⚠️" if stats['A'] > 0.5 else "❌"
            print(f"   {status} {sim}: S2M={stats['sim_sent_count']:>3}, M2S={stats['middts_sent_count']:>3}, ODTE={stats['A']:.3f}")
    
    # Recomendações baseadas em dados
    print(f"\n💡 RECOMENDAÇÕES INTELIGENTES:")
    
    if odte_all < 0.5:
        print(f"   🔧 CRÍTICO: ODTE muito baixo - Verificar conectividade básica")
    elif odte_all < 0.7:
        print(f"   ⚡ MÉDIO: ODTE abaixo do ideal - Otimizar configurações")
    else:
        print(f"   ✅ BOM: ODTE dentro do esperado")
    
    if sensors_inactive > 20:
        print(f"   🔌 Verificar se todos os containers simuladores estão rodando")
        print(f"   📡 Verificar configuração MQTT_BROKER nos simuladores")
        print(f"   🔍 Verificar logs dos simuladores para erros de conexão")
    
    if sensors_with_m2s < sensors_with_s2m * 0.5:
        print(f"   📤 M2S muito baixo - Verificar middleware Django")
        print(f"   ⚙️ Verificar configuração RPC no ThingsBoard")
        print(f"   🕐 Verificar timeouts de RPC")
    
    return {
        'total_sensors': total_sensors,
        'active_s2m': sensors_with_s2m,
        'active_m2s': sensors_with_m2s,
        'bidirectional': sensors_bidirectional,
        'odte_general': odte_all,
        'odte_active': odte_active_only,
        'odte_bidirectional': odte_bidirectional
    }

def extract_simulator_from_uuid(uuid_str):
    """Extrai identificador do simulador baseado no padrão UUID"""
    try:
        # UUIDs seguem padrão onde parte do meio indica o simulador
        parts = uuid_str.split('-')
        if len(parts) >= 3:
            return f"sim_{parts[2][:4]}"
        return "unknown"
    except:
        return "unknown"

def analyze_latency_data(s2m_file, m2s_file):
    """Análise inteligente de latências"""
    print(f"\n🚀 ANÁLISE DE LATÊNCIAS:")
    print("=" * 40)
    
    # S2M Analysis
    s2m_df = pd.read_csv(s2m_file)
    s2m_active = s2m_df[s2m_df['count'] > 0]
    
    print(f"📈 S2M (Sensor → Middleware):")
    if len(s2m_active) > 0:
        print(f"   Sensores ativos: {len(s2m_active)}")
        print(f"   Latência média: {s2m_active['mean_ms'].mean():.1f}ms")
        print(f"   Mediana: {s2m_active['median_ms'].mean():.1f}ms")
        print(f"   P95 médio: {s2m_active['p95_ms'].mean():.1f}ms")
        urllc_compliant = (s2m_active['p95_ms'] < 200).sum()
        print(f"   URLLC compliant (<200ms P95): {urllc_compliant}/{len(s2m_active)} ({urllc_compliant/len(s2m_active)*100:.1f}%)")
    else:
        print(f"   ❌ Nenhum sensor S2M ativo!")
    
    # M2S Analysis
    m2s_df = pd.read_csv(m2s_file)
    m2s_active = m2s_df[m2s_df['count'] > 0]
    
    print(f"\n📉 M2S (Middleware → Sensor):")
    if len(m2s_active) > 0:
        print(f"   Sensores ativos: {len(m2s_active)}")
        print(f"   Latência média: {m2s_active['mean_ms'].mean():.1f}ms")
        print(f"   Mediana: {m2s_active['median_ms'].mean():.1f}ms")
        print(f"   P95 médio: {m2s_active['p95_ms'].mean():.1f}ms")
        urllc_compliant = (m2s_active['p95_ms'] < 200).sum()
        print(f"   URLLC compliant (<200ms P95): {urllc_compliant}/{len(m2s_active)} ({urllc_compliant/len(m2s_active)*100:.1f}%)")
    else:
        print(f"   ❌ Nenhum sensor M2S ativo!")

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 intelligent_test_analysis.py <test_directory>")
        sys.exit(1)
    
    test_dir = Path(sys.argv[1])
    reports_dir = test_dir / "generated_reports"
    
    # Encontrar arquivos de relatório
    odte_files = list(reports_dir.glob("*odte*.csv"))
    s2m_files = list(reports_dir.glob("*simulator_to_middts*.csv"))
    m2s_files = list(reports_dir.glob("*middts_to_simulator*.csv"))
    
    if not odte_files:
        print(f"❌ Arquivo ODTE não encontrado em {reports_dir}")
        sys.exit(1)
    
    # Análise principal
    odte_stats = analyze_odte_data(odte_files[0])
    
    if s2m_files and m2s_files:
        analyze_latency_data(s2m_files[0], m2s_files[0])
    
    # Sumário final
    print(f"\n🎯 SUMÁRIO EXECUTIVO:")
    print("=" * 30)
    overall_health = "✅ EXCELENTE" if odte_stats['odte_general'] > 0.8 else \
                    "⚠️ ACEITÁVEL" if odte_stats['odte_general'] > 0.5 else \
                    "❌ CRÍTICO"
    print(f"Status Geral: {overall_health}")
    print(f"Eficiência ODTE: {odte_stats['odte_general']*100:.1f}%")
    print(f"Sensores Ativos: {odte_stats['active_s2m'] + odte_stats['active_m2s']}/116 (considera S2M+M2S)")
    print(f"Comunicação Bidirecional: {odte_stats['bidirectional']}/{odte_stats['total_sensors']}")

if __name__ == "__main__":
    main()