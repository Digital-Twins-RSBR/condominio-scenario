# Scripts do Condomínio Scenario

Este diretório contém todos os scripts para execução da suíte de testes, análise e configuração do ambiente URLLC/eMBB/Best-Effort.

## Scripts Principais

### Suíte de Testes

```bash
# Suíte completa (7 cenários, ~70 minutos para --duration 600)
./scripts/run_scenario_suite.sh --duration 600 --m2s-perf

# Opções disponíveis
./scripts/run_scenario_suite.sh --help
```

**Flags:**
| Flag | Descrição |
|------|-----------|
| `--duration N` | Duração de cada teste em segundos (padrão: 180) |
| `--test N` | Rodar apenas teste N (1–7) |
| `--tests N,M` | Rodar testes específicos |
| `--skip N,M` | Pular testes |
| `--full` | Testes 1–6 (sem Cenário 7) |
| `--m2s-perf` | Todos os 7 cenários incluindo M2S Perf |
| `--raw` | Usar configs ThingsBoard RAW |

**Cenários:**
| # | Nome | Timeout M2S |
|---|------|-------------|
| 1 | URLLC Otimizado | 150 ms |
| 2 | eMBB Otimizado | 300 ms |
| 3 | Best-Effort Otimizado | 500 ms |
| 4 | URLLC RAW | 30 000 ms (diagnóstico) |
| 5 | eMBB RAW | 5 000 ms (diagnóstico) |
| 6 | Best-Effort RAW | 10 000 ms (diagnóstico) |
| 7 | URLLC M2S Perf | 220 ms + fast mode |

### Análise de Resultados

```bash
# Analisar latências de uma execução
python3 scripts/fix_summary_s2m_metrics.py <summary.txt> <correlation.txt>

# Comparar execuções URLLC
python3 scripts/compare_urllc_tests.py

# Gerar plots
./scripts/generate_all_plots.sh
```

### Topologia e Infraestrutura

```bash
make topo               # Inicia topologia (chama topo_qos.py)
make net-clean          # Para e limpa containers
./scripts/apply_slice.sh --profile urllc --duration 300
```

## Estrutura de Diretórios

```
scripts/
├── run_scenario_suite.sh       # Orquestrador principal da suíte
├── apply_slice.sh              # Aplica perfil de rede e inicia serviços
├── fix_summary_s2m_metrics.py  # Extrai métricas M2S de relatórios
├── slice/                      # Variantes do apply_slice
├── plots/                      # Scripts de geração de gráficos
├── report_generators/          # Geradores de relatório (Python)
├── monitor/                    # Scripts de monitoramento
└── filters/                    # Filtros de digital twins
```

## Outputs

Cada execução da suíte gera:
- `outputs/tests_<TIMESTAMP>/test_N.csv` – dados consolidados
- `outputs/tests_<TIMESTAMP>/test_N_summary.txt` – métricas
- `outputs/tests_<TIMESTAMP>/test_N_correlation.txt` – análise M2S
- `outputs/tests_<TIMESTAMP>/comparison_table.md` – tabela comparativa

## Configurações ThingsBoard

Cada cenário monta um arquivo YAML diferente:

| Arquivo | Cenário |
|---------|---------|
| `config/thingsboard-urllc.yml` | Tests 1, 7 (base) |
| `config/thingsboard-urllc-m2s-perf.yml` | Test 7 (M2S Perf) |
| `config/thingsboard-urllc-raw.yml` | Test 4 |
| `config/thingsboard-embb.yml` | Test 2 |
| `config/thingsboard-embb-raw.yml` | Test 5 |
| `config/thingsboard-best-effort.yml` | Test 3 |
| `config/thingsboard-best-effort-raw.yml` | Test 6 |
