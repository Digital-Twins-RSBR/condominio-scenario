#!/bin/bash

# Script para mostrar configurações ativas no início de cada teste ODTE
# Facilita comparação entre diferentes cenários de teste

echo "🔧 =================================================="
echo "🔧         CONFIGURAÇÕES ATIVAS DO TESTE"
echo "🔧 =================================================="

# 1. Verificar perfil e duração
PROFILE=${PROFILE:-urllc}
DURATION=${DURATION:-1800}
echo "📊 PERFIL: $PROFILE | DURAÇÃO: ${DURATION}s"

# 1.1. Mostrar perfil de configuração ativo
if [ -f "config/.current_profile" ]; then
    CURRENT_CONFIG_PROFILE=$(cat config/.current_profile)
    APPLIED_AT=$(cat config/.profile_applied_at 2>/dev/null || echo "N/A")
    echo "🎯 CONFIG_PROFILE: $CURRENT_CONFIG_PROFILE (aplicado em: $APPLIED_AT)"
fi

# 2. Configurações do ThingsBoard (principais)
echo ""
echo "🏢 THINGSBOARD CONFIGURAÇÕES:"
if docker ps --format "{{.Names}}" | grep -q "mn.tb" 2>/dev/null; then
    if sudo docker exec mn.tb test -f /usr/share/thingsboard/conf/thingsboard.yml 2>/dev/null; then
        # RPC Timeout
        RPC_TIMEOUT=$(sudo docker exec mn.tb grep "CLIENT_SIDE_RPC_TIMEOUT:" /usr/share/thingsboard/conf/thingsboard.yml 2>/dev/null | awk '{print $2}' || echo "N/A")
        echo "   🔗 CLIENT_SIDE_RPC_TIMEOUT: ${RPC_TIMEOUT}ms"
        
        # Batch delays
        SQL_BATCH=$(sudo docker exec mn.tb grep "SQL_TS_BATCH_MAX_DELAY_MS:" /usr/share/thingsboard/conf/thingsboard.yml 2>/dev/null | awk '{print $2}' || echo "N/A")
        SQL_LATEST=$(sudo docker exec mn.tb grep "SQL_TS_LATEST_BATCH_MAX_DELAY_MS:" /usr/share/thingsboard/conf/thingsboard.yml 2>/dev/null | awk '{print $2}' || echo "N/A")
        echo "   📝 SQL_TS_BATCH_MAX_DELAY_MS: ${SQL_BATCH}ms"
        echo "   📝 SQL_TS_LATEST_BATCH_MAX_DELAY_MS: ${SQL_LATEST}ms"
        
        # HTTP timeouts se existirem
        HTTP_TIMEOUT=$(sudo docker exec mn.tb grep "HTTP_REQUEST_TIMEOUT_MS:" /usr/share/thingsboard/conf/thingsboard.yml 2>/dev/null | awk '{print $2}' || echo "N/A")
        if [ "$HTTP_TIMEOUT" != "N/A" ]; then
            echo "   🌐 HTTP_REQUEST_TIMEOUT_MS: ${HTTP_TIMEOUT}ms"
        fi
        
        # JVM Heap
        JVM_HEAP=$(sudo docker exec mn.tb ps aux | grep java | grep -o '\-Xmx[0-9]*[gGmM]' | head -1 | sed 's/-Xmx//' || echo "N/A")
        echo "   💾 JVM_HEAP: ${JVM_HEAP}"
    else
        echo "   ❌ ThingsBoard config não encontrada"
    fi
else
    # Mostrar configuração do arquivo local
    echo "   📝 Usando config local (containernet parado):"
    if [ -f "config/thingsboard-urllc.yml" ]; then
        RPC_TIMEOUT=$(grep "CLIENT_SIDE_RPC_TIMEOUT:" config/thingsboard-urllc.yml | awk '{print $2}' || echo "N/A")
        HTTP_TIMEOUT=$(grep "HTTP_REQUEST_TIMEOUT_MS:" config/thingsboard-urllc.yml | awk '{print $2}' || echo "N/A")
        echo "   🔗 CLIENT_SIDE_RPC_TIMEOUT: ${RPC_TIMEOUT}ms"
        if [ "$HTTP_TIMEOUT" != "N/A" ]; then
            echo "   🌐 HTTP_REQUEST_TIMEOUT_MS: ${HTTP_TIMEOUT}ms"
        fi
    else
        echo "   ❌ Arquivo config/thingsboard-urllc.yml não encontrado"
    fi
fi

# 3. Configurações dos Simuladores
echo ""
echo "🤖 SIMULADORES CONFIGURAÇÕES:"
if docker ps --format "{{.Names}}" | grep -q "mn.sim_001" 2>/dev/null; then
    HEARTBEAT=$(sudo docker exec mn.sim_001 grep -r "HEARTBEAT_INTERVAL" /iot_simulator/ 2>/dev/null | head -1 | grep -o '[0-9]\+' || echo "N/A")
    echo "   💓 HEARTBEAT_INTERVAL: ${HEARTBEAT}s"
    
    # Verificar quantos simuladores estão rodando
    SIM_COUNT=$(docker ps --filter "name=mn.sim_" --format "{{.Names}}" | wc -l)
    echo "   📊 SIMULADORES ATIVOS: ${SIM_COUNT}"
else
    echo "   📦 SIMULADORES: containernet parado (usar valores padrão)"
    echo "   💓 HEARTBEAT_INTERVAL: 4s (padrão)"
    echo "   📊 SIMULADORES: 10 (padrão)"
fi

# 4. Configurações de Rede (TC)
echo ""
echo "🌐 REDE CONFIGURAÇÕES:"
# Verificar TC no primeiro simulador
TC_INFO=$(sudo docker exec mn.sim_001 tc qdisc show dev eth0 2>/dev/null | head -1 || echo "default")
if [[ "$TC_INFO" == *"tbf"* ]]; then
    RATE=$(echo "$TC_INFO" | grep -o 'rate [0-9]*[GMK]*bit' | awk '{print $2}')
    BURST=$(echo "$TC_INFO" | grep -o 'burst [0-9]*[GMK]*b' | awk '{print $2}')
    echo "   🚀 TC_RATE: ${RATE} | BURST: ${BURST}"
else
    echo "   📡 TC: $TC_INFO"
fi

# 5. Middleware configurações
echo ""
echo "🔄 MIDDLEWARE CONFIGURAÇÕES:"
if docker exec mn.middts test -f /middleware-dt/facade/models.py 2>/dev/null; then
    # Verificar se tem RPC timeout customizado
    RPC_CUSTOM=$(sudo docker exec mn.middts grep -n "timeout" /middleware-dt/facade/models.py 2>/dev/null | head -1 || echo "default")
    echo "   ⚡ RPC_CONFIG: ${RPC_CUSTOM}"
else
    echo "   📦 MIDDLEWARE: configuração padrão"
fi

# 6. Timestamp do teste
echo ""
echo "⏰ TIMESTAMP: $(date '+%Y-%m-%d %H:%M:%S')"
echo "🔧 =================================================="
echo ""