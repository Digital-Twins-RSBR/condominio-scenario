# Cenario Condominio - URLLC com ODTE Bidirectional

Testbed de avaliacao de desempenho URLLC/eMBB/Best-Effort para aplicacoes IoT em condominios inteligentes, com medicao de latencia ODTE (One-Way Delay Time) bidirecional (Sensor->Middleware e Middleware->Sensor).

## Marco Atual - Suite Completa (2026-03-10)

Execucao de referencia: 7 cenarios, `--duration 600`.
Dados: `outputs/tests_20260310_185810/`.

| Cenario | S2M eventos | M2S Sent | M2S Recv | Delivery | Media M2S | P95 M2S |
|---------|------------:|---------:|---------:|---------:|----------:|--------:|
| Test 1 URLLC Otimizado (150ms)     | 29 577 | 1 063 |   778 | 73.19% | 309.6 ms | 349 ms |
| Test 2 eMBB Otimizado (300ms)      |  3 266 |    97 |     7 |  7.22% | 5173.3 ms | 6112 ms |
| Test 3 Best-Effort Otimizado (500ms) |  1 580 |    61 |     7 | 11.48% | 8713.6 ms | 10896 ms |
| Test 4 URLLC RAW (30 000ms)        | 29 594 | 1 064 |   779 | 73.21% | 307.3 ms | 354 ms |
| Test 5 eMBB RAW (5 000ms)          |  3 362 |    97 |    15 | 15.46% | 5157.4 ms | 6374 ms |
| Test 6 Best-Effort RAW (10 000ms)  |  1 585 |    62 |     5 |  8.06% | 8694.4 ms | 10976 ms |
| Test 7 URLLC M2S Perf (220ms)      | 30 532 | 1 525 | 1 115 | 73.11% | 276.5 ms | 313 ms |

**Test 7 vs Test 1:** -33 ms na media (-10.7%), -36 ms no P95 (-10.3%), CV 8.03% vs 8.89%.

Observacao: os valores de `M2S Recv` e `Delivery` acima sao calculados pelo pos-processamento em `_compute_run_metrics.py`, usando pareamento por `correlation_id` no CSV bruto exportado.

### Reproduzir este marco

```bash
./scripts/run_scenario_suite.sh --duration 600 --m2s-perf
```

## Analise Completa do Marco Atual

### Caminho M2S (Middleware -> Sensor)

| Cenario | Sent | Matched | Delivery | Mean | P50 | P95 | P99 | CV | AoT Mean | Twin Fidelity |
|---------|-----:|--------:|---------:|-----:|----:|----:|----:|---:|---------:|--------------:|
| Test 1 URLLC Otimizado | 1063 | 778 | 73.19% | 309.639 ms | 307 ms | 349 ms | 390 ms | 8.89% | 309.64 ms | 73.19% |
| Test 2 eMBB Otimizado | 97 | 7 | 7.22% | 5173.286 ms | 4989 ms | 6112 ms | 6112 ms | 13.41% | 5173.29 ms | 7.22% |
| Test 3 Best-Effort Otimizado | 61 | 7 | 11.48% | 8713.571 ms | 8552 ms | 10896 ms | 10896 ms | 15.04% | 8713.57 ms | 11.48% |
| Test 4 URLLC RAW | 1064 | 779 | 73.21% | 307.268 ms | 305 ms | 354 ms | 389 ms | 8.59% | 307.27 ms | 73.21% |
| Test 5 eMBB RAW | 97 | 15 | 15.46% | 5157.400 ms | 4981 ms | 6374 ms | 6374 ms | 16.25% | 5157.40 ms | 15.46% |
| Test 6 Best-Effort RAW | 62 | 5 | 8.06% | 8694.400 ms | 8161 ms | 10976 ms | 10976 ms | 15.13% | 8694.40 ms | 8.06% |
| Test 7 URLLC M2S Perf | 1525 | 1115 | 73.11% | 276.469 ms | 275 ms | 313 ms | 336 ms | 8.03% | 276.47 ms | 73.11% |

Notas:
- `Matched` = pares (correlation_id) entregues em ate 60s (entrega eventual, nao necessariamente dentro do SLA).
- `Delivery` = % de comandos que receberam resposta eventual (mesmo apos timeout do TB).
- `AoT Mean` = latencia media M2S = frescor do estado do Digital Twin.
- `Twin Fidelity` = % de atualizacoes M2S que chegaram com sucesso = confiabilidade de sincronizacao.
- eMBB/best-effort: TF segue baixo por timeout no caminho RPC (300ms/500ms), mas o novo baseline ja mostra melhoria em eMBB (7.22% no otimizado e 15.46% no RAW).

### Caminho S2M (Sensor -> Middleware)

| Cenario | S2M Recebidos | S2M Enviados | S2M Pares | Mean | P50 | P95 | P99 | CV |
|---------|-------------:|-------------:|----------:|-----:|----:|----:|----:|---:|
| Test 1 URLLC Otimizado | 29577 | 7295 | 7295 | 98.46 ms | 92.00 ms | 203.00 ms | 270.00 ms | 58.47% |
| Test 2 eMBB Otimizado | 3266 | 848 | 746 | 2465.54 ms | 2149.00 ms | 6059.00 ms | 8035.00 ms | 70.78% |
| Test 3 Best-Effort Otimizado | 1580 | 430 | 266 | 4914.91 ms | 4531.00 ms | 9278.00 ms | 9885.00 ms | 57.42% |
| Test 4 URLLC RAW | 29594 | 7282 | 7282 | 103.58 ms | 98.00 ms | 210.00 ms | 284.00 ms | 56.74% |
| Test 5 eMBB RAW | 3362 | 884 | 759 | 3138.97 ms | 2793.00 ms | 7145.00 ms | 9377.00 ms | 68.84% |
| Test 6 Best-Effort RAW | 1585 | 442 | 272 | 4790.90 ms | 4662.00 ms | 9586.00 ms | 9962.00 ms | 63.50% |
| Test 7 URLLC M2S Perf | 30532 | 7305 | 7305 | 103.30 ms | 98.00 ms | 207.00 ms | 260.00 ms | 54.92% |

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

Estado no marco `outputs/tests_20260310_185810`:

| Cenario | ODTE_M2S | ODTE_S2M | ODTE_geral |
|---------|----------:|---------:|-----------:|
| Test 1 URLLC Otimizado | 73.19% | 100.00% | 96.59% |
| Test 2 eMBB Otimizado | 7.22% | 87.97% | 79.68% |
| Test 3 Best-Effort Otimizado | 11.48% | 61.86% | 55.60% |
| Test 4 URLLC RAW | 73.21% | 100.00% | 96.59% |
| Test 5 eMBB RAW | 15.46% | 85.86% | 78.90% |
| Test 6 Best-Effort RAW | 8.06% | 61.54% | 54.96% |
| Test 7 URLLC M2S Perf | 73.11% | 100.00% | 95.36% |

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

- **URLLC Otimizado (Test 1):** M2S media 309.6 ms, P95 349 ms, delivery 73.19%
- **URLLC RAW (Test 4):** M2S media 307.3 ms, P95 354 ms, delivery 73.21%
- **URLLC M2S Perf (Test 7):** M2S media 276.5 ms, P95 313 ms, delivery 73.11%
- **Ganho Test 7 vs Test 1:** -10.7% na media e -10.3% no P95

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
