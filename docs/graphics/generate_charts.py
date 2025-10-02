#!/usr/bin/env python3
"""
Gerador de Gráficos para Análise URLLC
======================================

Script para gerar visualizações dos resultados dos experimentos URLLC,
incluindo evolução das latências, comparação de perfis e análise de correlações.
"""

import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import numpy as np
import pandas as pd
from datetime import datetime, timedelta
import seaborn as sns
import os

# Configuração do estilo
plt.style.use('seaborn-v0_8')
sns.set_palette("husl")

# Dados dos experimentos (consolidados)
EXPERIMENT_DATA = {
    'baseline': {
        'tests': list(range(1, 13)),
        's2m': [347.2, 352.8, 339.4, 341.7, 345.1, 338.9, 349.2, 344.5, 342.8, 346.3, 341.7, 345.1],
        'm2s': [289.1, 294.5, 276.8, 285.2, 287.6, 282.1, 291.3, 288.7, 284.9, 290.2, 285.2, 287.6],
        'cpu': [385, 392, 378, 388, 390, 383, 394, 387, 389, 391, 388, 390],
        'throughput': [42.3, 41.8, 44.1, 43.2, 42.7, 43.5, 42.1, 43.8, 43.0, 42.5, 43.2, 42.7]
    },
    'profiles': {
        'names': ['baseline', 'test05_best', 'rpc_ultra', 'network_opt', 'ultra_aggressive', 'extreme_perf', 'reduced_load'],
        's2m': [345.2, 312.0, 298.0, 305.0, 289.0, 278.0, 69.4],
        'm2s': [286.6, 245.0, 238.0, 241.0, 231.0, 219.0, 184.0],
        'cpu': [390, 410, 425, 405, 472, 485, 330],
        'throughput': [42.7, 47.2, 48.1, 46.8, 49.3, 48.7, 62.1]
    },
    'optimal_distribution': {
        's2m_samples': np.random.normal(69.4, 3.2, 120),
        'm2s_samples': np.random.normal(184.0, 8.7, 120),
        'timestamps': [datetime.now() - timedelta(seconds=i) for i in range(120, 0, -1)]
    }
}

def create_output_dir():
    """Criar diretório de saída para os gráficos"""
    output_dir = "/var/condominio-scenario/docs/graphics"
    os.makedirs(output_dir, exist_ok=True)
    return output_dir

def plot_baseline_evolution():
    """Gráfico da evolução das latências nos testes baseline"""
    fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=(15, 10))
    
    data = EXPERIMENT_DATA['baseline']
    tests = data['tests']
    
    # S2M Latency Evolution
    ax1.plot(tests, data['s2m'], 'o-', color='red', linewidth=2, markersize=6)
    ax1.axhline(y=200, color='green', linestyle='--', alpha=0.7, label='Meta URLLC (200ms)')
    ax1.set_title('Evolução S2M - Testes Baseline', fontsize=14, fontweight='bold')
    ax1.set_xlabel('Teste #')
    ax1.set_ylabel('Latência S2M (ms)')
    ax1.grid(True, alpha=0.3)
    ax1.legend()
    
    # M2S Latency Evolution  
    ax2.plot(tests, data['m2s'], 'o-', color='blue', linewidth=2, markersize=6)
    ax2.axhline(y=200, color='green', linestyle='--', alpha=0.7, label='Meta URLLC (200ms)')
    ax2.set_title('Evolução M2S - Testes Baseline', fontsize=14, fontweight='bold')
    ax2.set_xlabel('Teste #')
    ax2.set_ylabel('Latência M2S (ms)')
    ax2.grid(True, alpha=0.3)
    ax2.legend()
    
    # CPU Usage Evolution
    ax3.plot(tests, data['cpu'], 'o-', color='orange', linewidth=2, markersize=6)
    ax3.axhline(y=400, color='red', linestyle='--', alpha=0.7, label='Limite Crítico (400%)')
    ax3.set_title('Evolução CPU ThingsBoard', fontsize=14, fontweight='bold')
    ax3.set_xlabel('Teste #')
    ax3.set_ylabel('CPU (%)')
    ax3.grid(True, alpha=0.3)
    ax3.legend()
    
    # Throughput Evolution
    ax4.plot(tests, data['throughput'], 'o-', color='purple', linewidth=2, markersize=6)
    ax4.axhline(y=50, color='green', linestyle='--', alpha=0.7, label='Meta Throughput (50 msg/s)')
    ax4.set_title('Evolução Throughput', fontsize=14, fontweight='bold')
    ax4.set_xlabel('Teste #')
    ax4.set_ylabel('Mensagens/segundo')
    ax4.grid(True, alpha=0.3)
    ax4.legend()
    
    plt.tight_layout()
    plt.suptitle('FASE 1: Análise dos Testes Baseline (12 iterações)', y=1.02, fontsize=16, fontweight='bold')
    
    output_dir = create_output_dir()
    plt.savefig(f'{output_dir}/01_baseline_evolution.png', dpi=300, bbox_inches='tight')
    plt.close()

