#!/bin/bash

# 🚀 Script para executar cenário ODTE completo de 8 horas
# Configuração ótima: reduced_load + 5 simuladores
# Execução em screen sessions para monitoramento contínuo

set -e

# Configurações
DURATION="28800"  # 8 horas em segundos (8 * 60 * 60)
PROFILE="reduced_load"
SIMULATORS=5
TIMESTAMP=$(date +"%Y%m%dT%H%M%SZ")
TEST_NAME="long_scenario_${TIMESTAMP}"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 CENÁRIO LONGO ODTE - 8 HORAS${NC}"
echo -e "${BLUE}=================================${NC}"
echo ""
echo -e "📊 ${YELLOW}Configuração Ótima:${NC}"
echo -e "   • Profile: ${GREEN}${PROFILE}${NC}"
echo -e "   • Simuladores: ${GREEN}${SIMULATORS}${NC}"
echo -e "   • Duração: ${GREEN}8 horas (28800s)${NC}"
echo -e "   • Test ID: ${GREEN}${TEST_NAME}${NC}"
echo ""

# Verificar se já existe alguma topologia rodando
if screen -list | grep -q "topology"; then
    echo -e "${RED}⚠️  Screen 'topology' já existe. Finalizando...${NC}"
    screen -S topology -X quit || true
    sleep 3
fi

if screen -list | grep -q "scenario"; then
    echo -e "${RED}⚠️  Screen 'scenario' já existe. Finalizando...${NC}"
    screen -S scenario -X quit || true
    sleep 3
fi

# Limpar ambiente anterior
echo -e "${YELLOW}🧹 Limpando ambiente anterior...${NC}"
make clean-light >/dev/null 2>&1 || true
sleep 2

# Aplicar configuração ótima
echo -e "${YELLOW}🔧 Aplicando configuração ótima (${PROFILE})...${NC}"
make topo PROFILE=urllc CONFIG_PROFILE=reduced_load || {
    echo -e "${RED}❌ Erro ao aplicar profile${NC}"
    exit 1
}

# Criar diretório de resultados
RESULTS_DIR="results/${TEST_NAME}"
mkdir -p "${RESULTS_DIR}"

echo -e "${YELLOW}📁 Diretório de resultados: ${RESULTS_DIR}${NC}"
echo ""

# Função para verificar se a topologia está pronta
check_topology_ready() {
    local max_attempts=60  # 5 minutos
    local attempt=0
    
    echo -e "${YELLOW}⏳ Verificando se topologia está pronta...${NC}"
    
    while [ $attempt -lt $max_attempts ]; do
        if docker ps | grep -q "mn.tb" && docker ps | grep -q "mn.middts"; then
            echo -e "${GREEN}✅ Topologia pronta!${NC}"
            return 0
        fi
        
        echo -ne "\r   Tentativa $((attempt + 1))/${max_attempts}..."
        sleep 5
        attempt=$((attempt + 1))
    done
    
    echo -e "\n${RED}❌ Timeout esperando topologia ficar pronta${NC}"
    return 1
}

# 1. Iniciar topologia em screen
echo -e "${BLUE}1. 🌐 Iniciando topologia em screen...${NC}"
screen -dmS topology bash -c "
    echo '🌐 Iniciando topologia com ${SIMULATORS} simuladores...'
    cd /var/condominio-scenario
    make topology SIMULATORS=${SIMULATORS} 2>&1 | tee ${RESULTS_DIR}/topology.log
    echo '⚠️  Topologia finalizada - verificar logs'
    exec bash
"

echo -e "${GREEN}   Screen 'topology' iniciado${NC}"
echo -e "   ${YELLOW}Para monitorar: screen -r topology${NC}"
echo ""

# Aguardar topologia ficar pronta
if ! check_topology_ready; then
    echo -e "${RED}❌ Falha ao iniciar topologia${NC}"
    exit 1
fi

# Aguardar mais um pouco para estabilizar
echo -e "${YELLOW}⏳ Aguardando estabilização (30s)...${NC}"
sleep 30

