#!/bin/bash
# run_scenario_suite.sh - Executa todos os cenários de teste e gera todos os indicadores e gráficos organizados

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$WORKSPACE_ROOT"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*"; }
success() { echo -e "${GREEN}[OK] $*${NC}"; }
error() { echo -e "${RED}[ERR] $*${NC}"; }

CURRENT_SCREEN=""
CURRENT_TEST_PID=""

cleanup() {
    error "Ctrl+C detectado - Limpando..."
    if [ -n "$CURRENT_TEST_PID" ]; then
        sudo kill -9 "$CURRENT_TEST_PID" 2>/dev/null || true
    fi
    sudo pkill -9 -f "scripts/apply_slice.sh" 2>/dev/null || true
    if [ -n "$CURRENT_SCREEN" ]; then
        screen -ls | grep -E "[0-9]+\.${CURRENT_SCREEN}[[:space:]]" | awk '{print $1}' | xargs -r -I{} screen -S {} -X quit 2>/dev/null || true
    fi
    timeout 30 make clean >/dev/null 2>&1 || true
    exit 130
}
trap cleanup INT TERM

TEST_DURATION="180"
WITH_LINK_EVENTS=0
USE_RAW_CONFIG=0  # Use raw configs (high timeout) to measure real latencies
TESTS_FILTER=""  # Empty = run all tests; "1,3,5" = run only tests 1,3,5; "2,4" with skip = run 1,3,5
ENABLE_M2S_PERF_7=0  # Optional scenario 7 with M2S-focused middleware tuning
BUILD_IMAGES=0  # Rebuild Docker images before running the suite

