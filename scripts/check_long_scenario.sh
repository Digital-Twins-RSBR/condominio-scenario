#!/bin/bash

# 🔍 Script de monitoramento rápido para cenário longo
# Executa verificações básicas de status

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

clear
echo -e "${BLUE}🔍 MONITOR CENÁRIO LONGO ODTE${NC}"
echo -e "${BLUE}============================${NC}"
echo ""

# 1. Status dos Screens
echo -e "${YELLOW}📺 Screens Ativos:${NC}"
if screen -list 2>/dev/null | grep -E "(topology|scenario)"; then
    echo ""
else
    echo -e "   ${RED}❌ Nenhum screen relacionado encontrado${NC}"
    echo ""
fi

# 2. Status dos Containers
echo -e "${YELLOW}🐳 Containers ODTE:${NC}"
CONTAINERS=$(docker ps --format "{{.Names}}" | grep "mn\." | wc -l)
if [ $CONTAINERS -gt 0 ]; then
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -E "(mn\.|NAMES)"
    echo -e "   ${GREEN}✅ $CONTAINERS containers ativos${NC}"
else
    echo -e "   ${RED}❌ Nenhum container ODTE ativo${NC}"
fi
echo ""

# 3. Último resultado de teste
echo -e "${YELLOW}📊 Últimos Resultados:${NC}"
LATEST_RESULT=$(ls -1t results/ | grep "long_scenario" | head -1 2>/dev/null)
if [ -n "$LATEST_RESULT" ]; then
    echo -e "   📁 Diretório: ${GREEN}results/$LATEST_RESULT${NC}"
    
    if [ -f "results/$LATEST_RESULT/test_info.yaml" ]; then
        echo "   📋 Informações do teste:"
        grep -E "(timestamp|duration_hours|profile|simulators|expected_end)" "results/$LATEST_RESULT/test_info.yaml" | sed 's/^/      /'
    fi
    
    echo ""
    echo -e "   📈 Progresso dos logs:"
    if [ -f "results/$LATEST_RESULT/odte_test.log" ]; then
        SIZE=$(du -h "results/$LATEST_RESULT/odte_test.log" | cut -f1)
        LINES=$(wc -l < "results/$LATEST_RESULT/odte_test.log")
        echo -e "      ODTE log: ${GREEN}$SIZE ($LINES linhas)${NC}"
        
        echo "      Últimas 3 linhas:"
        tail -3 "results/$LATEST_RESULT/odte_test.log" | sed 's/^/         /'
    else
        echo -e "      ${YELLOW}⏳ Log ODTE ainda não criado${NC}"
    fi
    
    if [ -f "results/$LATEST_RESULT/topology.log" ]; then
        SIZE=$(du -h "results/$LATEST_RESULT/topology.log" | cut -f1)
        echo -e "      Topology log: ${GREEN}$SIZE${NC}"
    fi
else
    echo -e "   ${YELLOW}⚠️  Nenhum cenário longo encontrado${NC}"
fi
echo ""

# 4. Status da máquina
echo -e "${YELLOW}💻 Status da Máquina:${NC}"
echo -e "   CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)% uso"
echo -e "   RAM: $(free -h | awk 'NR==2{printf "%.1f%%", $3*100/$2 }')"
echo -e "   Uptime: $(uptime -p)"
echo ""

# 5. Comandos úteis
echo -e "${BLUE}🔧 Comandos Úteis:${NC}"
echo -e "   • Ver topology: ${YELLOW}screen -r topology${NC}"
echo -e "   • Ver scenario: ${YELLOW}screen -r scenario${NC}"
echo -e "   • Listar screens: ${YELLOW}screen -list${NC}"
if [ -n "$LATEST_RESULT" ]; then
    echo -e "   • Monitor completo: ${YELLOW}cd results/$LATEST_RESULT && ./monitor.sh${NC}"
fi
echo ""

# 6. Status geral
if screen -list 2>/dev/null | grep -q "topology" && screen -list 2>/dev/null | grep -q "scenario" && [ $CONTAINERS -gt 0 ]; then
    echo -e "${GREEN}✅ CENÁRIO ATIVO - Tudo funcionando${NC}"
elif screen -list 2>/dev/null | grep -q "topology" && [ $CONTAINERS -gt 0 ]; then
    echo -e "${YELLOW}⏳ TOPOLOGIA ATIVA - Aguardando cenário${NC}"
else
    echo -e "${RED}❌ SISTEMA INATIVO${NC}"
fi

echo ""
echo -e "${BLUE}Atualizado: $(date)${NC}"