# 2. Executar cenário de teste em screen
echo -e "${BLUE}2. 🧪 Iniciando cenário de teste em screen...${NC}"
screen -dmS scenario bash -c "
    echo '🧪 Iniciando cenário de teste de 8 horas...'
    echo 'Configuração: ${PROFILE} + ${SIMULATORS} simuladores'
    echo 'Duração: ${DURATION}s (8 horas)'
    echo 'Timestamp: ${TIMESTAMP}'
    echo ''
    
    cd /var/condominio-scenario
    
    # Executar teste ODTE monitorado
    echo '📊 Executando teste ODTE...'
    make odte-monitored DURATION=${DURATION} 2>&1 | tee ${RESULTS_DIR}/odte_test.log
    
    echo ''
    echo '✅ Cenário de 8 horas finalizado!'
    echo 'Resultados em: ${RESULTS_DIR}'
    echo 'Timestamp final: \$(date +\"%Y%m%dT%H%M%SZ\")'
    
    exec bash
"

echo -e "${GREEN}   Screen 'scenario' iniciado${NC}"
echo -e "   ${YELLOW}Para monitorar: screen -r scenario${NC}"
echo ""

# Criar script de monitoramento
cat > "${RESULTS_DIR}/monitor.sh" << 'EOF'
#!/bin/bash
# Script para monitorar o progresso do cenário longo

echo "🔍 MONITORAMENTO CENÁRIO LONGO"
echo "=============================="
echo ""

echo "📊 Status dos Screens:"
screen -list | grep -E "(topology|scenario)" || echo "   Nenhum screen ativo"
echo ""

echo "🐳 Status dos Containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(mn\.|NAMES)" || echo "   Nenhum container ativo"
echo ""

echo "📁 Tamanho dos Logs:"
if [ -f "odte_test.log" ]; then
    echo "   odte_test.log: $(du -h odte_test.log | cut -f1)"
fi
if [ -f "topology.log" ]; then
    echo "   topology.log: $(du -h topology.log | cut -f1)"
fi
echo ""

echo "⏰ Última atividade ODTE:"
if [ -f "odte_test.log" ]; then
    tail -3 odte_test.log
else
    echo "   Log ainda não disponível"
fi
EOF

chmod +x "${RESULTS_DIR}/monitor.sh"

# Salvar informações do teste
cat > "${RESULTS_DIR}/test_info.yaml" << EOF
test_name: ${TEST_NAME}
timestamp: ${TIMESTAMP}
duration_seconds: ${DURATION}
duration_hours: 8
profile: ${PROFILE}
simulators: ${SIMULATORS}
results_dir: ${RESULTS_DIR}
expected_end: $(date -d "+8 hours" +"%Y-%m-%d %H:%M:%S")
commands:
  monitor_topology: "screen -r topology"
  monitor_scenario: "screen -r scenario"
  check_progress: "cd ${RESULTS_DIR} && ./monitor.sh"
EOF

echo -e "${GREEN}✅ CENÁRIO LONGO INICIADO COM SUCESSO!${NC}"
echo ""
echo -e "${BLUE}📋 INFORMAÇÕES DO TESTE:${NC}"
echo -e "   • Test ID: ${GREEN}${TEST_NAME}${NC}"
echo -e "   • Início: ${GREEN}$(date)${NC}"
echo -e "   • Fim previsto: ${GREEN}$(date -d "+8 hours")${NC}"
echo -e "   • Resultados: ${GREEN}${RESULTS_DIR}${NC}"
echo ""
echo -e "${BLUE}🔧 COMANDOS ÚTEIS:${NC}"
echo -e "   • Monitorar topologia: ${YELLOW}screen -r topology${NC}"
echo -e "   • Monitorar cenário: ${YELLOW}screen -r scenario${NC}"
echo -e "   • Ver progresso: ${YELLOW}cd ${RESULTS_DIR} && ./monitor.sh${NC}"
echo -e "   • Listar screens: ${YELLOW}screen -list${NC}"
echo ""
echo -e "${BLUE}📊 MONITORAMENTO CONTÍNUO:${NC}"
echo -e "   Execute a cada hora: ${YELLOW}cd ${RESULTS_DIR} && ./monitor.sh${NC}"
echo ""
echo -e "${GREEN}🚀 Cenário de 8 horas em execução!${NC}"
echo -e "${YELLOW}⚠️  Não desligue o sistema durante o teste${NC}"