# Args:
#   ./scripts/run_scenario_suite.sh 300
#   ./scripts/run_scenario_suite.sh --duration 300 --with-link-events
#   ./scripts/run_scenario_suite.sh --test 1 --duration 300
#   ./scripts/run_scenario_suite.sh --tests 1,3,5 --duration 300
#   ./scripts/run_scenario_suite.sh --skip 2,4 --duration 300
#   ./scripts/run_scenario_suite.sh --raw --duration 300  # Raw configs without timeout artificial
#   ./scripts/run_scenario_suite.sh --duration 300 --m2s-perf --build-images
while [ $# -gt 0 ]; do
    case "$1" in
        --duration)
            TEST_DURATION="${2:-}"
            shift 2
            ;;
        --duration=*)
            TEST_DURATION="${1#*=}"
            shift
            ;;
        --duration[0-9]*)
            # Compact form: --duration600
            TEST_DURATION="${1#--duration}"
            shift
            ;;
        -d)
            TEST_DURATION="${2:-}"
            shift 2
            ;;
        --raw)
            # Use raw configs (high timeout) to measure real latencies
            USE_RAW_CONFIG=1
            shift
            ;;
        --m2s-perf|--with-perf7)
            # Run suite + optional scenario 7 (URLLC M2S performance mode)
            TESTS_FILTER="1,2,3,4,5,6,7"
            ENABLE_M2S_PERF_7=1
            shift
            ;;
        --build-images)
            BUILD_IMAGES=1
            shift
            ;;
        --test)
            # Single test: --test 1
            TESTS_FILTER="$2"
            shift 2
            ;;
        --test=*)
            # Single test: --test=1
            TESTS_FILTER="${1#*=}"
            shift
            ;;
        --tests)
            # Multiple tests: --tests 1,3,5
            TESTS_FILTER="$2"
            shift 2
            ;;
        --tests=*)
            # Multiple tests: --tests=1,3,5
            TESTS_FILTER="${1#*=}"
            shift
            ;;
        --skip)
            # Skip tests: --skip 2,4 (runs 1,3,5)
            skip_list="$2"
            TESTS_FILTER=""
            for i in {1..7}; do
                if ! echo ",$skip_list," | grep -q ",$i,"; then
                    [ -n "$TESTS_FILTER" ] && TESTS_FILTER="$TESTS_FILTER,"
                    TESTS_FILTER="$TESTS_FILTER$i"
                fi
            done
            shift 2
            ;;
        --skip=*)
            # Skip tests: --skip=2,4
            skip_list="${1#*=}"
            TESTS_FILTER=""
            for i in {1..7}; do
                if ! echo ",$skip_list," | grep -q ",$i,"; then
                    [ -n "$TESTS_FILTER" ] && TESTS_FILTER="$TESTS_FILTER,"
                    TESTS_FILTER="$TESTS_FILTER$i"
                fi
            done
            shift
            ;;
        --with-link-events)
            WITH_LINK_EVENTS=1
            shift
            ;;
        --full|--suite)
            # Run complete suite: 7 scenarios (3 optimized + 3 raw + 1 M2S perf)
            TESTS_FILTER="1,2,3,4,5,6,7"
            shift
            ;;
        --help|-h)
            echo "Uso: $0 [--duration SEGUNDOS] [--raw] [--test N] [--tests N,M,P] [--skip N,M] [--full] [--m2s-perf] [--with-link-events] [--build-images]"
            echo ""
            echo "Opções:"
            echo "  --duration N        : Duração de cada teste em segundos [padrão: 180]"
            echo "  --raw               : Usar configs ThingsBoard RAW (timeout alto, sem artificial)"
            echo "  --test N            : Rodar apenas teste N (1-7)"
            echo "  --tests N,M,P       : Rodar apenas testes N, M, P (ex: --tests 1,3,5)"
            echo "  --skip N,M          : Rodar todos EXCETO testes N, M (ex: --skip 3,5)"
            echo "  --full              : Rodar suite padrão (testes 1-7: 3 otimizados + 3 raw + 1 M2S perf)"
            echo "  --m2s-perf          : Rodar suite + Teste 7 URLLC M2S Performance (1-7)"
            echo "  --with-link-events  : Habilita link scheduler (desabilitado por padrão)"
            echo "  --build-images      : Executa 'make build-images' uma vez antes da suite"
            echo ""
            echo "Cenários:"
            echo "  Test 1: URLLC Otimizado       [150ms timeout]"
            echo "  Test 2: eMBB Otimizado        [300ms timeout]"
            echo "  Test 3: Best-Effort Otimizado [500ms timeout]"
            echo "  Test 4: URLLC RAW             [30000ms timeout - diagnóstico]"
            echo "  Test 5: eMBB RAW              [5000ms timeout - diagnóstico]"
            echo "  Test 6: Best-Effort RAW       [10000ms timeout - diagnóstico]"
            echo "  Test 7: URLLC M2S Performance [MiddTS fast mode + TB RPC 220ms]"

            echo ""
            echo "Exemplos:"
            echo "  $0 --duration 150 --full              # Suite padrão: 6×150s = 15 minutos"
            echo "  $0 --duration 150 --m2s-perf          # Suite + cenário 7 M2S"
            echo "  $0 --duration 150 --test 7            # Apenas cenário 7"
            echo "  $0 --duration 600 --m2s-perf --build-images"

            exit 0
            ;;
        --*)
            error "Flag invalida: '$1'"
            echo "Uso: $0 [--duration SEGUNDOS] [--raw] [--test N] [--tests N,M,P] [--skip N,M] [--with-link-events] [--build-images]"
            exit 2
            ;;
        *)
            # Backward-compatible positional duration
            TEST_DURATION="$1"
            shift
            ;;
    esac
done

# Function to check if test should run
should_run_test() {
    local test_num="$1"
    if [ -z "$TESTS_FILTER" ]; then
        [ "$test_num" -le 7 ] && return 0 || return 1
    fi
    echo ",$TESTS_FILTER," | grep -q ",$test_num," && return 0 || return 1
}

case "$TEST_DURATION" in
    ''|*[!0-9]*)
        error "Duracao invalida: '$TEST_DURATION' (use inteiro em segundos)"
        exit 2
        ;;
esac

RESULTS_DIR="outputs/tests_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

# Enable latency measurements for testing (default is False in production)
export ENABLE_INFLUX_LATENCY_MEASUREMENTS=True

log "==========================================="
log "SUITE DE TESTES AUTOMATIZADA"
log "==========================================="
log "Duracao: ${TEST_DURATION}s por cenario"
log "Resultados: $RESULTS_DIR"
if [ -z "$TESTS_FILTER" ]; then
    log "Cenários: PADRÃO (1,2,3,4,5,6,7)"
else
    log "Cenários: $TESTS_FILTER (filtrado)"
fi
if [ "$USE_RAW_CONFIG" -eq 1 ]; then
    log "Modo: RAW (timeout alto, mede latências reais sem timeout artificial)"
else
    log "Modo: OTIMIZADO (timeouts calibrados)"
