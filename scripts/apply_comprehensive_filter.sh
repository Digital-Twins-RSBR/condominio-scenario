#!/bin/bash

# Script para aplicar filtro mais abrangente baseado em proporção correta
# Versão que considera que 5 simuladores ativos = 50% dos dispositivos

echo "🚀 APLICANDO FILTRO ABRANGENTE PARA MÁXIMA CONECTIVIDADE"
echo "======================================================="

# 1. Calcular proporção correta
ACTIVE_SIMS=$(docker ps --format '{{.Names}}' | grep '^mn.sim_' | wc -l)
TOTAL_SIMS=10
PROPORTION=$(echo "scale=2; $ACTIVE_SIMS / $TOTAL_SIMS" | bc -l)

echo "1. 📊 CÁLCULO DA PROPORÇÃO:"
echo "   - Simuladores ativos: $ACTIVE_SIMS"
echo "   - Simuladores totais: $TOTAL_SIMS"
echo "   - Proporção: $PROPORTION (${ACTIVE_SIMS}0%)"

# 2. Obter todos os IDs únicos
ALL_IDS=$(docker exec mn.middts grep -o "[a-f0-9]\{8\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{12\}" /middleware-dt/update_causal_property.out | sort | uniq | tr '\n' ' ')
TOTAL_IDS=$(echo $ALL_IDS | wc -w)

# 3. Calcular quantos IDs usar (mais generoso)
TARGET_IDS=$(echo "$TOTAL_IDS * $PROPORTION + 5" | bc | cut -d. -f1)  # +5 para ser mais generoso

echo ""
echo "2. 📋 CÁLCULO DE DISPOSITIVOS:"
echo "   - Total de IDs únicos: $TOTAL_IDS"
echo "   - IDs alvo (proporção + margem): $TARGET_IDS"
echo "   - Cobertura: $(echo "scale=1; $TARGET_IDS * 100 / $TOTAL_IDS" | bc -l)%"

# 4. Selecionar IDs (primeiros N + alguns extras para variedade)
SELECTED_IDS=$(echo $ALL_IDS | tr ' ' '\n' | head -$TARGET_IDS | tr '\n' ' ')
SELECTED_COUNT=$(echo $SELECTED_IDS | wc -w)

echo ""
echo "3. 🎯 FILTRO SELECIONADO:"
echo "   - Dispositivos selecionados: $SELECTED_COUNT"
echo "   - Expectativa de conectividade: >80%"

# 5. Aplicar filtro
echo ""
echo "4. 🚀 APLICANDO FILTRO ABRANGENTE:"

# Parar processo atual
docker exec mn.middts bash -c "pkill -f 'manage.py update_causal_property' || true; rm -f /tmp/update_causal_property*.pid || true"
sleep 2

# Aplicar novo filtro
echo "   📤 Executando update_causal_property com $SELECTED_COUNT dispositivos..."

docker exec -d mn.middts bash -c "
    cd /middleware-dt && 
    nohup python3 manage.py update_causal_property --thingsboard-ids $SELECTED_IDS > /middleware-dt/update_causal_property_abrangente.out 2>&1 & 
    echo \$! > /tmp/update_causal_property_abrangente.pid
"

# Verificar se iniciou
sleep 3
PROCESS_RUNNING=$(docker exec mn.middts bash -c "ps -ef | grep -v grep | grep 'update_causal_property.*--thingsboard-ids' | wc -l")

if [ "$PROCESS_RUNNING" -gt "0" ]; then
    echo "   ✅ Processo filtrado iniciado com sucesso!"
    
    # Calcular estatísticas
    REDUCTION_PERCENT=$(echo "scale=1; ($TOTAL_IDS - $SELECTED_COUNT) * 100 / $TOTAL_IDS" | bc -l)
    
    echo ""
    echo "5. 📊 VERIFICAÇÃO INICIAL:"
    sleep 5
    docker exec mn.middts tail -8 /middleware-dt/update_causal_property_abrangente.out
    
    echo ""
    echo "✅ FILTRO ABRANGENTE APLICADO!"
    echo "=============================="
    echo "📊 Nova Configuração:"
    echo "   - Simuladores ativos: $ACTIVE_SIMS de $TOTAL_SIMS"
    echo "   - Dispositivos processados: $SELECTED_COUNT de $TOTAL_IDS"
    echo "   - Redução de carga: ~${REDUCTION_PERCENT}%"
    echo "   - Expectativa de conectividade: >80%"
    echo ""
    echo "🔍 Para monitorar:"
    echo "   docker exec mn.middts tail -f /middleware-dt/update_causal_property_abrangente.out"
    echo ""
    echo "📊 Para verificar conectividade em tempo real:"
    echo "   ./scripts/monitor_realtime_connectivity.sh"
    echo ""
    echo "🚀 PRÓXIMO TESTE:"
    echo "   make odte-full DURATION=300"
    
else
    echo "   ❌ Falha ao iniciar processo filtrado"
    docker exec mn.middts tail -10 /middleware-dt/update_causal_property_abrangente.out
fi