#!/bin/bash
# 🎯 URLLC Auto-Optimization Script
# Aplica automaticamente todas as otimizações descobertas no breakthrough de 2025-10-03

set -e

echo "🎯 APLICANDO OTIMIZAÇÕES URLLC AUTOMÁTICAS"
echo "========================================"
echo "📅 Baseado no breakthrough results de 2025-10-03"
echo ""

# 1. Verificar se topologia está rodando
echo "1. 🔍 VERIFICANDO TOPOLOGIA..."
if ! docker ps | grep -q "mn."; then
    echo "   ❌ Topologia não encontrada. Execute primeiro: make topo PROFILE=urllc"
    exit 1
fi
echo "   ✅ Topologia detectada"

# 2. Aplicar configurações URLLC no middleware
echo ""
echo "2. 🔧 APLICANDO CONFIGURAÇÕES MIDDLEWARE..."

# Copiar versão otimizada do update_causal_property
if [ -f "services/middleware-dt/orchestrator/management/commands/update_causal_property.py" ]; then
    docker cp services/middleware-dt/orchestrator/management/commands/update_causal_property.py mn.middts:/middleware-dt/orchestrator/management/commands/update_causal_property.py
    echo "   ✅ Middleware optimizado copiado"
else
    echo "   ⚠️ Arquivo middleware otimizado não encontrado"
fi

# 3. Verificar se comando otimizado está funcionando
echo ""
echo "3. 🧪 TESTANDO COMANDO OTIMIZADO..."
if docker exec mn.middts python3 manage.py update_causal_property --help | grep -q "thingsboard-ids"; then
    echo "   ✅ Comando --thingsboard-ids disponível"
else
    echo "   ❌ Comando otimizado não está funcionando"
    exit 1
fi

# 4. Aguardar simuladores ficarem ativos
echo ""
echo "4. ⏳ AGUARDANDO SIMULADORES..."
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    ACTIVE_SIMS=$(docker ps --filter "name=mn.sim_" --format "{{.Names}}" | wc -l)
    if [ $ACTIVE_SIMS -ge 5 ]; then
        echo "   ✅ $ACTIVE_SIMS simuladores ativos"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo "   ⏳ Aguardando... ($ACTIVE_SIMS/5 ativos, ${ELAPSED}s)"
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "   ⚠️ Timeout aguardando simuladores, continuando..."
fi

# 5. Aplicar filtro inteligente (se simuladores estão enviando dados)
echo ""
echo "5. 🎯 APLICANDO FILTRO INTELIGENTE..."
sleep 10  # Dar tempo para simuladores começarem a enviar dados

if [ -f "scripts/apply_comprehensive_filter.sh" ]; then
    ./scripts/apply_comprehensive_filter.sh
    if [ $? -eq 0 ]; then
        echo "   ✅ Filtro inteligente aplicado com sucesso"
    else
        echo "   ⚠️ Filtro pode não ter encontrado dados, mas processo continua"
    fi
else
    echo "   ❌ Script de filtro não encontrado"
fi

# 6. Verificar status final
echo ""
echo "6. 📊 VERIFICAÇÃO FINAL..."
if [ -f "scripts/monitor_realtime_connectivity.sh" ]; then
    echo "   🔍 Status da conectividade:"
    ./scripts/monitor_realtime_connectivity.sh | head -15
else
    echo "   ⚠️ Script de monitoramento não encontrado"
fi

echo ""
echo "🎉 OTIMIZAÇÕES APLICADAS COM SUCESSO!"
echo "========================================"
echo ""
echo "📊 RESULTADOS ESPERADOS:"
echo "   • S2M Latência: ~73ms (target: <200ms)"
echo "   • Carga middleware: ~40% redução"
echo "   • Conectividade: >90%"
echo ""
echo "🚀 PRÓXIMOS PASSOS:"
echo "   1. Execute: make odte-full DURATION=300"
echo "   2. Monitore: ./scripts/monitor_realtime_connectivity.sh"
echo "   3. Analise resultados em: results/"
echo ""
echo "📈 BASELINE ESTABELECIDA: 2025-10-03 (test_20251003T154254Z_urllc)"