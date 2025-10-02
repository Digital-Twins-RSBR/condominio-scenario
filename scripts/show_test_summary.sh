#!/bin/bash

# Script para mostrar resumo final compacto do ODTE
# Substitui logs verbosos por informações essenciais agrupadas

REPORTS_DIR="$1"

if [ -z "$REPORTS_DIR" ] || [ ! -d "$REPORTS_DIR" ]; then
    echo "❌ Diretório de relatórios não encontrado: $REPORTS_DIR"
    exit 1
fi

echo ""
echo "📊 =================================================="
echo "📊           RESUMO DO TESTE ODTE"
echo "📊 =================================================="

# 1. Informações básicas do teste
if [ -f "$REPORTS_DIR/latency_analysis_summary.txt" ]; then
    echo "📈 RESULTADOS DE LATÊNCIA:"
    
    # Extrair métricas principais
    S2M_AVG=$(grep "S2M Latência Média:" "$REPORTS_DIR/latency_analysis_summary.txt" | awk '{print $4}' | head -1)
    M2S_AVG=$(grep "M2S Latência Média:" "$REPORTS_DIR/latency_analysis_summary.txt" | awk '{print $4}' | head -1)
    
    S2M_RANGE=$(grep "S2M Range:" "$REPORTS_DIR/latency_analysis_summary.txt" | awk '{print $3 " " $4 " " $5}' | head -1)
    M2S_RANGE=$(grep "M2S Range:" "$REPORTS_DIR/latency_analysis_summary.txt" | awk '{print $3 " " $4 " " $5}' | head -1)
    
    echo "   🔄 S2M (Sensor→Middleware): ${S2M_AVG}ms | Range: ${S2M_RANGE}"
    echo "   🔄 M2S (Middleware→Sensor): ${M2S_AVG}ms | Range: ${M2S_RANGE}"
fi

# 2. ODTE Metrics se disponível
if [ -f "$REPORTS_DIR/odte_summary.txt" ]; then
    echo ""
    echo "⚡ ODTE EFFICIENCY:"
    
    S2M_ODTE=$(grep "S2M ODTE:" "$REPORTS_DIR/odte_summary.txt" | awk '{print $3}' | head -1)
    M2S_ODTE=$(grep "M2S ODTE:" "$REPORTS_DIR/odte_summary.txt" | awk '{print $3}' | head -1)
    
    echo "   📊 S2M ODTE: ${S2M_ODTE} | M2S ODTE: ${M2S_ODTE}"
fi

# 3. Conectividade (se disponível)
if [ -f "$REPORTS_DIR/connectivity_summary.txt" ]; then
    echo ""
    echo "🔗 CONECTIVIDADE:"
    
    S2M_CONN=$(grep "S2M Conectividade:" "$REPORTS_DIR/connectivity_summary.txt" | awk '{print $3}' | head -1)
    M2S_CONN=$(grep "M2S Conectividade:" "$REPORTS_DIR/connectivity_summary.txt" | awk '{print $3}' | head -1)
    
    echo "   📡 S2M: ${S2M_CONN} | M2S: ${M2S_CONN}"
fi

# 4. Status de meta (<200ms)
echo ""
echo "🎯 STATUS DA META (<200ms):"

# Verificar se S2M está abaixo de 200ms
if [ ! -z "$S2M_AVG" ]; then
    S2M_NUM=$(echo "$S2M_AVG" | sed 's/ms//')
    if (( $(echo "$S2M_NUM < 200" | bc -l) )); then
        echo "   ✅ S2M: ATINGIU META (${S2M_AVG})"
    else
        echo "   ❌ S2M: ACIMA DA META (${S2M_AVG})"
    fi
fi

# Verificar se M2S está abaixo de 200ms
if [ ! -z "$M2S_AVG" ]; then
    M2S_NUM=$(echo "$M2S_AVG" | sed 's/ms//')
    if (( $(echo "$M2S_NUM < 200" | bc -l) )); then
        echo "   ✅ M2S: ATINGIU META (${M2S_AVG})"
    else
        echo "   ❌ M2S: ACIMA DA META (${M2S_AVG})"
    fi
fi

# 5. Diretório do teste
TEST_DIR=$(dirname "$REPORTS_DIR")
echo ""
echo "📁 DIRETÓRIO: $(basename "$TEST_DIR")"
echo "📊 =================================================="
echo ""