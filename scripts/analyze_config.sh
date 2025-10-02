#!/bin/bash
# Script para análise detalhada de configurações e identificação de otimizações

echo "🔧 ANÁLISE DETALHADA DE CONFIGURAÇÕES URLLC"
echo "============================================="
echo "Timestamp: $(date)"
echo ""

echo "📊 1. THINGSBOARD CONFIG ANALYSIS:"
echo "-----------------------------------"
if docker ps --format "{{.Names}}" | grep -q "^mn.tb$"; then
    echo "🔹 RPC & HTTP Timeouts:"
    docker exec mn.tb grep -E "(CLIENT_SIDE_RPC_TIMEOUT|HTTP_REQUEST_TIMEOUT_MS|MQTT_TIMEOUT)" /usr/share/thingsboard/conf/thingsboard.yml 2>/dev/null || echo "  ❌ Config não encontrada"
    
    echo "🔹 Batch Processing:"
    docker exec mn.tb grep -E "(BATCH.*DELAY|BATCH.*SIZE)" /usr/share/thingsboard/conf/thingsboard.yml 2>/dev/null || echo "  ❌ Config não encontrada"
    
    echo "🔹 Queue Configuration:"
    docker exec mn.tb grep -E "(QUEUE.*THREAD|QUEUE.*POLL)" /usr/share/thingsboard/conf/thingsboard.yml 2>/dev/null || echo "  ❌ Config não encontrada"
    
    echo "🔹 Java Process Info:"
    docker exec mn.tb ps aux | grep java | head -1 | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}' 2>/dev/null || echo "  ❌ Processo Java não encontrado"
fi

echo ""
echo "📊 2. DATABASE CONFIG ANALYSIS:"
echo "--------------------------------"
if docker ps --format "{{.Names}}" | grep -q "^mn.pg"; then
    PG_CONTAINER=$(docker ps --format "{{.Names}}" | grep "^mn.pg" | head -1)
    echo "🔹 PostgreSQL Settings:"
    docker exec $PG_CONTAINER psql -U thingsboard -d thingsboard -c "SHOW shared_buffers; SHOW work_mem; SHOW maintenance_work_mem;" 2>/dev/null || echo "  ❌ Settings não disponíveis"
    
    echo "🔹 Connection Info:"
    docker exec $PG_CONTAINER psql -U thingsboard -d thingsboard -c "SHOW max_connections; SELECT count(*) as current_connections FROM pg_stat_activity;" 2>/dev/null || echo "  ❌ Connection info não disponível"
fi

echo ""
echo "📊 3. NETWORK CONFIG ANALYSIS:"
echo "-------------------------------"
echo "🔹 Container Network Settings:"
for container in mn.tb mn.middts mn.sim_001; do
    if docker ps --format "{{.Names}}" | grep -q "^$container$"; then
        echo "  📡 $container network config:"
        docker exec $container cat /proc/sys/net/core/rmem_max 2>/dev/null | xargs -I {} echo "    rmem_max: {}" || echo "    ❌ rmem_max não disponível"
        docker exec $container cat /proc/sys/net/core/wmem_max 2>/dev/null | xargs -I {} echo "    wmem_max: {}" || echo "    ❌ wmem_max não disponível"
    fi
done

echo ""
echo "📊 4. SIMULATOR CONFIG ANALYSIS:"
echo "---------------------------------"
if docker ps --format "{{.Names}}" | grep -q "^mn.sim_001$"; then
    echo "🔹 Simulator Settings:"
    docker exec mn.sim_001 grep -E "(HEARTBEAT|MQTT)" /iot_simulator/iot_simulator/settings.py 2>/dev/null || echo "  ❌ Simulator config não encontrada"
    
    echo "🔹 Active Processes:"
    docker exec mn.sim_001 ps aux | grep -E "(send_telemetry|python)" | wc -l | xargs -I {} echo "  📱 Processos ativos: {}" 2>/dev/null || echo "  ❌ Process count não disponível"
fi

echo ""
echo "🎯 OPTIMIZATION RECOMMENDATIONS:"
echo "================================="

# Análise automática e recomendações
echo "🔧 Baseado na configuração atual:"

if docker ps --format "{{.Names}}" | grep -q "^mn.tb$"; then
    RPC_TIMEOUT=$(docker exec mn.tb grep "CLIENT_SIDE_RPC_TIMEOUT:" /usr/share/thingsboard/conf/thingsboard.yml 2>/dev/null | awk '{print $2}')
    HTTP_TIMEOUT=$(docker exec mn.tb grep "HTTP_REQUEST_TIMEOUT_MS:" /usr/share/thingsboard/conf/thingsboard.yml 2>/dev/null | awk '{print $2}')
    
    if [ "$RPC_TIMEOUT" ] && [ "$RPC_TIMEOUT" -gt 500 ]; then
        echo "  📉 CLIENT_SIDE_RPC_TIMEOUT ($RPC_TIMEOUT ms) pode ser reduzido para 200-300ms"
    fi
    
    if [ "$HTTP_TIMEOUT" ] && [ "$HTTP_TIMEOUT" -gt 1000 ]; then
        echo "  📉 HTTP_REQUEST_TIMEOUT_MS ($HTTP_TIMEOUT ms) pode ser reduzido para 1000ms ou menos"
    fi
fi

echo "  ⚡ Sugestões adicionais:"
echo "    • Aumentar JAVA_OPTS: -Xmx16g -Xms12g"
echo "    • Reduzir SQL_TS_BATCH_MAX_DELAY_MS para 5ms"
echo "    • Aumentar TB_QUEUE_*_THREAD_POOL_SIZE para 64"
echo "    • Configurar TCP_NODELAY=true nos simuladores"
echo "    • Reduzir HEARTBEAT_INTERVAL para 2s"

echo ""
echo "============================================="
echo "Análise concluída: $(date)"