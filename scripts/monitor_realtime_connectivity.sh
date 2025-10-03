#!/bin/bash

# Script para mostrar conectividade em tempo real durante teste ODTE
# Pode ser chamado durante o teste para diagnosticar problemas

echo "📊 CONECTIVIDADE EM TEMPO REAL - $(date)"
echo "========================================"

# 1. Status dos simuladores
echo "1. 📱 STATUS DOS SIMULADORES:"
ACTIVE_SIMS=0
for sim in mn.sim_001 mn.sim_002 mn.sim_003 mn.sim_004 mn.sim_005; do
    if docker ps --format '{{.Names}}' | grep -q "^$sim$"; then
        TELEMETRY_PROCS=$(docker exec $sim ps aux | grep "send_telemetry" | grep -v grep | wc -l 2>/dev/null || echo "0")
        if [ "$TELEMETRY_PROCS" -gt "0" ]; then
            echo "   ✅ $sim: ATIVO (send_telemetry rodando)"
            ACTIVE_SIMS=$((ACTIVE_SIMS + 1))
        else
            echo "   ❌ $sim: INATIVO (send_telemetry parado)"
        fi
    else
        echo "   🔴 $sim: CONTAINER PARADO"
    fi
done

echo "   📊 Simuladores ativos: $ACTIVE_SIMS/5"

# 2. Status do middleware
echo ""
echo "2. 🔄 STATUS DO MIDDLEWARE:"
if docker ps --format '{{.Names}}' | grep -q "mn.middts"; then
    UPDATE_PROCS=$(docker exec mn.middts ps aux | grep "update_causal_property" | grep -v grep | wc -l 2>/dev/null || echo "0")
    if [ "$UPDATE_PROCS" -gt "0" ]; then
        echo "   ✅ MIDDLEWARE: ATIVO (update_causal_property rodando)"
        
        # Verificar se está usando filtro
        FILTER_ACTIVE=$(docker exec mn.middts ps aux | grep "update_causal_property.*--thingsboard-ids" | grep -v grep | wc -l 2>/dev/null || echo "0")
        if [ "$FILTER_ACTIVE" -gt "0" ]; then
            echo "   🎯 FILTRO INTELIGENTE: ATIVO"
            
            # Contar quantos IDs estão sendo processados
            FILTERED_COUNT=$(docker exec mn.middts ps aux | grep "update_causal_property.*--thingsboard-ids" | grep -v grep | tr ' ' '\n' | grep -E '^[a-f0-9]{8}-' | wc -l 2>/dev/null || echo "0")
            echo "   📊 Dispositivos filtrados: $FILTERED_COUNT"
        else
            echo "   ⚠️ FILTRO: NÃO ATIVO (processando todos os dispositivos)"
        fi
    else
        echo "   ❌ MIDDLEWARE: INATIVO (update_causal_property parado)"
    fi
else
    echo "   🔴 MIDDLEWARE: CONTAINER PARADO"
fi

# 3. Conectividade de rede
echo ""
echo "3. 🌐 CONECTIVIDADE DE REDE:"
if docker ps --format '{{.Names}}' | grep -q "mn.tb"; then
    echo "   ✅ ThingsBoard: ONLINE"
    
    # Testar conectividade dos simuladores para o ThingsBoard
    CONNECTED_SIMS=0
    for sim in mn.sim_001 mn.sim_002 mn.sim_003 mn.sim_004 mn.sim_005; do
        if docker ps --format '{{.Names}}' | grep -q "^$sim$"; then
            PING_RESULT=$(docker exec $sim ping -c 1 -W 1 10.0.0.11 2>/dev/null | grep "1 received" | wc -l || echo "0")
            if [ "$PING_RESULT" -gt "0" ]; then
                CONNECTED_SIMS=$((CONNECTED_SIMS + 1))
            fi
        fi
    done
    echo "   📡 Simuladores conectados: $CONNECTED_SIMS/5"
else
    echo "   🔴 ThingsBoard: OFFLINE"
fi

# 4. Estatísticas de dados em tempo real (últimos 30 segundos)
echo ""
echo "4. 📈 ATIVIDADE RECENTE (últimos 30s):"
if docker ps --format '{{.Names}}' | grep -q "mn.middts"; then
    # Contar linhas recentes nos logs do middleware
    RECENT_ACTIVITY=$(docker exec mn.middts bash -c "
        if [ -f /middleware-dt/update_causal_property_contextual.out ]; then
            tail -100 /middleware-dt/update_causal_property_contextual.out | grep \"\$(date -d '30 seconds ago' '+%Y-%m-%d')\" | wc -l
        else
            echo '0'
        fi
    " 2>/dev/null || echo "0")
    
    echo "   📊 Atividade do middleware: $RECENT_ACTIVITY eventos/30s"
    
    # Mostrar últimas 3 linhas de atividade
    echo "   📋 Últimas atividades:"
    docker exec mn.middts bash -c "
        if [ -f /middleware-dt/update_causal_property_contextual.out ]; then
            tail -3 /middleware-dt/update_causal_property_contextual.out | sed 's/^/       /'
        else
            echo '       Nenhum log encontrado'
        fi
    " 2>/dev/null || echo "       Erro ao acessar logs"
fi

# 5. Diagnóstico rápido
echo ""
echo "5. 🔍 DIAGNÓSTICO RÁPIDO:"
HEALTH_SCORE=0

if [ "$ACTIVE_SIMS" -eq "5" ]; then
    echo "   ✅ Simuladores: OK"
    HEALTH_SCORE=$((HEALTH_SCORE + 25))
else
    echo "   ❌ Simuladores: $ACTIVE_SIMS/5 ativos"
fi

if [ "$UPDATE_PROCS" -gt "0" ]; then
    echo "   ✅ Middleware: OK"
    HEALTH_SCORE=$((HEALTH_SCORE + 25))
else
    echo "   ❌ Middleware: Inativo"
fi

if [ "$CONNECTED_SIMS" -eq "5" ]; then
    echo "   ✅ Conectividade: OK"
    HEALTH_SCORE=$((HEALTH_SCORE + 25))
else
    echo "   ❌ Conectividade: $CONNECTED_SIMS/5 conectados"
fi

if [ "$FILTER_ACTIVE" -gt "0" ]; then
    echo "   ✅ Filtro: OK"
    HEALTH_SCORE=$((HEALTH_SCORE + 25))
else
    echo "   ⚠️ Filtro: Não otimizado"
    HEALTH_SCORE=$((HEALTH_SCORE + 10))
fi

echo ""
echo "📊 SCORE GERAL: $HEALTH_SCORE/100"
if [ "$HEALTH_SCORE" -gt "80" ]; then
    echo "🎯 STATUS: EXCELENTE"
elif [ "$HEALTH_SCORE" -gt "60" ]; then
    echo "⚠️ STATUS: BOM (algumas melhorias possíveis)"
else
    echo "❌ STATUS: PROBLEMAS DETECTADOS"
fi

echo ""
echo "========================================"