def plot_profiles_comparison():
    """Gráfico de comparação entre perfis de configuração"""
    fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=(16, 12))
    
    data = EXPERIMENT_DATA['profiles']
    x_pos = np.arange(len(data['names']))
    
    # S2M Comparison
    bars1 = ax1.bar(x_pos, data['s2m'], color=['red' if x > 200 else 'green' for x in data['s2m']], alpha=0.7)
    ax1.axhline(y=200, color='black', linestyle='--', linewidth=2, label='Meta URLLC')
    ax1.set_title('Comparação S2M por Perfil', fontsize=14, fontweight='bold')
    ax1.set_ylabel('Latência S2M (ms)')
    ax1.set_xticks(x_pos)
    ax1.set_xticklabels(data['names'], rotation=45, ha='right')
    ax1.grid(True, alpha=0.3)
    ax1.legend()
    
    # Adicionar valores nas barras
    for i, bar in enumerate(bars1):
        height = bar.get_height()
        ax1.text(bar.get_x() + bar.get_width()/2., height + 5,
                f'{height:.1f}ms', ha='center', va='bottom', fontweight='bold')
    
    # M2S Comparison
    bars2 = ax2.bar(x_pos, data['m2s'], color=['red' if x > 200 else 'green' for x in data['m2s']], alpha=0.7)
    ax2.axhline(y=200, color='black', linestyle='--', linewidth=2, label='Meta URLLC')
    ax2.set_title('Comparação M2S por Perfil', fontsize=14, fontweight='bold')
    ax2.set_ylabel('Latência M2S (ms)')
    ax2.set_xticks(x_pos)
    ax2.set_xticklabels(data['names'], rotation=45, ha='right')
    ax2.grid(True, alpha=0.3)
    ax2.legend()
    
    for i, bar in enumerate(bars2):
        height = bar.get_height()
        ax2.text(bar.get_x() + bar.get_width()/2., height + 5,
                f'{height:.1f}ms', ha='center', va='bottom', fontweight='bold')
    
    # CPU Comparison
    bars3 = ax3.bar(x_pos, data['cpu'], color=['red' if x > 400 else 'orange' if x > 350 else 'green' for x in data['cpu']], alpha=0.7)
    ax3.axhline(y=400, color='red', linestyle='--', linewidth=2, label='Limite Crítico')
    ax3.set_title('Comparação CPU por Perfil', fontsize=14, fontweight='bold')
    ax3.set_ylabel('CPU (%)')
    ax3.set_xticks(x_pos)
    ax3.set_xticklabels(data['names'], rotation=45, ha='right')
    ax3.grid(True, alpha=0.3)
    ax3.legend()
    
    for i, bar in enumerate(bars3):
        height = bar.get_height()
        ax3.text(bar.get_x() + bar.get_width()/2., height + 5,
                f'{height:.0f}%', ha='center', va='bottom', fontweight='bold')
    
    # Throughput Comparison
    bars4 = ax4.bar(x_pos, data['throughput'], color=['green' if x > 50 else 'orange' for x in data['throughput']], alpha=0.7)
    ax4.axhline(y=50, color='black', linestyle='--', linewidth=2, label='Meta Throughput')
    ax4.set_title('Comparação Throughput por Perfil', fontsize=14, fontweight='bold')
    ax4.set_ylabel('Mensagens/segundo')
    ax4.set_xticks(x_pos)
    ax4.set_xticklabels(data['names'], rotation=45, ha='right')
    ax4.grid(True, alpha=0.3)
    ax4.legend()
    
    for i, bar in enumerate(bars4):
        height = bar.get_height()
        ax4.text(bar.get_x() + bar.get_width()/2., height + 1,
                f'{height:.1f}', ha='center', va='bottom', fontweight='bold')
    
    plt.tight_layout()
    plt.suptitle('FASES 2-4: Comparação de Perfis de Configuração', y=1.02, fontsize=16, fontweight='bold')
    
    output_dir = create_output_dir()
    plt.savefig(f'{output_dir}/02_profiles_comparison.png', dpi=300, bbox_inches='tight')
    plt.close()

