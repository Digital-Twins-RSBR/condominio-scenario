#!/bin/bash

# Script corrigido para mapear dispositivos dos simuladores ativos
# Versão com regex precisa para evitar falsos positivos

echo "🔍 MAPEAMENTO CORRETO DOS DISPOSITIVOS (REGEX PRECISA)"
echo "====================================================="

# 1. Identificar simuladores ativos
ACTIVE_SIMS=$(docker ps --format '{{.Names}}' | grep '^mn.sim_' | sort)
SIM_COUNT=$(echo "$ACTIVE_SIMS" | wc -l)
echo "1. 📱 SIMULADORES ATIVOS: $SIM_COUNT"

# Extrair números dos simuladores ativos
ACTIVE_SIM_NUMBERS=""
for sim in $ACTIVE_SIMS; do
    SIM_NUM=$(echo "$sim" | sed 's/mn\.sim_0*//')
    ACTIVE_SIM_NUMBERS="$ACTIVE_SIM_NUMBERS $SIM_NUM"
    echo "   - $sim (número: $SIM_NUM)"
done

echo ""

# 2. Mapear dispositivos com regex precisa
echo "2. 🎯 MAPEAMENTO PRECISO DOS DISPOSITIVOS:"

ALL_TB_IDS=""
TOTAL_DEVICES_EXPECTED=$(($SIM_COUNT * 5))  # 5 dispositivos por simulador

for sim_num in $ACTIVE_SIM_NUMBERS; do
    echo "   📱 House $sim_num (Simulador $sim_num):"
    
    # Usar regex precisa: 'House X ' com espaço para evitar House 10 quando buscar House 1
    HOUSE_TB_IDS=$(docker exec mn.middts bash -c "
        grep \"'House $sim_num \" /middleware-dt/update_causal_property.out | 
        grep -o '[a-f0-9]\{8\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{12\}' | 
        sort | uniq
    " 2>/dev/null)
    
    if [ -n "$HOUSE_TB_IDS" ]; then
        HOUSE_COUNT=$(echo "$HOUSE_TB_IDS" | wc -l)
        echo "     ✅ $HOUSE_COUNT dispositivos encontrados"
        
        # Mostrar tipos de dispositivos desta casa
        echo "     📋 Tipos de dispositivos:"
        docker exec mn.middts bash -c "
            grep \"'House $sim_num \" /middleware-dt/update_causal_property.out | 
            cut -d\"'\" -f4 | sort | uniq
        " 2>/dev/null | sed 's/^/       - /'
        
        # Adicionar IDs à lista total
        ALL_TB_IDS="$ALL_TB_IDS $HOUSE_TB_IDS"
    else
        echo "     ❌ Nenhum dispositivo encontrado"
    fi
    echo ""
done

# 3. Processar lista final de IDs
UNIQUE_TB_IDS=$(echo $ALL_TB_IDS | tr ' ' '\n' | sort | uniq | tr '\n' ' ')
UNIQUE_COUNT=$(echo $UNIQUE_TB_IDS | wc -w)

echo "3. 📊 RESUMO FINAL:"
echo "   ✅ Simuladores ativos: $SIM_COUNT"
echo "   ✅ Dispositivos esperados: $TOTAL_DEVICES_EXPECTED (${SIM_COUNT} × 5)"
echo "   ✅ Dispositivos encontrados: $UNIQUE_COUNT"

if [ $UNIQUE_COUNT -eq $TOTAL_DEVICES_EXPECTED ]; then
    echo "   🎯 PERFEITO! Quantidade exata encontrada"
elif [ $UNIQUE_COUNT -gt 0 ]; then
    echo "   ⚠️ Discrepância: esperado $TOTAL_DEVICES_EXPECTED, encontrado $UNIQUE_COUNT"
else
    echo "   ❌ Nenhum dispositivo encontrado"
fi

# 4. Aplicar filtro correto
if [ $UNIQUE_COUNT -gt 0 ]; then
    echo ""
    echo "4. 🚀 APLICANDO FILTRO PRECISO:"
    echo "   📊 Processando $UNIQUE_COUNT dispositivos dos simuladores ativos"
    
    # Parar processo atual
    docker exec mn.middts bash -c "pkill -f 'manage.py update_causal_property' || true"
    docker exec mn.middts bash -c "rm -f /tmp/update_causal_property*.pid || true"
    sleep 2
    
    # Aplicar filtro preciso
    echo "   📤 Executando update_causal_property com filtro preciso..."
    
    docker exec -d mn.middts bash -c "
        cd /middleware-dt && 
        nohup python3 manage.py update_causal_property --thingsboard-ids $UNIQUE_TB_IDS > /middleware-dt/update_causal_property_precise.out 2>&1 & 
        echo \$! > /tmp/update_causal_property_precise.pid
    "
    
    # Verificar se iniciou
    sleep 3
    PROCESS_RUNNING=$(docker exec mn.middts bash -c "ps -ef | grep -v grep | grep 'update_causal_property.*--thingsboard-ids' | wc -l")
    
    if [ "$PROCESS_RUNNING" -gt "0" ]; then
        echo "   ✅ Processo filtrado iniciado com sucesso!"
        
        # Calcular estatísticas
        TOTAL_POSSIBLE=$(($SIM_COUNT * 10 * 5))  # 10 simuladores × 5 dispositivos cada
        REDUCTION_PERCENT=$(echo "scale=1; (($TOTAL_POSSIBLE - $UNIQUE_COUNT) * 100) / $TOTAL_POSSIBLE" | bc -l)
        
        echo ""
        echo "5. 📊 VERIFICAÇÃO INICIAL:"
        sleep 5
        docker exec mn.middts tail -10 /middleware-dt/update_causal_property_precise.out
        
        echo ""
        echo "✅ FILTRO PRECISO APLICADO!"
        echo "==========================="
        echo "📊 Estatísticas Corretas:"
        echo "   - Simuladores totais: 10"
        echo "   - Simuladores ativos: $SIM_COUNT"
        echo "   - Dispositivos por simulador: 5"
        echo "   - Dispositivos processados: $UNIQUE_COUNT"
        echo "   - Redução de carga: ~${REDUCTION_PERCENT}%"
        echo ""
        echo "🔍 Para monitorar:"
        echo "   docker exec mn.middts tail -f /middleware-dt/update_causal_property_precise.out"
        echo ""
        echo "🚀 Teste de validação:"
        echo "   make odte-monitored DURATION=300"
        
    else
        echo "   ❌ Falha ao iniciar processo filtrado"
        docker exec mn.middts tail -10 /middleware-dt/update_causal_property_precise.out
    fi
else
    echo ""
    echo "❌ Não foi possível identificar dispositivos dos simuladores ativos"
fi