fi
if [ "$WITH_LINK_EVENTS" -eq 1 ]; then
    log "Link Scheduler: HABILITADO"
else
    log "Link Scheduler: DESABILITADO"
fi
if [ "$BUILD_IMAGES" -eq 1 ]; then
    log "Imagens: REBUILD antes da suite"
else
    log "Imagens: reutilizando imagens locais atuais"
fi
log ""
log ""

if [ "$BUILD_IMAGES" -eq 1 ]; then
    log "0. Reconstruindo imagens Docker..."
    make build-images || {
        error "Falha no build das imagens Docker"
        exit 1
    }
fi

run_scenario() {
    local num="$1" profile="$2" tb_flag="$3" desc="$4"
    local scenario_failed=0
    
    # Adjust description based on mode
    if [ "$USE_RAW_CONFIG" -eq 1 ]; then
        case "$num" in
            1) desc="URLLC + TB 30000ms RAW (measure real latencies)" ;;
            2) desc="eMBB + TB 5000ms RAW (measure real latencies)" ;;
            3) desc="eMBB + TB 5000ms RAW (measure real latencies)" ;;
            4) desc="Best-Effort + TB 10000ms RAW (measure real latencies)" ;;
            5) desc="Best-Effort + TB 10000ms RAW (measure real latencies)" ;;
            6) desc="Best-Effort + TB 10000ms RAW (measure real latencies)" ;;
        esac
    fi
    
    log ""
    log "==========================================="
    log "[$num/7] $desc"
    log "==========================================="
    log "1. Limpando..."
    timeout 60 make clean >/dev/null 2>&1 || true
    
    # Ensure complete topology isolation between tests
    # Force removal of any existing Containernet containers to guarantee clean state
    log "   Garantindo remoção completa de containers para isolamento total..."
    # Kill any existing containernet containers
    docker ps -a --format '{{.Names}}' | grep '^mn\.' | xargs -r docker rm -f >/dev/null 2>&1 || true
    # Clean Mininet state
    sudo mn -c >/dev/null 2>&1 || true
    sleep 3
    sleep 5
    log "2. Criando topologia $profile..."
    CURRENT_SCREEN="topo_${num}"
    # Export config mode flags so topo_qos.py can select the correct ThingsBoard config
    local raw_env_value="false"
    local m2s_perf_env_value="false"
    if [ "$USE_RAW_CONFIG" -eq 1 ]; then
        raw_env_value="true"
        log "   [RAW mode] ThingsBoard will mount RAW config (high timeout for real latency measurement)"
    fi
    if echo " $tb_flag " | grep -q -- "--m2s-perf"; then
        m2s_perf_env_value="true"
        log "   [M2S perf mode] ThingsBoard should mount URLLC M2S performance config"
    fi
    local screen_bootstrap_log="/tmp/topo_${num}_bootstrap.log"
    rm -f "$screen_bootstrap_log" /tmp/topo_${num}.log
    screen -L -Logfile "$screen_bootstrap_log" -dmS "$CURRENT_SCREEN" bash -lc "cd $WORKSPACE_ROOT && USE_RAW_CONFIG=$raw_env_value USE_M2S_PERF=$m2s_perf_env_value make topo PROFILE=$profile"
    log "3. Aguardando CLI..."
    i=0
    cli_bootstrap_seen_at=0
    while true; do
        i=$((i + 1))

        # If screen session disappeared, fail fast with useful diagnostics.
        if ! screen -list 2>/dev/null | grep -q "\\.${CURRENT_SCREEN}[[:space:]]"; then
            error "Sessao screen '$CURRENT_SCREEN' nao encontrada (encerrou cedo)."
            if [ -f "$screen_bootstrap_log" ]; then
                error "Ultimas linhas do bootstrap log ($screen_bootstrap_log):"
                tail -n 40 "$screen_bootstrap_log" || true
            fi
            return 1
        fi

        screen -S "$CURRENT_SCREEN" -X hardcopy "/tmp/topo_${num}.log" >/dev/null 2>&1 || true
        grep -q "Starting CLI:" /tmp/topo_${num}.log 2>/dev/null \
            && grep -q "containernet>" /tmp/topo_${num}.log 2>/dev/null \
            && { log "   CLI pronto (${i}s)"; break; }

        # Fallback: in some runs, screen hardcopy may miss the interactive prompt
        # even though bootstrap log already reached "*** Starting CLI:".
        if [ "$cli_bootstrap_seen_at" -eq 0 ] && grep -q "\*\*\* Starting CLI:" "$screen_bootstrap_log" 2>/dev/null; then
            cli_bootstrap_seen_at="$i"
            log "   Bootstrap atingiu 'Starting CLI' (${i}s); aguardando prompt por mais 20s..."
        fi
        if [ "$cli_bootstrap_seen_at" -gt 0 ] && [ $((i - cli_bootstrap_seen_at)) -ge 20 ]; then
            log "   CLI considerado pronto via bootstrap log (${i}s)"
            break
        fi

        if [ "$i" -ge 900 ]; then
            error "Timeout aguardando CLI no screen '$CURRENT_SCREEN' (900s)."
            if [ -f "$screen_bootstrap_log" ]; then
                error "Ultimas linhas do bootstrap log ($screen_bootstrap_log):"
                tail -n 40 "$screen_bootstrap_log" || true
            fi
            return 1
        fi

        [ $((i % 30)) -eq 0 ] && log "   Aguardando (${i}s)..."
        sleep 1
    done
    log "4. Aguardando containers..."
    for i in $(seq 1 60); do
        cnt=0
        docker ps 2>/dev/null | grep -q "mn.tb" && cnt=$((cnt + 1)) || true
        docker ps 2>/dev/null | grep -q "mn.middts" && cnt=$((cnt + 1)) || true
        docker ps 2>/dev/null | grep -q "mn.influxdb" && cnt=$((cnt + 1)) || true
        docker ps 2>/dev/null | grep -q "mn.sim" && cnt=$((cnt + 1)) || true
        [ $cnt -ge 4 ] && { log "   Containers prontos"; break; }
        sleep 2
    done
    log "5. Iniciando teste em 10s..."
    sleep 10
    log "6. Executando (${TEST_DURATION}s)..."
    rm -f .current_slice_profile
    
    # Disable link scheduler by default (for article baseline metrics)
    # Use --with-link-events flag to enable resilience testing
    if [ "$WITH_LINK_EVENTS" -eq 0 ]; then
        export SCHEDULE_FILE=/dev/null
    fi
    
    # Build apply_slice.sh arguments.
    # In RAW mode, always apply RAW TB config for all scenarios (ignore baseline --no-tb-config)
    # so tests are directly comparable under the same timeout policy.
    local apply_args="$tb_flag"
    if [ "$USE_RAW_CONFIG" -eq 1 ]; then
        apply_args="--raw"
    fi
    
    # Extra buffer for test execution, export, and cleanup.
    # Since ThingsBoard now starts with correct config (no restart needed),
    # we only need buffer for: test duration + data export + safety margin
    local timeout_buffer=600  # 10 minutes: test + export + margin
    timeout $((TEST_DURATION + timeout_buffer)) ./scripts/apply_slice.sh $apply_args "$profile" --execute-scenario "$TEST_DURATION" &
    CURRENT_TEST_PID=$!
    wait $CURRENT_TEST_PID 2>/dev/null || true
    CURRENT_TEST_PID=""
    log "7. Aguardando flush (60s)..."
    sleep 60
    log "8. Coletando..."
    latest_test_dir=$(find outputs/results -maxdepth 1 -type d -name "test_*_${profile}" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    latest_device_csv=$(find "$latest_test_dir" -maxdepth 1 -type f -name "*_device_data.csv" | head -1)
    latest_latency_csv=$(find "$latest_test_dir" -maxdepth 1 -type f -name "*_latency_measurement.csv" | head -1)
    latest_summary=$(find "$latest_test_dir" -maxdepth 1 -type f -name "summary_*.txt" | head -1)
    latest_latency_analysis=$(find "$latest_test_dir" -maxdepth 1 -type f -name "latency_analysis.txt" | head -1)
    latest_correlation=$(find "$latest_test_dir" -maxdepth 1 -type f -name "latency_analysis_correlation.txt" | head -1)
    
    if [ -n "$latest_device_csv" ] && [ -s "$latest_device_csv" ] && [ -n "$latest_latency_csv" ] && [ -s "$latest_latency_csv" ]; then
        # Copy CSVs for archival
        cp "$latest_device_csv" "$RESULTS_DIR/test_${num}_device_data.csv"
        cp "$latest_latency_csv" "$RESULTS_DIR/test_${num}_latency_measurement.csv"
        
        # Copy analysis files already generated by apply_slice.sh (these use correlation_id and dedup logic)
        [ -f "$latest_summary" ] && cp "$latest_summary" "$RESULTS_DIR/test_${num}_summary.txt"
        [ -f "$latest_latency_analysis" ] && cp "$latest_latency_analysis" "$RESULTS_DIR/test_${num}_latency_analysis.txt"
        [ -f "$latest_correlation" ] && cp "$latest_correlation" "$RESULTS_DIR/test_${num}_correlation.txt"
        
        # Create merged CSV for compatibility
        merged_csv="$RESULTS_DIR/test_${num}.csv"
        {
            echo ",result,table,_start,_stop,_time,_value,_field,_measurement,direction,dt_id,request_id,sensor,source"
            tail -n +2 "$latest_device_csv" | awk -F',' 'BEGIN{OFS=","} {print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,"",$11,$12,$13}'
            tail -n +2 "$latest_latency_csv"
        } > "$merged_csv"
        
        success "Resultados copiados para Teste $num (usando análise correta do apply_slice.sh)"

        # Compute derived post-test metrics: M2S matched pairs, AoT, Twin Fidelity, S2M FIFO pairing
        log "8b. Computando métricas pós-teste (M2S matched, AoT, TwinFidelity, S2M FIFO)..."
        local reports_dir="${latest_test_dir}/generated_reports"
        python3 scripts/reports/report_generators/_compute_run_metrics.py \
            --reports-dir "$reports_dir" \
            --profile "$profile" \
            --summary "$RESULTS_DIR/test_${num}_summary.txt" \
            --device-csv "$RESULTS_DIR/test_${num}_device_data.csv" \
            --latency-csv "$RESULTS_DIR/test_${num}_latency_measurement.csv" 2>/dev/null \
            || log "[AVISO] compute metrics falhou para teste ${num} (nao critico)"
    else
        error "CSVs do teste ausentes ou vazios (device_data + latency_measurement)"
        scenario_failed=1
    fi
    log "9. Limpando..."
    screen -ls | grep -E "[0-9]+\.${CURRENT_SCREEN}[[:space:]]" | awk '{print $1}' | xargs -r -I{} screen -S {} -X quit 2>/dev/null || true
    CURRENT_SCREEN=""
    timeout 60 make clean >/dev/null 2>&1 || true
    sleep 5
    if [ -f "$RESULTS_DIR/test_${num}_correlation.txt" ]; then
        success "Teste $num OK"
    else
        error "Teste $num FALHOU (sem correlation report)"
        scenario_failed=1
    fi

    if [ "$scenario_failed" -ne 0 ]; then
        return 1
    fi
}