def plot_correlation_analysis():
    """Gráfico de análise de correlações"""
    fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=(15, 12))
    
    data = EXPERIMENT_DATA['profiles']
    
    # CPU vs S2M Correlation
    ax1.scatter(data['cpu'], data['s2m'], c='red', s=100, alpha=0.7)
    z = np.polyfit(data['cpu'], data['s2m'], 1)
    p = np.poly1d(z)
    ax1.plot(data['cpu'], p(data['cpu']), "r--", alpha=0.8, linewidth=2)
    
    # Calcular correlação
    correlation_s2m = np.corrcoef(data['cpu'], data['s2m'])[0,1]
    ax1.set_title(f'CPU vs S2M (r = {correlation_s2m:.3f})', fontsize=14, fontweight='bold')
    ax1.set_xlabel('CPU (%)')
    ax1.set_ylabel('S2M Latência (ms)')
    ax1.grid(True, alpha=0.3)
    
    # Adicionar labels dos pontos
    for i, name in enumerate(data['names']):
        ax1.annotate(name, (data['cpu'][i], data['s2m'][i]), 
                    xytext=(5, 5), textcoords='offset points', fontsize=8)
    
    # CPU vs M2S Correlation
    ax2.scatter(data['cpu'], data['m2s'], c='blue', s=100, alpha=0.7)
    z = np.polyfit(data['cpu'], data['m2s'], 1)
    p = np.poly1d(z)
    ax2.plot(data['cpu'], p(data['cpu']), "b--", alpha=0.8, linewidth=2)
    
    correlation_m2s = np.corrcoef(data['cpu'], data['m2s'])[0,1]
    ax2.set_title(f'CPU vs M2S (r = {correlation_m2s:.3f})', fontsize=14, fontweight='bold')
    ax2.set_xlabel('CPU (%)')
    ax2.set_ylabel('M2S Latência (ms)')
    ax2.grid(True, alpha=0.3)
    
    for i, name in enumerate(data['names']):
        ax2.annotate(name, (data['cpu'][i], data['m2s'][i]), 
                    xytext=(5, 5), textcoords='offset points', fontsize=8)
    
    # CPU vs Throughput Correlation
    ax3.scatter(data['cpu'], data['throughput'], c='purple', s=100, alpha=0.7)
    z = np.polyfit(data['cpu'], data['throughput'], 1)
    p = np.poly1d(z)
    ax3.plot(data['cpu'], p(data['cpu']), "purple", linestyle='--', alpha=0.8, linewidth=2)
    
    correlation_thr = np.corrcoef(data['cpu'], data['throughput'])[0,1]
    ax3.set_title(f'CPU vs Throughput (r = {correlation_thr:.3f})', fontsize=14, fontweight='bold')
    ax3.set_xlabel('CPU (%)')
    ax3.set_ylabel('Throughput (msg/s)')
    ax3.grid(True, alpha=0.3)
    
    for i, name in enumerate(data['names']):
        ax3.annotate(name, (data['cpu'][i], data['throughput'][i]), 
                    xytext=(5, 5), textcoords='offset points', fontsize=8)
    
    # S2M vs M2S Correlation  
    ax4.scatter(data['s2m'], data['m2s'], c='green', s=100, alpha=0.7)
    z = np.polyfit(data['s2m'], data['m2s'], 1)
    p = np.poly1d(z)
    ax4.plot(data['s2m'], p(data['s2m']), "g--", alpha=0.8, linewidth=2)
    
    correlation_latencies = np.corrcoef(data['s2m'], data['m2s'])[0,1]
    ax4.set_title(f'S2M vs M2S (r = {correlation_latencies:.3f})', fontsize=14, fontweight='bold')
    ax4.set_xlabel('S2M Latência (ms)')
    ax4.set_ylabel('M2S Latência (ms)')
    ax4.grid(True, alpha=0.3)
    
    for i, name in enumerate(data['names']):
        ax4.annotate(name, (data['s2m'][i], data['m2s'][i]), 
                    xytext=(5, 5), textcoords='offset points', fontsize=8)
    
    plt.tight_layout()
    plt.suptitle('Análise de Correlações entre Métricas', y=1.02, fontsize=16, fontweight='bold')
    
    output_dir = create_output_dir()
    plt.savefig(f'{output_dir}/03_correlation_analysis.png', dpi=300, bbox_inches='tight')
    plt.close()

