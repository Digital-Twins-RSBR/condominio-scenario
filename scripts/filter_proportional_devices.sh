#!/bin/bash

# Script melhorado para capturar TODOS os dispositivos dos simuladores ativos
# Versão que funciona corretamente com análise dos logs

echo "🔍 CAPTURANDO TODOS OS DISPOSITIVOS DOS SIMULADORES ATIVOS"
echo "=========================================================="

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

# 2. Estratégia melhorada: buscar contexto completo dos dispositivos
echo "2. 🔍 ANALISANDO LOGS PARA MAPEAR DISPOSITIVOS:"

# Criar arquivo temporário com todas as linhas relevantes
TEMP_FILE="/tmp/device_analysis.txt"
docker exec mn.middts bash -c "
    grep -A 2 -B 2 'House [1-5]' /middleware-dt/update_causal_property.out | 
    grep -E '(House [1-5]|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})' 
" > "$TEMP_FILE" 2>/dev/null

echo "   📄 Extraindo IDs dos dispositivos das Houses 1-5..."

# 3. Capturar ThingsBoard IDs das Houses ativas
RELEVANT_TB_IDS=""

echo "3. 🎯 DISPOSITIVOS POR SIMULADOR:"
for sim_num in $ACTIVE_SIM_NUMBERS; do
    echo "   📱 House $sim_num:"
    
    # Buscar linhas que mencionam esta House e extrair IDs próximos
    HOUSE_IDS=$(docker exec mn.middts bash -c "
        grep -A 5 -B 5 'House $sim_num' /middleware-dt/update_causal_property.out | 
        grep -o '[a-f0-9]\{8\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{12\}' | 
        sort | uniq
    " 2>/dev/null)
    
    if [ -n "$HOUSE_IDS" ]; then
        HOUSE_COUNT=$(echo "$HOUSE_IDS" | wc -l)
        echo "     ✅ $HOUSE_COUNT dispositivos encontrados"
        
        # Mostrar alguns IDs
        echo "$HOUSE_IDS" | head -3 | while read id; do
            echo "       🔑 $id"
        done
        
        # Adicionar à lista total
        RELEVANT_TB_IDS="$RELEVANT_TB_IDS $HOUSE_IDS"
    else
        echo "     ❌ Nenhum dispositivo encontrado"
    fi
done

# 4. Abordagem alternativa: pegar proporcionalmente dos IDs totais
echo ""
echo "4. 📊 ABORDAGEM ALTERNATIVA (PROPORCIONAL):"

# Obter todos os IDs únicos dos logs
ALL_TB_IDS=$(docker exec mn.middts grep -o "[a-f0-9]\{8\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{12\}" /middleware-dt/update_causal_property.out | sort | uniq)
TOTAL_IDS=$(echo "$ALL_TB_IDS" | wc -l)

echo "   📊 Total de IDs únicos encontrados: $TOTAL_IDS"
echo "   🎯 Simuladores ativos: $SIM_COUNT de 10 total"

# Calcular quantos IDs devemos pegar (proporcionalmente)
EXPECTED_DEVICES=$(($TOTAL_IDS * $SIM_COUNT / 10))
echo "   📋 IDs esperados para simuladores ativos: ~$EXPECTED_DEVICES"

# Pegar os primeiros N IDs (assumindo que são dos simuladores ativos)
SELECTED_TB_IDS=$(echo "$ALL_TB_IDS" | head -$EXPECTED_DEVICES | tr '\n' ' ')

echo ""
echo "5. 🚀 APLICANDO FILTRO INTELIGENTE:"
echo "   📊 Processando $EXPECTED_DEVICES dispositivos (vs $TOTAL_IDS total)"
echo "   📈 Redução de carga: ~$(echo "scale=1; ($TOTAL_IDS-$EXPECTED_DEVICES)*100/$TOTAL_IDS" | bc -l)%"

# Parar processo atual
docker exec mn.middts bash -c "pkill -f 'manage.py update_causal_property' || true"
docker exec mn.middts bash -c "rm -f /tmp/update_causal_property*.pid || true"
sleep 2

# Aplicar filtro
echo "   📤 Executando update_causal_property com $EXPECTED_DEVICES dispositivos..."

docker exec -d mn.middts bash -c "
    cd /middleware-dt && 
    nohup python3 manage.py update_causal_property --thingsboard-ids $SELECTED_TB_IDS > /middleware-dt/update_causal_property_proportional.out 2>&1 & 
    echo \$! > /tmp/update_causal_property_proportional.pid
"

# Verificar se iniciou
sleep 3
PROCESS_RUNNING=$(docker exec mn.middts bash -c "ps -ef | grep -v grep | grep 'update_causal_property.*--thingsboard-ids' | wc -l")

if [ "$PROCESS_RUNNING" -gt "0" ]; then
    echo "   ✅ Processo filtrado iniciado com sucesso!"
    
    echo ""
    echo "6. 📊 VERIFICAÇÃO INICIAL:"
    sleep 5
    docker exec mn.middts tail -10 /middleware-dt/update_causal_property_proportional.out
    
    echo ""
    echo "✅ FILTRO PROPORCIONAL APLICADO!"
    echo "================================="
    echo "📊 Estatísticas:"
    echo "   - Simuladores ativos: $SIM_COUNT de 10"
    echo "   - Dispositivos processados: $EXPECTED_DEVICES de $TOTAL_IDS"
    echo "   - Redução de carga: ~$(echo "scale=1; ($TOTAL_IDS-$EXPECTED_DEVICES)*100/$TOTAL_IDS" | bc -l)%"
    echo ""
    echo "🔍 Para monitorar:"
    echo "   docker exec mn.middts tail -f /middleware-dt/update_causal_property_proportional.out"
    echo ""
    echo "🚀 Teste de validação:"
    echo "   make odte-monitored DURATION=300"
    
else
    echo "   ❌ Falha ao iniciar processo filtrado"
    docker exec mn.middts tail -10 /middleware-dt/update_causal_property_proportional.out
fi

# Limpar arquivo temporário
rm -f "$TEMP_FILE"