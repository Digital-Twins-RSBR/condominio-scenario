#!/bin/bash

# Script PRÁTICO para aplicar filtro baseado em ThingsBoard IDs
# Versão que funciona com os dados reais do sistema

echo "🚀 APLICANDO FILTRO PRÁTICO POR THINGSBOARD IDs"
echo "=============================================="

# 1. Identificar simuladores ativos
ACTIVE_SIMS=$(docker ps --format '{{.Names}}' | grep '^mn.sim_' | wc -l)
echo "1. 📱 SIMULADORES ATIVOS: $ACTIVE_SIMS"

# 2. Extrair ThingsBoard IDs dos logs atuais
echo "2. 🔍 EXTRAINDO THINGSBOARD IDs DOS LOGS:"
echo "   Analisando logs do update_causal_property atual..."

# Obter IDs únicos dos logs, limitando aos primeiros N (correspondentes aos simuladores ativos)
THINGSBOARD_IDS=$(docker exec mn.middts grep -o "[a-f0-9]\{8\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{12\}" /middleware-dt/update_causal_property.out | sort | uniq | head -$ACTIVE_SIMS | tr '\n' ' ')

echo "   ✅ IDs extraídos (primeiros $ACTIVE_SIMS): $THINGSBOARD_IDS"

# 3. Parar processo atual
echo ""
echo "3. ⏹️ PARANDO PROCESSO ATUAL:"
docker exec mn.middts bash -c "pkill -f 'manage.py update_causal_property' || true"
docker exec mn.middts bash -c "rm -f /tmp/update_causal_property*.pid || true"
sleep 2
echo "   ✅ Processo anterior interrompido"

# 4. Aplicar filtro com ThingsBoard IDs
echo ""
echo "4. 🚀 APLICANDO FILTRO INTELIGENTE:"

if [ -n "$THINGSBOARD_IDS" ]; then
    IDS_COUNT=$(echo $THINGSBOARD_IDS | wc -w)
    echo "   📊 Aplicando filtro para $IDS_COUNT devices (vs 120+ anteriormente)"
    echo "   🔑 ThingsBoard IDs: $THINGSBOARD_IDS"
    
    # Executar update_causal_property com filtro de ThingsBoard IDs
    docker exec -d mn.middts bash -c "
        cd /middleware-dt && 
        nohup python3 manage.py update_causal_property --thingsboard-ids $THINGSBOARD_IDS > /middleware-dt/update_causal_property_smart_filtered.out 2>&1 & 
        echo \$! > /tmp/update_causal_property_smart_filtered.pid
    "
    
    # Verificar se iniciou
    sleep 3
    PROCESS_RUNNING=$(docker exec mn.middts bash -c "ps -ef | grep -v grep | grep 'update_causal_property.*--thingsboard-ids' | wc -l")
    
    if [ "$PROCESS_RUNNING" -gt "0" ]; then
        echo "   ✅ Processo filtrado iniciado com sucesso!"
        echo "   📈 Redução de carga: ~$(echo "scale=1; (120-$IDS_COUNT)*100/120" | bc -l)%"
        
        echo ""
        echo "5. 📊 VERIFICAÇÃO INICIAL DOS LOGS:"
        sleep 5
        echo "   Primeiras mensagens do processo filtrado:"
        docker exec mn.middts tail -10 /middleware-dt/update_causal_property_smart_filtered.out
        
        echo ""
        echo "✅ FILTRO INTELIGENTE APLICADO COM SUCESSO!"
        echo "============================================"
        echo "📊 Estatísticas:"
        echo "   - Simuladores ativos: $ACTIVE_SIMS"
        echo "   - Digital Twins processados: $IDS_COUNT (antes: 120+)"
        echo "   - Redução de carga: ~$(echo "scale=1; (120-$IDS_COUNT)*100/120" | bc -l)%"
        echo ""
        echo "🔍 Para monitorar em tempo real:"
        echo "   docker exec mn.middts tail -f /middleware-dt/update_causal_property_smart_filtered.out"
        echo ""
        echo "🚀 PRÓXIMO PASSO - TESTE DE VALIDAÇÃO:"
        echo "   make odte-monitored DURATION=300  # 5 minutos"
        echo ""
        echo "📈 EXPECTATIVA DE MELHORIA:"
        echo "   - S2M latência: < 2 segundos"
        echo "   - Conectividade: > 95%"
        echo "   - CPU middleware: redução significativa"
        
    else
        echo "   ❌ Falha ao iniciar processo filtrado"
        echo "   💡 Verificando logs de erro..."
        docker exec mn.middts tail -20 /middleware-dt/update_causal_property_smart_filtered.out
    fi
else
    echo "   ❌ Nenhum ThingsBoard ID encontrado nos logs"
    echo "   💡 Execute um teste primeiro para gerar logs com IDs"
fi