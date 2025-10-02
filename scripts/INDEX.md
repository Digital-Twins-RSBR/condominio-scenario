# Índice de Scripts - Condomínio Scenario URLLC

## 🎯 Scripts Principais (Uso Diário)

| Script | Makefile Target | Descrição | Status |
|--------|----------------|-----------|---------|
| `apply_urllc_minimal.sh` | `make apply-urllc` | Aplica otimizações URLLC (automático na topologia) | ✅ Principal |
| `check_urllc_status.sh` | `make check-urllc` | Verifica status das otimizações | ✅ Principal |
| `OPTIMIZATION_SUMMARY.sh` | `make summary` | Resumo executivo das otimizações | ✅ Principal |
| `check_topology.sh` | `make check-topology` | Status geral da topologia | ✅ Principal |
| `check_tc.sh` | `make check-tc` | Verificar Traffic Control | ✅ Principal |
| `organize_reports.sh` | `make organize-reports` | Organizar relatórios por timestamp | ✅ Principal |

## 🧪 Scripts de Teste/Experimentação

| Script | Uso | Descrição | Status |
|--------|-----|-----------|---------|
| `optimize_for_low_latency.sh` | Manual | HEARTBEAT_INTERVAL=2s (agressivo) | 📝 Teste |
| `optimize_balanced_latency.sh` | Manual | HEARTBEAT_INTERVAL=3s (balanceado) | 📝 Teste |
| `optimize_s2m_specific.sh` | Manual | HEARTBEAT_INTERVAL=4s (S2M focus) | 📝 Teste |
| `optimize_thingsboard_resources.sh` | Manual | Otimizações específicas TB | 📝 Teste |

## 🗂️ Scripts de Sistema/Legado

| Script | Status | Observação |
|--------|--------|------------|
| `apply_urllc_config.sh` | 🔄 Legado | Versão completa com restart TB (usar só manualmente) |
| `apply_slice.sh` | 🔄 Legado | Script complexo original (preferir Makefile) |
| `run_topo.sh` | ❌ Obsoleto | Use `make topo` ao invés |
| `setup.sh` | ✅ Sistema | Configuração inicial |
| `influx_provision.sh` | ✅ Sistema | Provisionamento InfluxDB |

## 🚀 Fluxo de Trabalho Recomendado

```bash
# 1. Iniciar topologia (com otimizações automáticas)
make topo

# 2. Verificar otimizações
make check-urllc

# 3. Executar análise completa
make odte-full

# 4. Ver resumo dos resultados
make summary
```

## 📋 Comandos Quick Reference

```bash
# Verificações rápidas
make check-urllc         # Status das otimizações
make check-topology      # Status da topologia
make check-tc           # Traffic Control

# Análises
make odte-full          # Análise completa (experimento + relatórios)
make summary            # Resumo executivo
make organize-reports   # Organizar resultados

# Manutenção
make clean              # Limpeza completa
make apply-urllc        # Aplicar otimizações manualmente
```

## 📁 Estrutura de Diretórios

```
scripts/
├── README.md                          # Documentação principal
├── INDEX.md                           # Este arquivo
├── cleanup_scripts.sh                 # Organização e limpeza
│
├── 🎯 Principais/
│   ├── apply_urllc_minimal.sh        # Otimizações automáticas
│   ├── check_urllc_status.sh         # Verificação de status
│   ├── OPTIMIZATION_SUMMARY.sh       # Resumo executivo
│   ├── check_topology.sh             # Status da topologia
│   ├── check_tc.sh                   # Traffic Control
│   └── organize_reports.sh           # Organizar relatórios
│
├── 🧪 Testes/
│   ├── optimize_for_low_latency.sh   # Teste agressivo
│   ├── optimize_balanced_latency.sh  # Teste balanceado
│   ├── optimize_s2m_specific.sh      # Teste S2M específico
│   └── optimize_thingsboard_resources.sh
│
└── 🗂️ Sistema/
    ├── setup.sh                      # Setup inicial
    ├── influx_provision.sh           # InfluxDB
    ├── apply_urllc_config.sh         # Legado
    └── apply_slice.sh                # Legado
```