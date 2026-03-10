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
