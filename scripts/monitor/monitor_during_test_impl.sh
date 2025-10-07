#!/bin/bash
# Script para monitorar gargalos DURANTE a execução do teste URLLC
# Uso: ./monitor_during_test.sh <duração_em_segundos>

DURATION=${1:-60}
OUTPUT_DIR="results/monitoring_$(date +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUTPUT_DIR"

echo "🔍 INICIANDO MONITORAMENTO DURANTE TESTE URLLC"
echo "==============================================="
echo "Duração: ${DURATION}s"
echo "Output: $OUTPUT_DIR"
echo "Timestamp: $(date)"
echo ""

# Função para monitorar continuamente
monitor_performance() {
    local interval=5  # Coleta a cada 5 segundos
    local iterations=$((DURATION / interval))
    
    echo "timestamp,tb_cpu,tb_mem_gb,pg_cpu,pg_mem_gb,middts_cpu,middts_mem_gb,host_cpu,host_mem_gb,active_sims" > "$OUTPUT_DIR/performance.csv"
    
    for i in $(seq 1 $iterations); do
        timestamp=$(date +%Y-%m-%dT%H:%M:%SZ)
        
        # ThingsBoard stats
        if docker ps --format "{{.Names}}" | grep -q "^mn.tb$"; then
            tb_stats=$(docker stats mn.tb --no-stream --format "{{.CPUPerc}},{{.MemUsage}}")
            tb_cpu=$(echo $tb_stats | cut -d',' -f1 | sed 's/%//')
            tb_mem=$(echo $tb_stats | cut -d',' -f2 | cut -d'/' -f1 | sed 's/[^0-9.]//g')
        else
            tb_cpu=0; tb_mem=0
        fi
        
        # PostgreSQL stats
        pg_container=$(docker ps --format "{{.Names}}" | grep "^mn.pg" | head -1)
        if [ "$pg_container" ]; then
            pg_stats=$(docker stats $pg_container --no-stream --format "{{.CPUPerc}},{{.MemUsage}}")
            pg_cpu=$(echo $pg_stats | cut -d',' -f1 | sed 's/%//')
            pg_mem=$(echo $pg_stats | cut -d',' -f2 | cut -d'/' -f1 | sed 's/[^0-9.]//g')
        else
            pg_cpu=0; pg_mem=0
        fi
        
        # Middleware stats
        if docker ps --format "{{.Names}}" | grep -q "^mn.middts$"; then
            middts_stats=$(docker stats mn.middts --no-stream --format "{{.CPUPerc}},{{.MemUsage}}")
            middts_cpu=$(echo $middts_stats | cut -d',' -f1 | sed 's/%//')
            middts_mem=$(echo $middts_stats | cut -d',' -f2 | cut -d'/' -f1 | sed 's/[^0-9.]//g')
        else
            middts_cpu=0; middts_mem=0
        fi
        
        # Host stats
        host_cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
        host_mem=$(free -g | grep Mem | awk '{print $3}')
        
        # Active simulators
        active_sims=$(docker ps --format "{{.Names}}" | grep "^mn.sim_" | wc -l)
        
        echo "$timestamp,$tb_cpu,$tb_mem,$pg_cpu,$pg_mem,$middts_cpu,$middts_mem,$host_cpu,$host_mem,$active_sims" >> "$OUTPUT_DIR/performance.csv"
        
        # Log crítico a cada 30s
        if [ $((i % 6)) -eq 0 ]; then
            echo "[$(date +%H:%M:%S)] TB:${tb_cpu}% | PG:${pg_cpu}% | MID:${middts_cpu}% | HOST:${host_cpu}% | SIMS:${active_sims}"
        fi
        
        sleep $interval
    done
}

# Função para capturar configurações no início
capture_config() {
    echo "🔧 Capturando configurações iniciais..."
    
    echo "=== THINGSBOARD CONFIG ===" > "$OUTPUT_DIR/config_snapshot.txt"
    if docker ps --format "{{.Names}}" | grep -q "^mn.tb$"; then
        docker exec mn.tb grep -E "(CLIENT_SIDE_RPC_TIMEOUT|HTTP_REQUEST_TIMEOUT|BATCH.*DELAY)" /usr/share/thingsboard/conf/thingsboard.yml >> "$OUTPUT_DIR/config_snapshot.txt" 2>/dev/null
    fi
    
    echo -e "\n=== JAVA PROCESS ===" >> "$OUTPUT_DIR/config_snapshot.txt"
    if docker ps --format "{{.Names}}" | grep -q "^mn.tb$"; then
        docker exec mn.tb ps aux | grep java | head -1 >> "$OUTPUT_DIR/config_snapshot.txt" 2>/dev/null
    fi
    
    echo -e "\n=== SIMULATOR CONFIG ===" >> "$OUTPUT_DIR/config_snapshot.txt"
    if docker ps --format "{{.Names}}" | grep -q "^mn.sim_001$"; then
        docker exec mn.sim_001 grep -E "HEARTBEAT" /iot_simulator/iot_simulator/settings.py >> "$OUTPUT_DIR/config_snapshot.txt" 2>/dev/null || echo "Config não encontrada" >> "$OUTPUT_DIR/config_snapshot.txt"
    fi
}