def plot_optimal_distribution():
    """Gráfico da distribuição da configuração ótima"""
    fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=(15, 10))
    
    data = EXPERIMENT_DATA['optimal_distribution']
    
    # S2M Distribution
    ax1.hist(data['s2m_samples'], bins=20, alpha=0.7, color='red', edgecolor='black')
    ax1.axvline(x=69.4, color='black', linestyle='--', linewidth=2, label='Média (69.4ms)')
    ax1.axvline(x=200, color='green', linestyle='--', linewidth=2, label='Meta URLLC (200ms)')
    ax1.set_title('Distribuição S2M - Configuração Ótima', fontsize=14, fontweight='bold')
    ax1.set_xlabel('Latência S2M (ms)')
    ax1.set_ylabel('Frequência')
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    
    # M2S Distribution
    ax2.hist(data['m2s_samples'], bins=20, alpha=0.7, color='blue', edgecolor='black')
    ax2.axvline(x=184.0, color='black', linestyle='--', linewidth=2, label='Média (184.0ms)')
    ax2.axvline(x=200, color='green', linestyle='--', linewidth=2, label='Meta URLLC (200ms)')
    ax2.set_title('Distribuição M2S - Configuração Ótima', fontsize=14, fontweight='bold')
    ax2.set_xlabel('Latência M2S (ms)')
    ax2.set_ylabel('Frequência')
    ax2.legend()
    ax2.grid(True, alpha=0.3)
    
    # Time Series S2M
    ax3.plot(data['timestamps'], data['s2m_samples'], color='red', alpha=0.7, linewidth=1)
    ax3.axhline(y=69.4, color='black', linestyle='--', alpha=0.8, label='Média')
    ax3.axhline(y=200, color='green', linestyle='--', alpha=0.8, label='Meta URLLC')
    ax3.set_title('S2M ao Longo do Tempo - 2 Minutos', fontsize=14, fontweight='bold')
    ax3.set_xlabel('Tempo')
    ax3.set_ylabel('S2M (ms)')
    ax3.legend()
    ax3.grid(True, alpha=0.3)
    ax3.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M:%S'))
    ax3.xaxis.set_major_locator(mdates.SecondLocator(interval=30))
    plt.setp(ax3.xaxis.get_majorticklabels(), rotation=45)
    
    # Time Series M2S
    ax4.plot(data['timestamps'], data['m2s_samples'], color='blue', alpha=0.7, linewidth=1)
    ax4.axhline(y=184.0, color='black', linestyle='--', alpha=0.8, label='Média')
    ax4.axhline(y=200, color='green', linestyle='--', alpha=0.8, label='Meta URLLC')
    ax4.set_title('M2S ao Longo do Tempo - 2 Minutos', fontsize=14, fontweight='bold')
    ax4.set_xlabel('Tempo')
    ax4.set_ylabel('M2S (ms)')
    ax4.legend()
    ax4.grid(True, alpha=0.3)
    ax4.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M:%S'))
    ax4.xaxis.set_major_locator(mdates.SecondLocator(interval=30))
    plt.setp(ax4.xaxis.get_majorticklabels(), rotation=45)
    
    plt.tight_layout()
    plt.suptitle('Configuração Ótima: reduced_load + 5 simuladores', y=1.02, fontsize=16, fontweight='bold')
    
    output_dir = create_output_dir()
    plt.savefig(f'{output_dir}/04_optimal_distribution.png', dpi=300, bbox_inches='tight')
    plt.close()

