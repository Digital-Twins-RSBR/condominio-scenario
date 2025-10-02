#!/bin/bash
# quick_status_check.sh - Verificação rápida do status da topologia

echo "🔍 Quick Status Check - $(date)"
echo "================================================"

# Verificar containers
echo "📦 Containers Status:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep "mn\." | head -6

echo ""

# Verificar se ThingsBoard está respondendo
echo "🌐 ThingsBoard Health Check:"
TB_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://localhost:8080/api/auth/login 2>/dev/null || echo "000")
if [ "$TB_STATUS" != "000" ]; then
    echo "✅ ThingsBoard responding (HTTP $TB_STATUS)"
else
    echo "⏳ ThingsBoard ainda inicializando..."
fi

echo ""

# Verificar se Middleware está respondendo  
echo "🔧 Middleware Health Check:"
MW_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://localhost:8000/health 2>/dev/null || echo "000")
if [ "$MW_STATUS" != "000" ]; then
    echo "✅ Middleware responding (HTTP $MW_STATUS)"
else
    echo "⏳ Middleware ainda inicializando..."
fi

echo ""
echo "💡 Para executar o teste quando estiver pronto:"
echo "   cd /var/condominio-scenario"
echo "   make test"
echo ""