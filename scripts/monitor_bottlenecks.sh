#!/bin/bash
# Script para monitorar gargalos em tempo real durante teste URLLC

echo "🔍 MONITORAMENTO DE GARGALOS URLLC"
echo "=================================="
echo "Timestamp: $(date)"
echo ""

echo "📊 1. THINGSBOARD PERFORMANCE:"
echo "------------------------------"
# CPU e Memória do ThingsBoard
if docker ps --format "{{.Names}}" | grep -q "^mn.tb$"; then
    echo "🔹 ThingsBoard CPU/Memory:"
    docker stats mn.tb --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
    
    echo "🔹 ThingsBoard Heap Usage:"
    docker exec mn.tb jstat -gc $(docker exec mn.tb pgrep java) 2>/dev/null | tail -1 || echo "  ❌ JVM stats não disponíveis"
    
    echo "🔹 ThingsBoard Connection Pool:"
    docker exec mn.tb grep -E "(pool|connection)" /var/log/thingsboard/thingsboard.log | tail -3 2>/dev/null || echo "  ⚠️ Log não disponível"
fi

echo ""
echo "📊 2. POSTGRES PERFORMANCE:"
echo "----------------------------"
if docker ps --format "{{.Names}}" | grep -q "^mn.pg"; then
    PG_CONTAINER=$(docker ps --format "{{.Names}}" | grep "^mn.pg" | head -1)
    echo "🔹 PostgreSQL CPU/Memory:"
    docker stats $PG_CONTAINER --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
    
    echo "🔹 Active Connections:"
    docker exec $PG_CONTAINER psql -U thingsboard -d thingsboard -c "SELECT count(*) as active_connections FROM pg_stat_activity;" 2>/dev/null || echo "  ❌ Conexões não disponíveis"
    
    echo "🔹 Query Performance:"
    docker exec $PG_CONTAINER psql -U thingsboard -d thingsboard -c "SELECT query, mean_exec_time, calls FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 3;" 2>/dev/null || echo "  ⚠️ pg_stat_statements não disponível"
fi

echo ""
echo "📊 3. MIDDLEWARE PERFORMANCE:"
echo "-----------------------------"
if docker ps --format "{{.Names}}" | grep -q "^mn.middts$"; then
    echo "🔹 Middleware CPU/Memory:"
    docker stats mn.middts --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
    
    echo "🔹 Django Process Status:"
    docker exec mn.middts ps aux | grep -E "(python|django)" | head -3 2>/dev/null || echo "  ❌ Processos não encontrados"
    
    echo "🔹 Redis Status:"
    docker exec mn.middts redis-cli ping 2>/dev/null || echo "  ❌ Redis não disponível"
fi

echo ""
echo "📊 4. NETWORK PERFORMANCE:"
echo "--------------------------"
echo "🔹 Network Interface Stats:"
# Estatísticas de rede dos containers principais
for container in mn.tb mn.middts mn.sim_001; do
    if docker ps --format "{{.Names}}" | grep -q "^$container$"; then
        echo "  📡 $container:"
        docker exec $container cat /proc/net/dev | grep eth0 | awk '{printf "    RX: %s packets, TX: %s packets\n", $3, $11}' 2>/dev/null || echo "    ❌ Stats não disponíveis"
    fi
done

echo ""
echo "📊 5. SIMULATORS STATUS:"
echo "------------------------"
echo "🔹 Active Simulators:"
ACTIVE_SIMS=$(docker ps --format "{{.Names}}" | grep "^mn.sim_" | wc -l)
echo "  📱 Simuladores ativos: $ACTIVE_SIMS/10"

if [ $ACTIVE_SIMS -gt 0 ]; then
    echo "🔹 First Simulator Performance:"
    docker stats mn.sim_001 --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null || echo "  ❌ Stats não disponíveis"
fi

echo ""
echo "📊 6. SYSTEM RESOURCES:"
echo "-----------------------"
echo "🔹 Host System:"
echo "  💾 RAM: $(free -h | grep Mem | awk '{printf "%s/%s (%.1f%%)", $3, $2, ($3/$2)*100}')"
echo "  🔧 CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)% usage"
echo "  💿 Disk IO: $(iostat -d 1 1 | tail -n +4 | awk 'NR==1{printf "Read: %.1f MB/s, Write: %.1f MB/s", $3, $4}' 2>/dev/null || echo "iostat não disponível")"

echo ""
echo "🔍 GARGALOS IDENTIFICADOS:"
echo "=========================="

# Análise automática de gargalos
if docker ps --format "{{.Names}}" | grep -q "^mn.tb$"; then
    TB_CPU=$(docker stats mn.tb --no-stream --format "{{.CPUPerc}}" | sed 's/%//')
    TB_MEM=$(docker stats mn.tb --no-stream --format "{{.MemUsage}}" | cut -d'/' -f1 | sed 's/[^0-9.]//g')
    
    if (( $(echo "$TB_CPU > 80" | bc -l) )); then
        echo "🚨 ThingsBoard: CPU alto ($TB_CPU%)"
    fi
fi

if docker ps --format "{{.Names}}" | grep -q "^mn.pg"; then
    PG_CONTAINER=$(docker ps --format "{{.Names}}" | grep "^mn.pg" | head -1)
    PG_CPU=$(docker stats $PG_CONTAINER --no-stream --format "{{.CPUPerc}}" | sed 's/%//')
    
    if (( $(echo "$PG_CPU > 70" | bc -l) )); then
        echo "🚨 PostgreSQL: CPU alto ($PG_CPU%)"
    fi
fi

echo "=================================="
echo "Monitoramento concluído: $(date)"