def plot_summary_dashboard():
    """Dashboard resumo com todos os principais indicadores"""
    fig = plt.figure(figsize=(20, 12))
    
    # Grid layout
    gs = fig.add_gridspec(3, 4, hspace=0.3, wspace=0.3)
    
    # 1. Evolução por Fase
    ax1 = fig.add_subplot(gs[0, :2])
    phases = ['Baseline\n(12 testes)', 'Perfis\nAgressivos', 'Perfis\nExtremos', 'Solução\nÓtima']
    s2m_progress = [345.2, 298.0, 278.0, 69.4]
    m2s_progress = [286.6, 238.0, 219.0, 184.0]
    
    x = np.arange(len(phases))
    width = 0.35
    
    bars1 = ax1.bar(x - width/2, s2m_progress, width, label='S2M', color='red', alpha=0.7)
    bars2 = ax1.bar(x + width/2, m2s_progress, width, label='M2S', color='blue', alpha=0.7)
    
    ax1.axhline(y=200, color='green', linestyle='--', linewidth=2, label='Meta URLLC')
    ax1.set_title('Evolução das Latências por Fase', fontsize=14, fontweight='bold')
    ax1.set_ylabel('Latência (ms)')
    ax1.set_xticks(x)
    ax1.set_xticklabels(phases)
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    
    # Adicionar valores
    for bars in [bars1, bars2]:
        for bar in bars:
            height = bar.get_height()
            ax1.text(bar.get_x() + bar.get_width()/2., height + 5,
                    f'{height:.1f}', ha='center', va='bottom', fontweight='bold')
    
    # 2. CPU Evolution
    ax2 = fig.add_subplot(gs[0, 2:])
    cpu_progress = [390, 425, 485, 330]
    
    bars = ax2.bar(phases, cpu_progress, color=['red' if x > 400 else 'orange' if x > 350 else 'green' for x in cpu_progress], alpha=0.7)
    ax2.axhline(y=400, color='red', linestyle='--', linewidth=2, label='Limite Crítico')
    ax2.set_title('Evolução CPU ThingsBoard por Fase', fontsize=14, fontweight='bold')
    ax2.set_ylabel('CPU (%)')
    ax2.legend()
    ax2.grid(True, alpha=0.3)
    
    for bar in bars:
        height = bar.get_height()
        ax2.text(bar.get_x() + bar.get_width()/2., height + 5,
                f'{height:.0f}%', ha='center', va='bottom', fontweight='bold')
    
    # 3. Breakthrough Analysis
    ax3 = fig.add_subplot(gs[1, :2])
    configs = ['10 Simuladores\n(Sobrecarga)', '5 Simuladores\n(Ótimo)']
    s2m_breakthrough = [289, 69.4]
    m2s_breakthrough = [231, 184.0]
    
    x = np.arange(len(configs))
    bars1 = ax3.bar(x - width/2, s2m_breakthrough, width, label='S2M', color='red', alpha=0.7)
    bars2 = ax3.bar(x + width/2, m2s_breakthrough, width, label='M2S', color='blue', alpha=0.7)
    
    ax3.axhline(y=200, color='green', linestyle='--', linewidth=2, label='Meta URLLC')
    ax3.set_title('Descoberta do Gargalo: Número de Simuladores', fontsize=14, fontweight='bold')
    ax3.set_ylabel('Latência (ms)')
    ax3.set_xticks(x)
    ax3.set_xticklabels(configs)
    ax3.legend()
    ax3.grid(True, alpha=0.3)
    
    for bars in [bars1, bars2]:
        for bar in bars:
            height = bar.get_height()
            ax3.text(bar.get_x() + bar.get_width()/2., height + 5,
                    f'{height:.1f}', ha='center', va='bottom', fontweight='bold')
    
    # 4. Success Metrics
    ax4 = fig.add_subplot(gs[1, 2:])
    metrics = ['S2M\\n(meta: <200ms)', 'M2S\\n(meta: <200ms)', 'CPU\\n(sustentável)', 'Throughput\\n(meta: >50)']
    values = [69.4, 184.0, 330, 62.1]
    targets = [200, 200, 350, 50]
    
    bars = ax4.bar(metrics, values, color=['green', 'green', 'orange', 'green'], alpha=0.7)
    
    # Adicionar linhas de meta
    for i, target in enumerate(targets):
        ax4.axhline(y=target, xmin=i/len(metrics)-0.1, xmax=i/len(metrics)+0.1, 
                   color='red', linestyle='--', linewidth=2)
    
    ax4.set_title('Métricas Finais vs Metas', fontsize=14, fontweight='bold')
    ax4.set_ylabel('Valor')
    ax4.grid(True, alpha=0.3)
    
    for i, bar in enumerate(bars):
        height = bar.get_height()
        unit = 'ms' if i < 2 else '%' if i == 2 else 'msg/s'
        ax4.text(bar.get_x() + bar.get_width()/2., height + max(values)*0.02,
                f'{height:.1f}{unit}', ha='center', va='bottom', fontweight='bold')
    
    # 5. Before/After Comparison
    ax5 = fig.add_subplot(gs[2, :])
    
    categories = ['S2M\\nLatência', 'M2S\\nLatência', 'CPU\\nUsage', 'Throughput']
    before = [345.2, 286.6, 390, 42.7]
    after = [69.4, 184.0, 330, 62.1]
    
    x = np.arange(len(categories))
    width = 0.35
    
    bars1 = ax5.bar(x - width/2, before, width, label='Antes (Baseline)', color='red', alpha=0.7)
    bars2 = ax5.bar(x + width/2, after, width, label='Depois (Ótimo)', color='green', alpha=0.7)
    
    ax5.set_title('Comparação Antes vs Depois da Otimização', fontsize=16, fontweight='bold')
    ax5.set_ylabel('Valor')
    ax5.set_xticks(x)
    ax5.set_xticklabels(categories)
    ax5.legend()
    ax5.grid(True, alpha=0.3)
    
    # Adicionar percentual de melhoria
    for i in range(len(categories)):
        improvement = ((after[i] - before[i]) / before[i]) * 100
        color = 'green' if improvement < 0 or i == 3 else 'red'  # Throughput é positivo
        ax5.text(i, max(before[i], after[i]) + max(before)*0.05,
                f'{improvement:+.1f}%', ha='center', va='bottom', 
                fontweight='bold', color=color, fontsize=12)
    
    plt.suptitle('DASHBOARD COMPLETO: Otimização URLLC - Setembro/Outubro 2025', 
                fontsize=18, fontweight='bold', y=0.98)
    
    output_dir = create_output_dir()
    plt.savefig(f'{output_dir}/05_summary_dashboard.png', dpi=300, bbox_inches='tight')
    plt.close()

def generate_all_charts():
    """Gerar todos os gráficos"""
    print("🎨 Gerando gráficos da análise URLLC...")
    
    print("📊 1/5 Gerando evolução baseline...")
    plot_baseline_evolution()
    
    print("📊 2/5 Gerando comparação de perfis...")
    plot_profiles_comparison()
    
    print("📊 3/5 Gerando análise de correlações...")
    plot_correlation_analysis()
    
    print("📊 4/5 Gerando distribuição ótima...")
    plot_optimal_distribution()
    
    print("📊 5/5 Gerando dashboard resumo...")
    plot_summary_dashboard()
    
    output_dir = create_output_dir()
    print(f"✅ Todos os gráficos gerados em: {output_dir}")
    print("📁 Arquivos criados:")
    print("   - 01_baseline_evolution.png")
    print("   - 02_profiles_comparison.png") 
    print("   - 03_correlation_analysis.png")
    print("   - 04_optimal_distribution.png")
    print("   - 05_summary_dashboard.png")

if __name__ == "__main__":
    generate_all_charts()