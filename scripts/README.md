# Scripts do Condomínio Scenario

Este diretório contém todos os scripts utilizados para configuração, otimização e análise do ambiente URLLC.

## 📁 Estrutura Organizada

### 🔧 **Configuração e Setup**
- `setup.sh` - Configuração inicial completa do ambiente
- `setup_local.sh` - Configuração para ambiente local/desenvolvimento
- `influx_provision.sh` - Provisionamento do InfluxDB com buckets e tokens

### 🚀 **Otimizações URLLC**
- `apply_urllc_minimal.sh` - **[PRINCIPAL]** Aplica otimizações de rede e sistema (usado automaticamente pela topologia)
- `apply_urllc_config.sh` - **[LEGADO]** Versão completa com restart do ThingsBoard (usar apenas manualmente)
- `optimize_balanced_latency.sh` - **[TESTE]** Otimização balanceada S2M/M2S (HEARTBEAT_INTERVAL=3s)
- `optimize_for_low_latency.sh` - **[TESTE]** Otimização agressiva para baixa latência (HEARTBEAT_INTERVAL=2s)
- `optimize_s2m_specific.sh` - **[TESTE]** Otimização específica para S2M (HEARTBEAT_INTERVAL=4s)
- `optimize_thingsboard_resources.sh` - **[TESTE]** Otimização de recursos do ThingsBoard

### ✅ **Verificação e Status**
- `check_urllc_status.sh` - **[PRINCIPAL]** Verifica status das otimizações aplicadas
- `check_tc.sh` - Verifica configurações de Traffic Control nos containers
- `check_topology.sh` - Verifica status geral da topologia

### 📊 **Análise e Relatórios**
- `OPTIMIZATION_SUMMARY.sh` - **[PRINCIPAL]** Resumo executivo das otimizações e resultados
- `organize_reports.sh` - Organiza relatórios de teste por timestamp
- `report_generators/` - Scripts Python para geração de gráficos e análises

### 🔄 **Manutenção**
- `apply_slice.sh` - **[LEGADO]** Script original complexo para aplicação de slices
- `reset_machine.sh` - Reset completo da máquina
- `reset_digital_twins.py` - Reset dos digital twins no sistema
- `restore_middts.sh` - Restaura middleware-dt

### 🏃 **Execução**
- `run_topo.sh` - Execução da topologia (usar `make topo` ao invés)

## 🎯 **Scripts Principais Recomendados**

### Para Uso Diário:
```bash
make topo                    # Inicia topologia com otimizações automáticas
make check-urllc            # Verifica status das otimizações  
make odte-full              # Análise completa de latência
make summary                # Resumo das otimizações
```

### Para Desenvolvimento/Debug:
```bash
make check-topology         # Status detalhado da topologia
make check-tc               # Verificar Traffic Control
make organize-reports       # Organizar resultados
```

## 📋 **Mapeamento no Makefile**

Todos os scripts principais estão mapeados como targets no Makefile principal para facilitar o uso.

## 🔍 **Versionamento**

- **[PRINCIPAL]** - Scripts de uso diário recomendados
- **[LEGADO]** - Scripts mantidos para compatibilidade, preferir alternativas
- **[TESTE]** - Scripts de experimentação, úteis para debug específico

## 🚨 **Importante**

As otimizações URLLC agora são aplicadas **automaticamente** durante `make topo`. 
O script `apply_urllc_minimal.sh` é executado automaticamente pela topologia.
Use `check_urllc_status.sh` para verificar se tudo está funcionando corretamente.