# TIER 1: OPTIMIZED PROFILES (TB timeout calibrated for best performance)
if should_run_test 1; then run_scenario 1 "urllc" "" "Test 1/6: URLLC Otimizado [150ms timeout]" || exit 1; fi
if should_run_test 2; then run_scenario 2 "embb" "" "Test 2/6: eMBB Otimizado [300ms timeout]" || exit 1; fi
if should_run_test 3; then run_scenario 3 "best_effort" "" "Test 3/6: Best-Effort Otimizado [500ms timeout]" || exit 1; fi

# TIER 2: RAW PROFILES (TB timeout very high - diagnóstico, mede latências reais)
if should_run_test 4; then run_scenario 4 "urllc" "" "Test 4/6: URLLC RAW [30000ms - diagnóstico]" || exit 1; fi
if should_run_test 5; then run_scenario 5 "embb" "" "Test 5/6: eMBB RAW [5000ms - diagnóstico]" || exit 1; fi
if should_run_test 6; then run_scenario 6 "best_effort" "" "Test 6/6: Best-Effort RAW [10000ms - diagnóstico]" || exit 1; fi

# TIER 3: OPTIONAL M2S PERFORMANCE PROFILE
if should_run_test 7; then run_scenario 7 "urllc" "--m2s-perf" "Test 7/7: URLLC M2S Performance [MiddTS fast mode + TB 220ms]" || exit 1; fi

