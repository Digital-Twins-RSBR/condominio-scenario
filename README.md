# Cenario Condominio - URLLC com ODTE Bidirectional

Testbed de avaliacao de desempenho URLLC/eMBB/Best-Effort para aplicacoes IoT em condominios inteligentes, com medicao de latencia ODTE (One-Way Delay Time) bidirecional (Sensor->Middleware e Middleware->Sensor).

## Marco Atual - Suite Completa (2026-03-10)

Execucao de referencia: 7 cenarios, `--duration 600`.
Dados: `outputs/tests_20260310_114533/`.

| Cenario | S2M eventos | M2S Sent | M2S Recv | Delivery | Media M2S | P95 M2S |
|---------|------------:|---------:|---------:|---------:|----------:|--------:|
| Test 1 URLLC Otimizado (150ms)     | 29 424 | 1 033 |   756 | 73.18% | 324.7 ms | 366 ms |
| Test 2 eMBB Otimizado (300ms)      |  2 984 |    96 |     0 |  0.00% | 5436.7 ms | 7289 ms |
| Test 3 Best-Effort Otimizado       |  1 575 |    62 |     0 |  0.00% | 9200.1 ms | 11876 ms |
| Test 4 URLLC RAW (30 000ms)        | 29 542 | 1 019 |   745 | 73.11% | 329.2 ms | 374 ms |
| Test 5 eMBB RAW (5 000ms)          |  3 312 |    98 |     0 |  0.00% | 4713.5 ms | 6003 ms |
| Test 6 Best-Effort RAW             |  1 558 |    62 |     0 |  0.00% | 8710.6 ms | 10164 ms |
| Test 7 URLLC M2S Perf (220ms)      | 30 473 | 1 504 | 1 100 | 73.14% | 282.6 ms | 322 ms |

**Test 7 vs Test 1:** -42 ms na media (-13%), -44 ms no P95 (-12%), CV 8.01% vs 8.91%.

Observacao: em eMBB/Best-Effort, o `M2S_received_count` do summary pode ficar em `0` por regra de correlacao estrita, mesmo com respostas tardias no CSV bruto.

### Reproduzir este marco

```bash
./scripts/run_scenario_suite.sh --duration 600 --m2s-perf
```

## Analise Completa do Marco Atual

### Caminho M2S (Middleware -> Sensor)

| Cenario | Sent | Matched | Delivery | Mean | P50 | P95 | P99 | CV | AoT Mean | Twin Fidelity |
|---------|-----:|--------:|---------:|-----:|----:|----:|----:|---:|---------:|--------------:|
| Test 1 URLLC Otimizado | 1033 | 756 | 73.18% | 324.680 ms | 324 ms | 366 ms | 403 ms | 8.91% | N/D | N/D |
| Test 2 eMBB Otimizado | 96 | 0 | 0.00% | 5436.667 ms | 5454 ms | 7289 ms | 7289 ms | 21.15% | N/D | N/D |
| Test 3 Best-Effort Otimizado | 62 | 0 | 0.00% | 9200.143 ms | 8606 ms | 11876 ms | 11876 ms | 18.35% | N/D | N/D |
| Test 4 URLLC RAW | 1019 | 745 | 73.11% | 329.173 ms | 325 ms | 374 ms | 445 ms | 8.97% | N/D | N/D |
| Test 5 eMBB RAW | 98 | 0 | 0.00% | 4713.500 ms | 4798 ms | 6003 ms | 6003 ms | 18.87% | N/D | N/D |
| Test 6 Best-Effort RAW | 62 | 0 | 0.00% | 8710.600 ms | 8746 ms | 10164 ms | 10164 ms | 12.36% | N/D | N/D |
| Test 7 URLLC M2S Perf | 1504 | 1100 | 73.14% | 282.551 ms | 281 ms | 322 ms | 337 ms | 8.01% | N/D | N/D |

Notas:
- `AoT` e `Twin Fidelity` ainda nao sao emitidos no `test_*_summary.txt` desta execucao, por isso aparecem como `N/D`.
- Assim que o pipeline 6G metrics for acoplado ao summary, estes campos devem ser atualizados nesta tabela.

### Caminho S2M (Sensor -> Middleware)

| Cenario | S2M Recebidos | S2M Enviados | S2M Pares | Mean | P50 | P95 | P99 | CV |
|---------|-------------:|-------------:|----------:|-----:|----:|----:|----:|---:|
| Test 1 URLLC Otimizado | 29424 | 7240 | 7240 | 97.01 ms | 92.00 ms | 191.00 ms | 257.00 ms | 54.98% |
| Test 2 eMBB Otimizado | 2984 | 815 | 681 | 2384.11 ms | 1754.00 ms | 7071.00 ms | 9647.00 ms | 87.85% |
| Test 3 Best-Effort Otimizado | 1575 | 439 | 243 | 4933.95 ms | 4610.00 ms | 9598.00 ms | 9894.00 ms | 61.45% |
| Test 4 URLLC RAW | 29542 | 7292 | 7292 | 108.12 ms | 101.00 ms | 213.00 ms | 286.00 ms | 54.60% |
| Test 5 eMBB RAW | 3312 | 840 | 757 | 2916.86 ms | 2655.00 ms | 6975.00 ms | 9144.00 ms | 71.72% |
| Test 6 Best-Effort RAW | 1558 | 427 | 309 | 5147.48 ms | 5064.00 ms | 9483.00 ms | 9803.00 ms | 53.75% |
| Test 7 URLLC M2S Perf | 30473 | 7290 | 7290 | 100.66 ms | 95.00 ms | 198.00 ms | 251.00 ms | 53.62% |

