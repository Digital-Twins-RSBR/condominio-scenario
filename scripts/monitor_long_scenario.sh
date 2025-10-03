#!/bin/bash

# Monitor do Cenário Longo ODTE
# ============================

LOG_FILE="/var/condominio-scenario/long_scenario.log"
RESULTS_DIR="/var/condominio-scenario/results"

echo "🔍 MONITOR - CENÁRIO LONGO ODTE"
echo "==============================="
echo "$(date '+%Y-%m-%d %H:%M:%S') - Iniciando monitoramento"
echo ""

# Função para mostrar status dos containers
show_container_status() {
    echo "📦 STATUS DOS CONTAINERS:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -E "(mn\.|NAMES)" | head -10
    echo ""
}

# Função para mostrar últimas linhas do log
show_recent_log() {
    echo "📝 ÚLTIMAS MENSAGENS DO LOG:"
    tail -10 "$LOG_FILE" 2>/dev/null || echo "Log ainda não disponível"
    echo ""
}

# Função para mostrar métricas básicas
show_basic_metrics() {
    echo "📊 MÉTRICAS BÁSICAS:"
    echo "• Tempo decorrido: $(ps -o etime= -p $(pgrep -f run_long_scenario) 2>/dev/null || echo 'N/A')"
    echo "• Processo ativo: $(pgrep -f run_long_scenario >/dev/null && echo '✅ SIM' || echo '❌ NÃO')"
    echo "• Containers ativos: $(docker ps --filter name=mn. -q | wc -l)"
    echo ""
}

# Função para verificar espaço em disco
show_disk_usage() {
    echo "💾 USO DE ESPAÇO:"
    df -h | grep -E "(Filesystem|/var)" | head -2
    echo ""
}

# Função para mostrar últimos resultados
show_recent_results() {
    echo "📈 ÚLTIMOS RESULTADOS:"
    if [ -d "$RESULTS_DIR" ]; then
        ls -lt "$RESULTS_DIR" | head -5
    else
        echo "Diretório de resultados não encontrado"
    fi
    echo ""
}

# Loop principal de monitoramento
while true; do
    clear
    echo "🔍 MONITOR - CENÁRIO LONGO ODTE"
    echo "==============================="
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Atualização automática"
    echo ""
    
    show_basic_metrics
    show_container_status
    show_disk_usage
    show_recent_log
    show_recent_results
    
    echo "Pressione Ctrl+C para parar o monitoramento"
    echo "Próxima atualização em 30 segundos..."
    
    sleep 30
done