# Função para analisar resultados
analyze_bottlenecks() {
    echo ""
    echo "🚨 ANÁLISE DE GARGALOS (baseada no monitoramento):"
    echo "=================================================="
    
    # Análise do CSV
    if [ -f "$OUTPUT_DIR/performance.csv" ]; then
        avg_tb_cpu=$(awk -F',' 'NR>1 {sum+=$2; count++} END {if(count>0) printf "%.1f", sum/count}' "$OUTPUT_DIR/performance.csv")
        max_tb_cpu=$(awk -F',' 'NR>1 {if($2>max) max=$2} END {printf "%.1f", max}' "$OUTPUT_DIR/performance.csv")
        
        avg_pg_cpu=$(awk -F',' 'NR>1 {sum+=$4; count++} END {if(count>0) printf "%.1f", sum/count}' "$OUTPUT_DIR/performance.csv")
        max_pg_cpu=$(awk -F',' 'NR>1 {if($4>max) max=$4} END {printf "%.1f", max}' "$OUTPUT_DIR/performance.csv")
        
        avg_middts_cpu=$(awk -F',' 'NR>1 {sum+=$6; count++} END {if(count>0) printf "%.1f", sum/count}' "$OUTPUT_DIR/performance.csv")
        max_middts_cpu=$(awk -F',' 'NR>1 {if($6>max) max=$6} END {printf "%.1f", max}' "$OUTPUT_DIR/performance.csv")
        
        echo "📊 CPU Usage durante o teste:"
        echo "  🔹 ThingsBoard: Média ${avg_tb_cpu}% | Pico ${max_tb_cpu}%"
        echo "  🔹 PostgreSQL: Média ${avg_pg_cpu}% | Pico ${max_pg_cpu}%"
        echo "  🔹 Middleware: Média ${avg_middts_cpu}% | Pico ${max_middts_cpu}%"
        
        # Identificar gargalos
        if (( $(echo "$max_tb_cpu > 80" | bc -l) )); then
            echo "🚨 GARGALO IDENTIFICADO: ThingsBoard CPU alto (${max_tb_cpu}%)"
        fi
        
        if (( $(echo "$max_pg_cpu > 70" | bc -l) )); then
            echo "🚨 GARGALO IDENTIFICADO: PostgreSQL CPU alto (${max_pg_cpu}%)"
        fi
        
        if (( $(echo "$max_middts_cpu > 60" | bc -l) )); then
            echo "🚨 GARGALO IDENTIFICADO: Middleware CPU alto (${max_middts_cpu}%)"
        fi
        
        if (( $(echo "$max_tb_cpu < 30" | bc -l) )) && (( $(echo "$max_pg_cpu < 30" | bc -l) )); then
            echo "✅ Hardware está OK - gargalo provavelmente é configuracional"
            echo "🎯 RECOMENDAÇÃO: Focar em reduzir timeouts e otimizar configurações"
        fi
    fi
    
    echo ""
    echo "📁 Dados completos salvos em: $OUTPUT_DIR"
}

# Script principal
echo "⏳ Aguardando 10 segundos para os simuladores iniciarem..."
sleep 10

echo "🔧 Capturando configuração inicial..."
capture_config

echo "📊 Iniciando monitoramento por ${DURATION}s..."
monitor_performance &
MONITOR_PID=$!

# Aguardar fim do monitoramento
wait $MONITOR_PID

echo ""
echo "✅ Monitoramento concluído!"
analyze_bottlenecks

echo ""
echo "🎯 Para usar os dados:"
echo "  • Performance CSV: $OUTPUT_DIR/performance.csv"
echo "  • Config snapshot: $OUTPUT_DIR/config_snapshot.txt"
echo "  • Análise completa salva em: $OUTPUT_DIR/"
