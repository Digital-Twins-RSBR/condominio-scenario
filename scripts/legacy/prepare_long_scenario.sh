#!/bin/bash

# 🔍 Script preparatório para cenário longo de 8 horas
# Verifica espaço, configura análise automática e estimativas

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔍 PREPARAÇÃO CENÁRIO LONGO - 8 HORAS${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

# 1. Verificação de espaço em disco
echo -e "${YELLOW}💾 Verificação de Espaço:${NC}"
AVAILABLE_GB=$(df /var | tail -1 | awk '{print int($4/1024/1024)}')
CURRENT_RESULTS_MB=$(du -sm /var/condominio-scenario/results/ | cut -f1)
CURRENT_LOGS_MB=$(du -sm /var/condominio-scenario/deploy/logs/ | cut -f1)

echo -e "   📁 Espaço disponível: ${GREEN}${AVAILABLE_GB} GB${NC}"
echo -e "   📊 Resultados atuais: ${YELLOW}${CURRENT_RESULTS_MB} MB${NC}"
echo -e "   📜 Logs atuais: ${YELLOW}${CURRENT_LOGS_MB} MB${NC}"

# Estimativa de consumo para 8 horas
ESTIMATED_LOG_SIZE_MB=$((8 * 60 * 2))  # ~2MB por hora estimado
ESTIMATED_RESULTS_MB=$((8 * 50))       # ~50MB por hora estimado
TOTAL_ESTIMATED_MB=$((ESTIMATED_LOG_SIZE_MB + ESTIMATED_RESULTS_MB))

echo ""
echo -e "${YELLOW}📈 Estimativas para 8 horas:${NC}"
echo -e "   📜 Logs estimados: ${YELLOW}~${ESTIMATED_LOG_SIZE_MB} MB${NC}"
echo -e "   📊 Resultados estimados: ${YELLOW}~${ESTIMATED_RESULTS_MB} MB${NC}"
echo -e "   📦 Total estimado: ${YELLOW}~${TOTAL_ESTIMATED_MB} MB (~$((TOTAL_ESTIMATED_MB/1024)) GB)${NC}"

# Verificar se temos espaço suficiente
REQUIRED_GB=$((TOTAL_ESTIMATED_MB / 1024 + 2))  # +2GB de margem
if [ $AVAILABLE_GB -lt $REQUIRED_GB ]; then
    echo -e "${RED}❌ ESPAÇO INSUFICIENTE!${NC}"
    echo -e "   Necessário: ~${REQUIRED_GB} GB"
    echo -e "   Disponível: ${AVAILABLE_GB} GB"
    echo ""
    echo -e "${YELLOW}💡 Sugestões:${NC}"
    echo -e "   • Limpar resultados antigos: ${YELLOW}make clean-results${NC}"
    echo -e "   • Limpar logs Docker: ${YELLOW}docker system prune -f${NC}"
    echo -e "   • Verificar: ${YELLOW}du -sh /var/lib/docker/${NC}"
    exit 1
else
    echo -e "${GREEN}✅ Espaço suficiente!${NC}"
fi

echo ""

# 2. Limpeza preventiva
echo -e "${YELLOW}🧹 Limpeza Preventiva:${NC}"
echo -e "   • Removendo resultados > 7 dias..."
find /var/condominio-scenario/results/ -type d -name "test_*" -mtime +7 -exec rm -rf {} + 2>/dev/null || true
echo -e "   • Limpando logs Docker..."
docker system prune -f >/dev/null 2>&1 || true
echo -e "${GREEN}   ✅ Limpeza concluída${NC}"

echo ""

# 3. Configuração de análise automática
TIMESTAMP=$(date +"%Y%m%dT%H%M%SZ")
TEST_NAME="long_scenario_${TIMESTAMP}"
RESULTS_DIR="results/${TEST_NAME}"

echo -e "${YELLOW}📊 Configurando Análise Automática:${NC}"

# Criar script de análise automática
mkdir -p "$RESULTS_DIR"
cat > "${RESULTS_DIR}/auto_analysis.sh" << 'ANALYSIS_EOF'
#!/bin/bash

# 📊 Análise automática de resultados do cenário longo
# Executado automaticamente ao final do teste

set -e

RESULTS_DIR="$(dirname "$0")"
cd "$RESULTS_DIR"

echo "🔍 ANÁLISE AUTOMÁTICA - CENÁRIO 8 HORAS"
echo "======================================="
echo ""

# Informações básicas
if [ -f "test_info.yaml" ]; then
    echo "📋 Informações do Teste:"
    cat test_info.yaml | sed 's/^/   /'
    echo ""
fi

# Análise dos logs ODTE
if [ -f "odte_test.log" ]; then
    echo "📊 Análise ODTE:"
    LOG_SIZE=$(du -h odte_test.log | cut -f1)
    LOG_LINES=$(wc -l < odte_test.log)
    echo "   • Tamanho do log: $LOG_SIZE"
    echo "   • Linhas registradas: $LOG_LINES"
    
    # Extrair métricas principais
    echo ""
    echo "📈 Métricas Principais:"
    
    # S2M médio
    S2M_AVG=$(grep -o "S2M: [0-9.]*ms" odte_test.log | tail -20 | awk -F: '{sum+=$2} END {if(NR>0) print sum/NR "ms"; else print "N/A"}' | sed 's/ms//')
    if [ "$S2M_AVG" != "N/A" ] && [ -n "$S2M_AVG" ]; then
        printf "   • S2M médio (últimas 20): %.1fms\n" "$S2M_AVG"
    fi
    
    # M2S médio  
    M2S_AVG=$(grep -o "M2S: [0-9.]*ms" odte_test.log | tail -20 | awk -F: '{sum+=$2} END {if(NR>0) print sum/NR "ms"; else print "N/A"}' | sed 's/ms//')
    if [ "$M2S_AVG" != "N/A" ] && [ -n "$M2S_AVG" ]; then
        printf "   • M2S médio (últimas 20): %.1fms\n" "$M2S_AVG"
    fi
    
    # CPU médio
    CPU_AVG=$(grep -o "CPU: [0-9.]*%" odte_test.log | tail -20 | awk -F: '{sum+=$2} END {if(NR>0) print sum/NR "%"; else print "N/A"}' | sed 's/%//')
    if [ "$CPU_AVG" != "N/A" ] && [ -n "$CPU_AVG" ]; then
        printf "   • CPU médio (últimas 20): %.1f%%\n" "$CPU_AVG"
    fi
    
    # Throughput médio
    THROUGHPUT_AVG=$(grep -o "Throughput: [0-9.]*" odte_test.log | tail -20 | awk -F: '{sum+=$2} END {if(NR>0) print sum/NR; else print "N/A"}')
    if [ "$THROUGHPUT_AVG" != "N/A" ] && [ -n "$THROUGHPUT_AVG" ]; then
        printf "   • Throughput médio: %.1f msg/s\n" "$THROUGHPUT_AVG"
    fi
    
    echo ""
    echo "⏱️  Timeline do Teste:"
    echo "   • Início: $(head -1 odte_test.log | grep -o '[0-9][0-9]:[0-9][0-9]:[0-9][0-9]' | head -1 || echo 'N/A')"
    echo "   • Fim: $(tail -1 odte_test.log | grep -o '[0-9][0-9]:[0-9][0-9]:[0-9][0-9]' | tail -1 || echo 'N/A')"
    
    # Verificar se teste completou 8 horas
    DURATION_LINES=$(grep -c "DURATION" odte_test.log || echo 0)
    if [ $DURATION_LINES -gt 0 ]; then
        echo "   • Status: ✅ Teste completado"
    else
        echo "   • Status: ⚠️  Verificar se completou"
    fi
    
else
    echo "❌ Log ODTE não encontrado"
fi

echo ""
echo "📁 Arquivos Gerados:"
ls -lh | grep -v "^total" | sed 's/^/   /'

echo ""
echo "🏆 ANÁLISE COMPLETA"
echo "Data: $(date)"
ANALYSIS_EOF

chmod +x "${RESULTS_DIR}/auto_analysis.sh"

# Criar script de análise comparativa
cat > "${RESULTS_DIR}/compare_with_baseline.sh" << 'COMPARE_EOF'
#!/bin/bash

# 📊 Comparação com baseline e configuração ótima
echo "📊 COMPARAÇÃO COM RESULTADOS CONHECIDOS"
echo "======================================"
echo ""

echo "🎯 Configuração Ótima (Baseline):"
echo "   • S2M: 69.4ms"
echo "   • M2S: 184.0ms" 
echo "   • CPU: 330%"
echo "   • Throughput: 62.1 msg/s"
echo "   • ODTE Score: 95.8/100"
echo ""

if [ -f "odte_test.log" ]; then
    echo "📈 Resultados do Teste de 8h:"
    
    # Calcular médias do teste longo
    S2M_LONG=$(grep -o "S2M: [0-9.]*ms" odte_test.log | tail -50 | awk -F: '{sum+=$2} END {if(NR>0) print sum/NR}' | sed 's/ms//')
    M2S_LONG=$(grep -o "M2S: [0-9.]*ms" odte_test.log | tail -50 | awk -F: '{sum+=$2} END {if(NR>0) print sum/NR}' | sed 's/ms//')
    CPU_LONG=$(grep -o "CPU: [0-9.]*%" odte_test.log | tail -50 | awk -F: '{sum+=$2} END {if(NR>0) print sum/NR}' | sed 's/%//')
    THROUGHPUT_LONG=$(grep -o "Throughput: [0-9.]*" odte_test.log | tail -50 | awk -F: '{sum+=$2} END {if(NR>0) print sum/NR}')
    
    if [ -n "$S2M_LONG" ] && [ "$S2M_LONG" != "" ]; then
        printf "   • S2M: %.1fms\n" "$S2M_LONG"
        S2M_DIFF=$(echo "$S2M_LONG - 69.4" | bc -l 2>/dev/null || echo "0")
        printf "     Diferença: %+.1fms\n" "$S2M_DIFF"
    fi
    
    if [ -n "$M2S_LONG" ] && [ "$M2S_LONG" != "" ]; then
        printf "   • M2S: %.1fms\n" "$M2S_LONG"
        M2S_DIFF=$(echo "$M2S_LONG - 184.0" | bc -l 2>/dev/null || echo "0")
        printf "     Diferença: %+.1fms\n" "$M2S_DIFF"
    fi
    
    if [ -n "$CPU_LONG" ] && [ "$CPU_LONG" != "" ]; then
        printf "   • CPU: %.1f%%\n" "$CPU_LONG"
        CPU_DIFF=$(echo "$CPU_LONG - 330" | bc -l 2>/dev/null || echo "0")
        printf "     Diferença: %+.1f%%\n" "$CPU_DIFF"
    fi
    
    if [ -n "$THROUGHPUT_LONG" ] && [ "$THROUGHPUT_LONG" != "" ]; then
        printf "   • Throughput: %.1f msg/s\n" "$THROUGHPUT_LONG"
        THROUGHPUT_DIFF=$(echo "$THROUGHPUT_LONG - 62.1" | bc -l 2>/dev/null || echo "0")
        printf "     Diferença: %+.1f msg/s\n" "$THROUGHPUT_DIFF"
    fi
    
else
    echo "❌ Dados do teste não encontrados"
fi

echo ""
echo "📊 Conclusões:"
echo "   • Teste de longa duração valida estabilidade"
echo "   • Pequenas variações são normais"
echo "   • Valores próximos ao baseline indicam sucesso"
COMPARE_EOF

chmod +x "${RESULTS_DIR}/compare_with_baseline.sh"

echo -e "   📊 Script de análise: ${GREEN}${RESULTS_DIR}/auto_analysis.sh${NC}"
echo -e "   📈 Script comparativo: ${GREEN}${RESULTS_DIR}/compare_with_baseline.sh${NC}"

echo ""

# 4. Resumo final
echo -e "${BLUE}📋 RESUMO DA PREPARAÇÃO:${NC}"
echo -e "   • ✅ Espaço verificado: ${GREEN}${AVAILABLE_GB}GB disponíveis${NC}"
echo -e "   • ✅ Limpeza preventiva executada"
echo -e "   • ✅ Análise automática configurada"
echo -e "   • ✅ Scripts de monitoramento prontos"
echo ""

echo -e "${GREEN}🚀 SISTEMA PRONTO PARA CENÁRIO DE 8 HORAS!${NC}"
echo ""
echo -e "${BLUE}🔧 Próximos Passos:${NC}"
echo -e "   1. Execute: ${YELLOW}./scripts/run_long_scenario.sh${NC}"
echo -e "   2. Monitore: ${YELLOW}./scripts/check_long_scenario.sh${NC}"
echo -e "   3. Ao final: ${YELLOW}cd ${RESULTS_DIR} && ./auto_analysis.sh${NC}"
echo ""
echo -e "${YELLOW}⚠️  Importante: Não desligue o sistema durante o teste de 8 horas!${NC}"