Nota:
- Pares calculados por matching FIFO por sensor (corrige bug de column-shift no export InfluxDB).
- URLLC: latencia S2M ~100ms, CV ~55% — comportamento esperado em Docker local.
- eMBB/Best-Effort: alta latencia S2M (2-5s) reflete throttling de QoS aplicado aos perfis.

### ODTE Geral, Formula e Metricas Agregadas

Definicoes (por direcao):

- `ODTE_M2S(%) = (M2S_matched_pairs / M2S_sent_count) * 100`
- `ODTE_S2M(%) = (S2M_matched_pairs / S2M_sent_count) * 100`

ODTE geral (quando ambas as direcoes existem):

- `ODTE_geral(%) = ((M2S_matched_pairs + S2M_matched_pairs) / (M2S_sent_count + S2M_sent_count)) * 100`

Estado no marco `outputs/tests_20260310_114533`:

| Cenario | ODTE_M2S | ODTE_S2M | ODTE_geral |
|---------|----------:|---------:|-----------:|
| Test 1 URLLC Otimizado | 73.18% | 100.00% | 96.65% |
| Test 2 eMBB Otimizado | 0.00% | 83.56% | 74.75% |
| Test 3 Best-Effort Otimizado | 0.00% | 55.35% | 48.50% |
| Test 4 URLLC RAW | 73.11% | 100.00% | 96.70% |
| Test 5 eMBB RAW | 0.00% | 90.12% | 80.70% |
| Test 6 Best-Effort RAW | 0.00% | 72.37% | 63.19% |
| Test 7 URLLC M2S Perf | 73.14% | 100.00% | 95.41% |

_ODTE_geral = (M2S_matched_pairs + S2M_matched_pairs) / (M2S_sent_count + S2M_sent_count)_

Regra de atualizacao futura:

- Sempre que houver novos resultados melhores, atualizar esta secao com os valores do novo `outputs/tests_<TIMESTAMP>` e manter este bloco como baseline historico.

## Arquitetura do Sistema

```
Simuladores (IoT) <-> ThingsBoard (MQTT/RPC) <-> Middleware DT
         \_______________________________________________/
                          InfluxDB (metricas)
```

## Como Usar

### 1. Inicializacao do ambiente

```bash
# Setup inicial
make setup

# Build de imagens (se necessario)
make build-images

# Subir topologia
make topo

# Verificacoes gerais
make check
```

### 2. Perfis de topologia

Perfis de rede (slice):

- `make urllc`
- `make eMBB`
- `make best_effort`

Perfis de configuracao (ThingsBoard/Middleware), usados com `make topo`:

- `CONFIG_PROFILE=reduced_load` (default)
- `CONFIG_PROFILE=test05_best_performance`
- `CONFIG_PROFILE=rpc_ultra_aggressive`
- `CONFIG_PROFILE=network_optimized`
- `CONFIG_PROFILE=baseline_default`

Exemplos:

```bash
make topo PROFILE=urllc CONFIG_PROFILE=reduced_load
make topo PROFILE=eMBB CONFIG_PROFILE=baseline_default
make apply-profile CONFIG_PROFILE=test05_best_performance
```

### 3. Limpeza e reset

```bash
make clean
make clean-containers
make reset-db
```

## Metricas de Avaliacao

Metricas principais:

- S2M (Simulator -> Middleware)
- M2S (Middleware -> Simulator)
- Delivery (eventual delivery por correlacao)
- Percentis P50/P95/P99 e CV

Metricas avancadas (6G Twin-level), disponiveis na analise:

- AoT (Age of Twin)
- Twin Fidelity (TF)
- ETF (Event Tracking Fidelity)

Scripts relacionados:

- `scripts/analyze_6g_twin_metrics.py`
- `scripts/intelligent_test_analysis.py`

## Resultados Principais

- **URLLC Otimizado (Test 1):** M2S media 324.7 ms, P95 366 ms, delivery 73.18%
- **URLLC RAW (Test 4):** M2S media 329.2 ms, P95 374 ms, delivery 73.11%
- **URLLC M2S Perf (Test 7):** M2S media 282.6 ms, P95 322 ms, delivery 73.14%
- **Ganho Test 7 vs Test 1:** -13% na media e -12% no P95

## Ambiente Python (um venv recomendado)

Para evitar conflito de dependencias, recomenda-se usar **apenas um venv** no repositorio.

Padrao recomendado atual: `.venv-reports`.

```bash
./scripts/setup_venv.sh
. .venv-reports/bin/activate
```

Se existir outro venv legado (`.venv-docs` etc), mantenha desativado para nao misturar pacotes.

## Documentacao Tecnica

Links validos no repositorio:

- `services/middleware-dt/README.md`
- `services/middleware-dt/docs/README.md`
- `services/iot_simulator/README.md`
- `docs/00_DOCUMENTATION_INDEX.md`

Nota: `deploy/README.md` nao existe atualmente.

## Comandos uteis

```bash
# Suite completa
./scripts/run_scenario_suite.sh --duration 600 --m2s-perf

# Apenas Teste 7
./scripts/run_scenario_suite.sh --duration 600 --test 7

# Plots e analise
make plots
make intelligent-analysis
```

---

Status: ODTE bidirectional funcional
Ultima atualizacao: Marco 2026