log ""
log "==========================================="
log "RESUMO FINAL"
log "==========================================="
for i in $(seq 1 7); do
    [ -f "$RESULTS_DIR/test_${i}_summary.txt" ] && { log ""; cat "$RESULTS_DIR/test_${i}_summary.txt"; }
done

log ""
log "==========================================="
log "TABELA COMPARATIVA (CORRELATION-ID)"
log "==========================================="
USE_RAW_CONFIG="$USE_RAW_CONFIG" python3 - "$RESULTS_DIR" <<'PY'
import re
import sys
import os

results_dir = sys.argv[1]
use_raw = os.environ.get('USE_RAW_CONFIG', '0') in ('1', 'true', 'True')

labels = {
    1: 'URLLC Otimizado (150ms)',
    2: 'eMBB Otimizado (300ms)',
    3: 'Best-Effort Otimizado (500ms)',
    4: 'URLLC RAW (30000ms)',
    5: 'eMBB RAW (5000ms)',
    6: 'Best-Effort RAW (10000ms)',
    7: 'URLLC M2S Perf (220ms + fast mode)',
}

def extract_from_correlation(corr_file):
    """Extract metrics from latency_analysis_correlation.txt"""
    if not os.path.exists(corr_file):
        return None
    
    with open(corr_file, 'r') as f:
        content = f.read()
    
    # Extract key metrics using regex
    sent_m = re.search(r'Total commands sent:\s*(\d+)', content)
    recv_m = re.search(r'Total responses received:\s*(\d+)', content)
    delivery_m = re.search(r'Eventual Delivery.*?(\d+\.\d+)%', content)
    mean_m = re.search(r'All Delivery Latencies.*?Mean:\s*([\d.]+)', content, re.DOTALL)
    p95_m = re.search(r'P95:\s*([\d.]+)', content)
    cv_m = re.search(r'CV:\s*([\d.]+)%', content)
    
    if not all([sent_m, recv_m, delivery_m]):
        return None
    
    return {
        'sent': int(sent_m.group(1)),
        'recv': int(recv_m.group(1)),
        'delivery': float(delivery_m.group(1)),
        'mean': float(mean_m.group(1)) if mean_m else 0,
        'p95': float(p95_m.group(1)) if p95_m else 0,
        'cv': float(cv_m.group(1)) if cv_m else 0,
    }

