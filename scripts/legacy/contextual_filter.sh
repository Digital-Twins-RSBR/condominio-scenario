#!/bin/bash

# Script para correlacionar IDs com Houses usando contexto dos logs
# Método que busca IDs próximos às menções de Houses

echo "🔍 CORRELACIONANDO THINGSBOARD IDs COM HOUSES 1-5"
echo "================================================="

# 1. Verificar simuladores ativos
ACTIVE_SIMS=$(docker ps --format '{{.Names}}' | grep '^mn.sim_' | wc -l)
echo "1. 📱 SIMULADORES ATIVOS: $ACTIVE_SIMS"

# 2. Estratégia: buscar IDs em linhas próximas às Houses 1-5
echo "2. 🔍 EXTRAINDO IDs USANDO CONTEXTO DOS LOGS:"

# Criar arquivo temporário com contexto ampliado
TEMP_FILE="/tmp/houses_context.txt"
docker exec mn.middts bash -c "
    grep -B 3 -A 3 \"'House [1-5] -\" /middleware-dt/update_causal_property.out
" > "$TEMP_FILE"

# Extrair todos os IDs do contexto
CONTEXT_IDS=$(grep -o "[a-f0-9]\{8\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{12\}" "$TEMP_FILE" | sort | uniq | tr '\n' ' ')
CONTEXT_COUNT=$(echo $CONTEXT_IDS | wc -w)

echo "   📄 IDs encontrados no contexto das Houses 1-5: $CONTEXT_COUNT"

if [ $CONTEXT_COUNT -gt 0 ]; then
    echo "   🔑 Primeiros 10 IDs:"
    echo $CONTEXT_IDS | tr ' ' '\n' | head -10 | sed 's/^/       /'
    
    echo ""
    echo "3. 📊 ANÁLISE DOS IDs ENCONTRADOS:"
    echo "   - Simuladores ativos: $ACTIVE_SIMS"
    echo "   - IDs encontrados: $CONTEXT_COUNT"
    echo "   - Expectativa: ~$(($ACTIVE_SIMS * 5)) dispositivos"
    
    # Se temos poucos IDs, usar todos. Se temos muitos, pegar os primeiros 25
    if [ $CONTEXT_COUNT -le 30 ]; then
        FINAL_IDS="$CONTEXT_IDS"
        FINAL_COUNT=$CONTEXT_COUNT
        echo "   ✅ Usando todos os $CONTEXT_COUNT IDs encontrados"
    else
        FINAL_IDS=$(echo $CONTEXT_IDS | tr ' ' '\n' | head -25 | tr '\n' ' ')
        FINAL_COUNT=25
        echo "   📏 Limitando a 25 IDs dos mais relevantes"
    fi
    
    echo ""
    echo "4. 🚀 APLICANDO FILTRO BASEADO NO CONTEXTO:"
    echo "   📊 Processando $FINAL_COUNT dispositivos"
    
    # Parar processo atual
    docker exec mn.middts bash -c "pkill -f 'manage.py update_causal_property' || true; rm -f /tmp/update_causal_property*.pid || true"
    sleep 2
    
    # Aplicar filtro
    echo "   📤 Executando update_causal_property com filtro contextual..."
    
    docker exec -d mn.middts bash -c "
        cd /middleware-dt && 
        nohup python3 manage.py update_causal_property --thingsboard-ids $FINAL_IDS > /middleware-dt/update_causal_property_contextual.out 2>&1 & 
        echo \$! > /tmp/update_causal_property_contextual.pid
    "
    
    # Verificar se iniciou
    sleep 3
    PROCESS_RUNNING=$(docker exec mn.middts bash -c "ps -ef | grep -v grep | grep 'update_causal_property.*--thingsboard-ids' | wc -l")
    
    if [ "$PROCESS_RUNNING" -gt "0" ]; then
        echo "   ✅ Processo filtrado iniciado com sucesso!"
        
        # Calcular estatísticas
        TOTAL_POSSIBLE=50  # 10 simuladores × 5 dispositivos
        REDUCTION_PERCENT=$(echo "scale=1; (($TOTAL_POSSIBLE - $FINAL_COUNT) * 100) / $TOTAL_POSSIBLE" | bc -l)
        
        echo ""
        echo "5. 📊 VERIFICAÇÃO INICIAL:"
        sleep 5
        docker exec mn.middts tail -10 /middleware-dt/update_causal_property_contextual.out
        
        echo ""
        echo "✅ FILTRO CONTEXTUAL APLICADO!"
        echo "=============================="
        echo "📊 Estatísticas:"
        echo "   - Simuladores ativos: $ACTIVE_SIMS de 10"
        echo "   - Dispositivos processados: $FINAL_COUNT"
        echo "   - Redução de carga: ~${REDUCTION_PERCENT}%"
        echo ""
        echo "🔍 Para monitorar:"
        echo "   docker exec mn.middts tail -f /middleware-dt/update_causal_property_contextual.out"
        echo ""
        echo "🚀 AGORA EXECUTE O TESTE DE VALIDAÇÃO:"
        echo "   make odte-monitored DURATION=300"
        echo ""
        echo "📈 EXPECTATIVA:"
        echo "   - S2M latência: < 2s (antes: 7+s)"
        echo "   - Conectividade: > 95% (antes: 41.4%)"
        
    else
        echo "   ❌ Falha ao iniciar processo filtrado"
        docker exec mn.middts tail -10 /middleware-dt/update_causal_property_contextual.out
    fi
else
    echo "   ❌ Nenhum ID encontrado no contexto"
fi

# Limpar
rm -f "$TEMP_FILE"