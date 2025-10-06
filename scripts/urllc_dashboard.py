#!/usr/bin/env python3
"""
Dashboard de Status URLLC - Resumo Executivo Rápido
Mostra o status atual do sistema em formato executivo
"""

import pandas as pd
import sys
import os
from pathlib import Path
from datetime import datetime

def get_latest_test_summary():
    """Gera resumo executivo do teste mais recente"""
    
    # Encontrar teste mais recente
    results_dir = Path("results")
    urllc_tests = list(results_dir.glob("test_*_urllc"))
    
    if not urllc_tests:
        return "❌ Nenhum teste URLLC encontrado"
    
    latest_test = sorted(urllc_tests, key=lambda x: x.name)[-1]
    reports_dir = latest_test / "generated_reports"
    
    # Carregar dados ODTE
    odte_files = list(reports_dir.glob("*odte*.csv"))
    if not odte_files:
        return f"❌ Dados ODTE não encontrados em {latest_test.name}"
    
    df = pd.read_csv(odte_files[0])
    
    # Calcular métricas principais
    total_sensors = len(df)
    sensors_s2m = (df['sim_sent_count'] > 0).sum()
    sensors_m2s = (df['middts_sent_count'] > 0).sum()
    sensors_bidirectional = ((df['sim_sent_count'] > 0) & (df['middts_sent_count'] > 0)).sum()
    odte_general = df['A'].mean()
    odte_bidirectional = df[(df['sim_sent_count'] > 0) & (df['middts_sent_count'] > 0)]['A'].mean() if sensors_bidirectional > 0 else 0
    
    # Carregar dados de latência
    s2m_files = list(reports_dir.glob("*simulator_to_middts*.csv"))
    m2s_files = list(reports_dir.glob("*middts_to_simulator*.csv"))
    
    s2m_latency = 0
    m2s_latency = 0
    s2m_p95 = 0
    m2s_p95 = 0
    urllc_s2m = 0
    urllc_m2s = 0
    
    if s2m_files:
        s2m_df = pd.read_csv(s2m_files[0])
        s2m_active = s2m_df[s2m_df['count'] > 0]
        if len(s2m_active) > 0:
            s2m_latency = s2m_active['mean_ms'].mean()
            s2m_p95 = s2m_active['p95_ms'].mean()
            urllc_s2m = (s2m_active['p95_ms'] < 200).sum() / len(s2m_active) * 100
    
    if m2s_files:
        m2s_df = pd.read_csv(m2s_files[0])
        m2s_active = m2s_df[m2s_df['count'] > 0]
        if len(m2s_active) > 0:
            m2s_latency = m2s_active['mean_ms'].mean()
            m2s_p95 = m2s_active['p95_ms'].mean()
            urllc_m2s = (m2s_active['p95_ms'] < 200).sum() / len(m2s_active) * 100
    
    # Extrair timestamp
    try:
        timestamp_str = latest_test.name.split('_')[1]  # 20251006T004352Z
        test_date = datetime.strptime(timestamp_str, '%Y%m%dT%H%M%SZ')
        date_formatted = test_date.strftime('%d/%m/%Y %H:%M')
    except:
        date_formatted = "Data desconhecida"
    
    # Gerar relatório
    report = f"""
🎯 DASHBOARD URLLC - STATUS EXECUTIVO
══════════════════════════════════════════════════════════════════

📅 ÚLTIMO TESTE: {latest_test.name}
🕐 DATA/HORA: {date_formatted}

🚀 PERFORMANCE URLLC
──────────────────────────────────────────────────────────────────
📈 S2M (Sensor→Middleware): {s2m_latency:.1f}ms média | {s2m_p95:.1f}ms P95
📉 M2S (Middleware→Sensor): {m2s_latency:.1f}ms média | {m2s_p95:.1f}ms P95

🎯 URLLC COMPLIANCE (<200ms P95)
──────────────────────────────────────────────────────────────────
✅ S2M: {urllc_s2m:.0f}% compliance
✅ M2S: {urllc_m2s:.0f}% compliance
🏆 MÉDIO: {(urllc_s2m + urllc_m2s)/2:.0f}% compliance

📊 EFICIÊNCIA ODTE
──────────────────────────────────────────────────────────────────
📊 ODTE Geral: {odte_general:.1%} (operacional)
🔗 ODTE Bidirectional: {odte_bidirectional:.1%} (otimizado)

🔌 CONECTIVIDADE DOS SENSORES
──────────────────────────────────────────────────────────────────
📡 Total configurado: {total_sensors} sensores
📤 S2M ativos: {sensors_s2m} ({sensors_s2m/total_sensors*100:.1f}%)
📥 M2S ativos: {sensors_m2s} ({sensors_m2s/total_sensors*100:.1f}%)
🔄 Bidirecionais: {sensors_bidirectional} ({sensors_bidirectional/total_sensors*100:.1f}%)

🏆 STATUS GERAL
──────────────────────────────────────────────────────────────────"""

    # Determinar status geral
    urllc_avg = (urllc_s2m + urllc_m2s) / 2
    if urllc_avg >= 90 and odte_general >= 0.6:
        status = "✅ EXCELENTE - Sistema URLLC operacional"
    elif urllc_avg >= 80 and odte_general >= 0.5:
        status = "⚡ BOM - Performance adequada"
    elif urllc_avg >= 60:
        status = "⚠️ ACEITÁVEL - Necessita otimização"
    else:
        status = "❌ CRÍTICO - Requer intervenção"
    
    report += f"\n🎖️ {status}"
    
    # Recomendações
    report += f"\n\n💡 RECOMENDAÇÕES IMEDIATAS\n──────────────────────────────────────────────────────────────────"
    
    if urllc_m2s < 90:
        report += f"\n🔧 M2S: Otimizar para atingir >90% compliance (atual: {urllc_m2s:.0f}%)"
    
    if odte_general < 0.8:
        report += f"\n📈 ODTE: Aumentar eficiência para >80% (atual: {odte_general:.1%})"
    
    if sensors_bidirectional < total_sensors * 0.6:
        report += f"\n🔗 Conectividade: Aumentar sensores bidirecionais para >60% (atual: {sensors_bidirectional/total_sensors*100:.1f}%)"
    
    if urllc_avg >= 90 and odte_general >= 0.65:
        report += f"\n🚀 Sistema ready para scaling test (10 simuladores)"
        report += f"\n📋 Sistema ready para benchmark eMBB vs URLLC"
    
    report += f"\n\n══════════════════════════════════════════════════════════════════"
    report += f"\n📊 Para análise detalhada: make analyze-latest"
    report += f"\n📈 Para comparação evolutiva: make compare-urllc"
    
    return report

def main():
    print("🔍 Gerando dashboard de status URLLC...")
    
    try:
        summary = get_latest_test_summary()
        print(summary)
        
        # Salvar em arquivo também
        with open("STATUS_URLLC_DASHBOARD.txt", "w", encoding="utf-8") as f:
            f.write(summary)
        
        print(f"\n💾 Dashboard salvo em: STATUS_URLLC_DASHBOARD.txt")
        
    except Exception as e:
        print(f"❌ Erro ao gerar dashboard: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()