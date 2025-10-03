#!/bin/bash

# Script final corrigido para extrair ThingsBoard IDs corretos
# Versão que funciona corretamente

echo "🚀 EXTRAÇÃO FINAL CORRETA DOS THINGSBOARD IDs"
echo "============================================="

# 1. Identificar simuladores ativos
ACTIVE_SIMS=$(docker ps --format '{{.Names}}' | grep '^mn.sim_' | wc -l)
echo "1. 📱 SIMULADORES ATIVOS: $ACTIVE_SIMS"

# 2. Extrair IDs únicos para Houses 1-5 usando método mais direto
echo "2. 🔍 EXTRAINDO IDs PARA HOUSES 1-5:"

# Criar arquivo temporário com as linhas das Houses 1-5
TEMP_FILE="/tmp/houses_1_5.txt"
docker exec mn.middts bash -c "grep \"'House [1-5] -\" /middleware-dt/update_causal_property.out" > "$TEMP_FILE"

# Contar linhas encontradas
LINES_COUNT=$(wc -l < "$TEMP_FILE")
echo "   📄 Linhas encontradas: $LINES_COUNT"

# Extrair IDs únicos
UNIQUE_IDS=$(grep -o "[a-f0-9]\{8\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{12\}" "$TEMP_FILE" | sort | uniq | tr '\n' ' ')
UNIQUE_COUNT=$(echo $UNIQUE_IDS | wc -w)

echo "   ✅ ThingsBoard IDs únicos encontrados: $UNIQUE_COUNT"

if [ $UNIQUE_COUNT -gt 0 ]; then
    echo "   🔑 Primeiros 10 IDs:"
    echo $UNIQUE_IDS | tr ' ' '\n' | head -10 | sed 's/^/       /'
    
    echo ""
    echo "3. 📊 ESTATÍSTICAS:"
    echo "   - Simuladores ativos: $ACTIVE_SIMS de 10 total"
    echo "   - Dispositivos esperados: $(($ACTIVE_SIMS * 5))"
    echo "   - Dispositivos encontrados: $UNIQUE_COUNT"
    
    if [ $UNIQUE_COUNT -eq $(($ACTIVE_SIMS * 5)) ]; then
        echo "   🎯 PERFEITO! Quantidade exata"
    else
        echo "   ⚠️ Diferença pode ser normal (logs podem ter mais/menos entradas)"
    fi
    
    echo ""
    echo "4. 🚀 APLICANDO FILTRO FINAL:"
    
    # Parar processo atual
    docker exec mn.middts bash -c "pkill -f 'manage.py update_causal_property' || true; rm -f /tmp/update_causal_property*.pid || true"
    sleep 2
    
    # Aplicar filtro final
    echo "   📤 Executando update_causal_property com $UNIQUE_COUNT dispositivos..."
    
    docker exec -d mn.middts bash -c "
        cd /middleware-dt && 
        nohup python3 manage.py update_causal_property --thingsboard-ids $UNIQUE_IDS > /middleware-dt/update_causal_property_final.out 2>&1 & 
        echo \$! > /tmp/update_causal_property_final.pid
    "
    
    # Verificar se iniciou
    sleep 3
    PROCESS_RUNNING=$(docker exec mn.middts bash -c "ps -ef | grep -v grep | grep 'update_causal_property.*--thingsboard-ids' | wc -l")
    
    if [ "$PROCESS_RUNNING" -gt "0" ]; then
        echo "   ✅ Processo filtrado iniciado com sucesso!"
        
        # Calcular redução de carga
        TOTAL_POSSIBLE=50  # 10 simuladores × 5 dispositivos
        REDUCTION_PERCENT=$(echo "scale=1; (($TOTAL_POSSIBLE - $UNIQUE_COUNT) * 100) / $TOTAL_POSSIBLE" | bc -l)
        
        echo ""
        echo "5. 📊 VERIFICAÇÃO INICIAL DOS LOGS:"
        sleep 5
        docker exec mn.middts tail -10 /middleware-dt/update_causal_property_final.out
        
        echo ""
        echo "✅ FILTRO INTELIGENTE APLICADO COM SUCESSO!"
        echo "==========================================="
        echo "📊 Estatísticas Finais:"
        echo "   - Simuladores ativos: $ACTIVE_SIMS de 10"
        echo "   - Dispositivos processados: $UNIQUE_COUNT"
        echo "   - Redução de carga: ~${REDUCTION_PERCENT}%"
        echo ""
        echo "🔍 Para monitorar em tempo real:"
        echo "   docker exec mn.middts tail -f /middleware-dt/update_causal_property_final.out"
        echo ""
        echo "🚀 TESTE DE VALIDAÇÃO RECOMENDADO:"
        echo "   make odte-monitored DURATION=300"
        echo ""
        echo "📈 EXPECTATIVA DE MELHORIA:"
        echo "   - S2M latência: < 2 segundos (antes: 7+ segundos)"
        echo "   - Conectividade: > 95% (antes: 41.4%)"
        echo "   - CPU middleware: redução significativa"
        
    else
        echo "   ❌ Falha ao iniciar processo filtrado"
        echo "   📋 Verificando logs de erro:"
        docker exec mn.middts tail -10 /middleware-dt/update_causal_property_final.out
    fi
else
    echo "   ❌ Nenhum ThingsBoard ID encontrado"
    echo "   💡 Verifique se os logs estão sendo gerados corretamente"
fi

# Limpar arquivo temporário
rm -f "$TEMP_FILE"