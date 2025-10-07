#!/bin/bash

# Script para identificar TODOS os dispositivos dos simuladores ativos
# Versão corrigida que considera múltiplos dispositivos por simulador

echo "🔍 IDENTIFICANDO TODOS OS DISPOSITIVOS DOS SIMULADORES ATIVOS"
echo "============================================================"

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

echo "   📋 Números ativos: $ACTIVE_SIM_NUMBERS"

# 2. Analisar logs para identificar dispositivos por simulador
echo ""
echo "2. 🔍 ANALISANDO DISPOSITIVOS POR SIMULADOR NOS LOGS:"

# Extrair linhas que mostram dispositivos sendo processados
echo "   Buscando padrões 'House X' nos logs..."
docker exec mn.middts grep "House [0-9]" /middleware-dt/update_causal_property.out | head -20

echo ""
echo "3. 🎯 IDENTIFICANDO THINGSBOARD IDs DOS SIMULADORES ATIVOS:"

# Estratégia: buscar todas as linhas que mencionam "House [números dos sims ativos]"
RELEVANT_TB_IDS=""
TOTAL_DEVICES_FOUND=0

for sim_num in $ACTIVE_SIM_NUMBERS; do
    echo "   📱 Simulador $sim_num (House $sim_num):"
    
    # Buscar dispositivos do simulador nos logs
    HOUSE_LINES=$(docker exec mn.middts grep "House $sim_num" /middleware-dt/update_causal_property.out | head -20)
    
    if [ -n "$HOUSE_LINES" ]; then
        # Extrair ThingsBoard IDs das linhas que mencionam esta House
        HOUSE_TB_IDS=$(echo "$HOUSE_LINES" | grep -o "[a-f0-9]\{8\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{12\}" | sort | uniq)
        
        HOUSE_DEVICE_COUNT=$(echo "$HOUSE_TB_IDS" | wc -l)
        echo "     ✅ Encontrados $HOUSE_DEVICE_COUNT dispositivos"
        
        # Mostrar alguns dispositivos encontrados
        echo "$HOUSE_LINES" | head -3 | while read line; do
            if [[ $line == *"House $sim_num"* ]]; then
                DEVICE_NAME=$(echo "$line" | grep -o "House $sim_num[^']*" | head -1)
                TB_ID=$(echo "$line" | grep -o "[a-f0-9]\{8\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{12\}" | head -1)
                echo "       🏠 $DEVICE_NAME -> $TB_ID"
            fi
        done
        
        # Adicionar à lista de IDs relevantes
        RELEVANT_TB_IDS="$RELEVANT_TB_IDS $HOUSE_TB_IDS"
        TOTAL_DEVICES_FOUND=$((TOTAL_DEVICES_FOUND + HOUSE_DEVICE_COUNT))
    else
        echo "     ❌ Nenhum dispositivo encontrado para House $sim_num"
    fi
done

# Remover duplicatas e contar
UNIQUE_TB_IDS=$(echo $RELEVANT_TB_IDS | tr ' ' '\n' | sort | uniq | tr '\n' ' ')
UNIQUE_COUNT=$(echo $UNIQUE_TB_IDS | wc -w)

echo ""
echo "4. 📊 RESUMO DOS DISPOSITIVOS ENCONTRADOS:"
echo "   ✅ Total de dispositivos únicos: $UNIQUE_COUNT"
echo "   🎯 Expectativa: ~$(($SIM_COUNT * 12)) dispositivos (${SIM_COUNT} sims × 12 devices)"

if [ $UNIQUE_COUNT -gt 0 ]; then
    echo "   📋 Primeiros 10 ThingsBoard IDs:"
    echo "$UNIQUE_TB_IDS" | tr ' ' '\n' | head -10 | sed 's/^/       /'
    
    echo ""
    echo "5. 🚀 APLICANDO FILTRO CORRETO:"
    
    # Parar processo atual
    docker exec mn.middts bash -c "pkill -f 'manage.py update_causal_property' || true"
    docker exec mn.middts bash -c "rm -f /tmp/update_causal_property*.pid || true"
    sleep 2
    
    # Aplicar filtro com TODOS os dispositivos dos simuladores ativos
    echo "   📤 Aplicando filtro para $UNIQUE_COUNT dispositivos..."
    
    docker exec -d mn.middts bash -c "
        cd /middleware-dt && 
        nohup python3 manage.py update_causal_property --thingsboard-ids $UNIQUE_TB_IDS > /middleware-dt/update_causal_property_all_devices.out 2>&1 & 
        echo \$! > /tmp/update_causal_property_all_devices.pid
    "
    
    # Verificar se iniciou
    sleep 3
    PROCESS_RUNNING=$(docker exec mn.middts bash -c "ps -ef | grep -v grep | grep 'update_causal_property.*--thingsboard-ids' | wc -l")
    
    if [ "$PROCESS_RUNNING" -gt "0" ]; then
        echo "   ✅ Processo filtrado iniciado com TODOS os dispositivos!"
        echo "   📊 Processando $UNIQUE_COUNT devices (vs 120+ total)"
        echo "   📈 Redução de carga: ~$(echo "scale=1; (120-$UNIQUE_COUNT)*100/120" | bc -l)%"
        
        echo ""
        echo "6. 📊 VERIFICAÇÃO INICIAL:"
        sleep 5
        docker exec mn.middts tail -10 /middleware-dt/update_causal_property_all_devices.out
        
        echo ""
        echo "✅ FILTRO COMPLETO APLICADO!"
        echo "=============================="
        echo "📊 Estatísticas finais:"
        echo "   - Simuladores ativos: $SIM_COUNT"
        echo "   - Dispositivos processados: $UNIQUE_COUNT"
        echo "   - Dispositivos por simulador: ~$(($UNIQUE_COUNT / $SIM_COUNT))"
        echo "   - Redução de carga: ~$(echo "scale=1; (120-$UNIQUE_COUNT)*100/120" | bc -l)%"
        echo ""
        echo "🔍 Para monitorar:"
        echo "   docker exec mn.middts tail -f /middleware-dt/update_causal_property_all_devices.out"
        echo ""
        echo "🚀 Teste de validação:"
        echo "   make odte-monitored DURATION=300"
        
    else
        echo "   ❌ Falha ao iniciar processo filtrado"
    fi
else
    echo "   ❌ Nenhum dispositivo encontrado para os simuladores ativos"
    echo "   💡 Verifique se os simuladores estão gerando dados nos logs"
fi