def extract_from_summary(summary_file):
    """Extract S2M metrics from summary file"""
    if not os.path.exists(summary_file):
        return None
    
    with open(summary_file, 'r') as f:
        content = f.read()
    
    s2m_count_m = re.search(r'S2M_total_count:\s*(\d+)', content)
    s2m_mean_m = re.search(r'mean_S2M_ms:\s*([\d.]+)', content)
    s2m_p95_m = re.search(r'P95_S2M_ms:\s*([\d.]+)', content)
    
    return {
        's2m_count': int(s2m_count_m.group(1)) if s2m_count_m else 0,
        's2m_mean': float(s2m_mean_m.group(1)) if s2m_mean_m else 0,
        's2m_p95': float(s2m_p95_m.group(1)) if s2m_p95_m else 0,
    }

print('Cenário | S2M | M2S Sent | M2S Recv | Delivery | M2S Mean | M2S P95 | CV')
print('---|---:|---:|---:|---:|---:|---:|---:')

for idx in range(1, 8):
    if idx not in labels:
        continue
    label = labels[idx]
    corr_file = os.path.join(results_dir, f'test_{idx}_correlation.txt')
    summary_file = os.path.join(results_dir, f'test_{idx}_summary.txt')
    
    m2s_data = extract_from_correlation(corr_file)
    s2m_data = extract_from_summary(summary_file)
    
    if not m2s_data:
        print(f'{label} | NA | NA | NA | NA | NA | NA | NA')
    else:
        s2m_str = str(s2m_data['s2m_count']) if s2m_data else 'NA'
        s2m_mean_str = f"{s2m_data['s2m_mean']:.1f}" if s2m_data and s2m_data['s2m_mean'] > 0 else 'NA'
        s2m_p95_str = f"{s2m_data['s2m_p95']:.0f}" if s2m_data and s2m_data['s2m_p95'] > 0 else 'NA'
        
        print(
            f"{label} | {s2m_str} | {m2s_data['sent']} | {m2s_data['recv']} | "
            f"{m2s_data['delivery']:.2f}% | {m2s_data['mean']:.1f}ms | {m2s_data['p95']:.0f}ms | {m2s_data['cv']:.2f}%"
        )
PY

log ""
success "CONCLUIDO!"
log "CSVs em: $RESULTS_DIR"
ls -lh "$RESULTS_DIR"/test_*.csv 2>/dev/null || true
