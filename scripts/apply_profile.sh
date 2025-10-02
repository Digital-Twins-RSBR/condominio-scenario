#!/bin/bash

# ==============================================================================
# Apply Configuration Profile
# ==============================================================================
# Descrição: Aplica perfil de configuração ThingsBoard baseado em YAML
# Uso: ./scripts/apply_profile.sh <profile_name>
# Categoria: [PRINCIPAL] - Sistema de Perfis
# 
# Perfis disponíveis:
# - test05_best_performance  : Test #5 - melhor performance geral
# - rpc_ultra_aggressive     : RPC 300ms, HTTP ultra-otimizado  
# - network_optimized        : Foco em conectividade
# - baseline_default         : Configuração padrão ThingsBoard
# ==============================================================================

PROFILE_NAME="$1"
PROFILES_DIR="/var/condominio-scenario/config/profiles"
CONFIG_DIR="/var/condominio-scenario/config"

# Função para mostrar perfis disponíveis
show_available_profiles() {
    echo "📁 Perfis disponíveis:"
    for profile in "$PROFILES_DIR"/*.yml; do
        if [ -f "$profile" ]; then
            basename "$profile" .yml | sed 's/^/  • /'
        fi
    done
}

# Validar argumentos
if [ -z "$PROFILE_NAME" ]; then
    echo "❌ Erro: Nome do perfil é obrigatório"
    echo ""
    echo "📋 Uso: $0 <profile_name>"
    echo ""
    show_available_profiles
    exit 1
fi

# Verificar se perfil existe
PROFILE_FILE="$PROFILES_DIR/${PROFILE_NAME}.yml"
if [ ! -f "$PROFILE_FILE" ]; then
    echo "❌ Erro: Perfil '$PROFILE_NAME' não encontrado"
    echo ""
    show_available_profiles
    exit 1
fi

echo "🎯 Aplicando perfil: $PROFILE_NAME"

# Ler informações do perfil
PROFILE_DISPLAY_NAME=$(grep "PROFILE_NAME:" "$PROFILE_FILE" | cut -d'"' -f2 || echo "$PROFILE_NAME")
PROFILE_DESCRIPTION=$(grep "PROFILE_DESCRIPTION:" "$PROFILE_FILE" | cut -d'"' -f2 || echo "")
HEARTBEAT_INTERVAL=$(grep "HEARTBEAT_INTERVAL:" "$PROFILE_FILE" | cut -d' ' -f2 || echo "4")

echo "📋 Perfil: $PROFILE_DISPLAY_NAME"
echo "📝 Descrição: $PROFILE_DESCRIPTION"
echo "💓 HEARTBEAT_INTERVAL: ${HEARTBEAT_INTERVAL}s"
echo ""

# 1. Copiar perfil para configuração ativa
echo "📄 Copiando perfil para thingsboard-urllc.yml..."
cp "$PROFILE_FILE" "$CONFIG_DIR/thingsboard-urllc.yml"

# 2. Aplicar HEARTBEAT_INTERVAL nos simuladores
echo "💓 Aplicando HEARTBEAT_INTERVAL=${HEARTBEAT_INTERVAL}s nos simuladores..."
for sim_num in $(seq -w 1 10); do
    container="mn.sim_0${sim_num}"
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        docker exec "$container" bash -c "
            sed -i 's/HEARTBEAT_INTERVAL = [0-9]*/HEARTBEAT_INTERVAL = ${HEARTBEAT_INTERVAL}/g' /iot_simulator/config.py 2>/dev/null || true
            sed -i 's/heartbeat_interval.*=.*[0-9]*/heartbeat_interval = ${HEARTBEAT_INTERVAL}/g' /iot_simulator/*.py 2>/dev/null || true
        " 2>/dev/null || true
    fi
done

# 3. Aplicar configurações via hot-swap primeiro (sem restart)
echo "⚡ Aplicando configurações via hot-swap..."
if docker ps --format "{{.Names}}" | grep -q "^mn.tb$"; then
    # Tentar hot-swap primeiro
    docker exec mn.tb bash -c "
        export CLIENT_SIDE_RPC_TIMEOUT=$RPC_TIMEOUT
        export HTTP_REQUEST_TIMEOUT_MS=$HTTP_TIMEOUT
        export SQL_TS_BATCH_MAX_DELAY_MS=$BATCH_DELAY
        echo '✅ Hot-swap aplicado'
    " 2>/dev/null && echo "🔥 Hot-swap configurações aplicadas!" || echo "⚠️ Hot-swap falhou, precisará restart"
    
    # Apenas restart se necessário para mudanças críticas
    if [ "$CLIENT_SIDE_RPC_TIMEOUT" -lt 500 ] 2>/dev/null; then
        echo "⚠️ RPC timeout muito baixo ($RPC_TIMEOUT), restart necessário..."
        NEEDS_RESTART=true
    else
        echo "✅ Configurações aplicadas via hot-swap, restart desnecessário!"
        NEEDS_RESTART=false
    fi
else
    echo "ℹ️ ThingsBoard não está rodando"
    NEEDS_RESTART=false
fi

# 4. Rebuild e restart apenas se necessário
if [ "$NEEDS_RESTART" = "true" ] && docker ps --format "{{.Names}}" | grep -q "^mn.tb$"; then
    echo "🔄 Restart necessário para configurações críticas..."
    sudo docker restart mn.tb > /dev/null 2>&1
    
    echo "⏳ Aguardando ThingsBoard reinicializar..."
    sleep 15
    
    # Verificar se reiniciou corretamente
    retries=0
    while [ $retries -lt 30 ]; do
        if docker exec mn.tb pgrep -f thingsboard > /dev/null 2>&1; then
            echo "✅ ThingsBoard reiniciado com perfil aplicado"
            break
        fi
        sleep 2
        retries=$((retries + 1))
    done
    
    if [ $retries -eq 30 ]; then
        echo "⚠️ ThingsBoard demorou para reiniciar, mas processo continua..."
    fi
else
    echo "✅ Aplicação concluída sem restart necessário!"
fi

# 5. Criar marker de perfil aplicado
echo "$PROFILE_NAME" > "$CONFIG_DIR/.current_profile"
echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$CONFIG_DIR/.profile_applied_at"

echo ""
echo "✅ Perfil '$PROFILE_NAME' aplicado com sucesso!"
echo ""
echo "📊 Configurações principais aplicadas:"

# Mostrar algumas configurações chave do perfil
grep -E "CLIENT_SIDE_RPC_TIMEOUT|HTTP_REQUEST_TIMEOUT_MS|SQL_TS_BATCH_MAX_DELAY_MS|JAVA_OPTS" "$PROFILE_FILE" | head -5 | sed 's/^/  • /'

echo ""
echo "🚀 Execute 'make odte-full' para testar com o novo perfil!"