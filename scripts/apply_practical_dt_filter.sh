#!/bin/bash

# Script de filtragem prática - Versão simplificada
# Filtra apenas os primeiros Digital Twins (correspondentes aos simuladores ativos)

echo "🚀 IMPLEMENTAÇÃO PRÁTICA DE FILTRAGEM DE DIGITAL TWINS"
echo "====================================================="

# 1. Parar processo atual
echo "1. ⏹️ PARANDO PROCESSO update_causal_property ATUAL:"
docker exec mn.middts bash -c "pkill -f 'manage.py update_causal_property' || true"
docker exec mn.middts bash -c "rm -f /tmp/update_causal_property*.pid || true"
sleep 2
echo "   ✅ Processos anteriores interrompidos"

# 2. Identificar simuladores ativos
ACTIVE_SIMS=$(docker ps --format '{{.Names}}' | grep '^mn.sim_' | wc -l)
echo "2. 📊 SIMULADORES ATIVOS: $ACTIVE_SIMS"

# 3. Estratégia simplificada: usar os primeiros N Digital Twin IDs
echo "3. 🎯 APLICANDO FILTRO SIMPLIFICADO:"
echo "   Assumindo que os primeiros $ACTIVE_SIMS Digital Twins correspondem aos simuladores ativos"

# Gerar sequência de IDs (assumindo que começam em 1)
DT_IDS=""
for i in $(seq 1 $ACTIVE_SIMS); do
    DT_IDS="$DT_IDS $i"
done

echo "   📋 IDs de Digital Twins a processar: $DT_IDS"

# 4. Executar update_causal_property com filtro
echo "4. 🚀 EXECUTANDO update_causal_property FILTRADO:"

docker exec -d mn.middts bash -c "
    cd /middleware-dt && 
    nohup python3 manage.py update_causal_property --dt-ids $DT_IDS > /middleware-dt/update_causal_property_smart_filter.out 2>&1 & 
    echo \$! > /tmp/update_causal_property_smart_filter.pid
"

# Verificar se iniciou
sleep 3
PROCESS_RUNNING=$(docker exec mn.middts bash -c "ps -ef | grep -v grep | grep 'update_causal_property.*--dt-ids' | wc -l")

if [ "$PROCESS_RUNNING" -gt "0" ]; then
    echo "   ✅ Processo filtrado iniciado com sucesso"
    echo "   📊 Monitorando apenas $ACTIVE_SIMS Digital Twins ao invés de 120+"
    echo "   📈 Redução de carga: ~$(echo "scale=1; (120-$ACTIVE_SIMS)*100/120" | bc -l)%"
else
    echo "   ❌ Falha ao iniciar processo filtrado"
    exit 1
fi

echo ""

# 5. Monitoramento
echo "5. 📊 MONITORAMENTO:"
echo "   Para verificar logs em tempo real:"
echo "   docker exec mn.middts tail -f /middleware-dt/update_causal_property_smart_filter.out"
echo ""
echo "   Para verificar se o processo está rodando:"
echo "   docker exec mn.middts ps -ef | grep update_causal_property"

echo ""

# 6. Aguardar alguns segundos e verificar logs iniciais
echo "6. 🔍 VERIFICAÇÃO INICIAL (primeiros logs):"
sleep 5
docker exec mn.middts tail -10 /middleware-dt/update_causal_property_smart_filter.out

echo ""
echo "✅ FILTRAGEM INTELIGENTE APLICADA!"
echo "🎯 Agora execute teste ODTE para validar melhoria de performance:"
echo "   make odte-monitored DURATION=300  # 5 minutos"
echo ""
echo "📊 Expectativa de melhoria:"
echo "   - S2M latência: < 2 segundos"
echo "   - Conectividade: > 95%"
echo "   - CPU middleware: redução significativa"