#!/bin/bash

# Monitor em tempo real para ODTE de 30 minutos
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

CURRENT_TEST="test_20251002T110318Z_urllc"
START_TIME="11:03"

while true; do
    clear
    echo -e "${BLUE}🚀 MONITOR ODTE - 30 MINUTOS${NC}"
    echo -e "${BLUE}==============================${NC}"
    echo -e "Teste: ${GREEN}$CURRENT_TEST${NC}"
    echo -e "Início: ${GREEN}$START_TIME UTC${NC}"
    echo -e "Duração: ${GREEN}1800s (30 min)${NC}"
    echo ""
    
    # Tempo atual
    CURRENT_TIME=$(date '+%H:%M')
    echo -e "${YELLOW}⏰ Tempo atual:${NC} $CURRENT_TIME UTC"
    
    # Progresso estimado
    START_SECONDS=$(echo "$START_TIME" | awk -F: '{print ($1 * 3600) + ($2 * 60)}')
    CURRENT_SECONDS=$(date '+%H' | awk '{print $1 * 3600}')
    CURRENT_SECONDS=$((CURRENT_SECONDS + $(date '+%M' | awk '{print $1 * 60}')))
    
    if [ $CURRENT_SECONDS -ge $START_SECONDS ]; then
        ELAPSED=$((CURRENT_SECONDS - START_SECONDS))
        PROGRESS=$((ELAPSED * 100 / 1800))
        echo -e "${YELLOW}⏱️  Tempo decorrido:${NC} ${ELAPSED}s"
        echo -e "${YELLOW}📊 Progresso:${NC} ${PROGRESS}% (${ELAPSED}/1800s)"
        
        # Barra de progresso
        BARS=$((PROGRESS / 2))
        printf "${YELLOW}▶️  ["
        for i in $(seq 1 $BARS); do printf "█"; done
        for i in $(seq $((BARS + 1)) 50); do printf "░"; done
        printf "] ${PROGRESS}%%${NC}\n"
    fi
    
    echo ""
    
    # Status do processo
    if pgrep -f "make odte" > /dev/null; then
        echo -e "${GREEN}✅ Processo ODTE ativo${NC}"
    else
        echo -e "❌ Processo ODTE não encontrado"
    fi
    
    # Containers
    CONTAINERS=$(sudo docker ps --filter name=mn. -q 2>/dev/null | wc -l)
    echo -e "${GREEN}📦 Containers ativos: $CONTAINERS${NC}"
    
    # Arquivos no diretório de teste
    if [ -d "/var/condominio-scenario/results/$CURRENT_TEST" ]; then
        FILES=$(ls -1 "/var/condominio-scenario/results/$CURRENT_TEST" 2>/dev/null | wc -l)
        echo -e "${GREEN}📁 Arquivos gerados: $FILES${NC}"
        
        if [ $FILES -gt 0 ]; then
            echo -e "${YELLOW}📋 Últimos arquivos:${NC}"
            ls -lt "/var/condominio-scenario/results/$CURRENT_TEST" | head -3 | sed 's/^/   /'
        fi
    fi
    
    echo ""
    echo -e "${BLUE}Próxima atualização em 10 segundos... (Ctrl+C para parar)${NC}"
    sleep 10
done