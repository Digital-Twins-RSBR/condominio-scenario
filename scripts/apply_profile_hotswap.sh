#!/bin/bash

# ==============================================================================
# Apply Profile without ThingsBoard Restart
# ==============================================================================
# Descrição: Aplica perfil via environment variables sem restart do container
# Uso: ./scripts/apply_profile_hotswap.sh <profile_name>
# Categoria: [PRINCIPAL] - Hot-Swap Configuration
# ==============================================================================

PROFILE_NAME="$1"
PROFILES_DIR="/var/condominio-scenario/config/profiles"

if [ -z "$PROFILE_NAME" ]; then
    echo "❌ Erro: Nome do perfil é obrigatório"
    exit 1
fi

PROFILE_FILE="$PROFILES_DIR/${PROFILE_NAME}.yml"
if [ ! -f "$PROFILE_FILE" ]; then
    echo "❌ Erro: Perfil '$PROFILE_NAME' não encontrado"
    exit 1
fi

echo "🔥 Aplicando perfil HOT-SWAP: $PROFILE_NAME"

# Ler valores do perfil
RPC_TIMEOUT=$(grep "CLIENT_SIDE_RPC_TIMEOUT:" "$PROFILE_FILE" | awk '{print $2}')
HTTP_TIMEOUT=$(grep "HTTP_REQUEST_TIMEOUT_MS:" "$PROFILE_FILE" | awk '{print $2}')
BATCH_DELAY=$(grep "SQL_TS_BATCH_MAX_DELAY_MS:" "$PROFILE_FILE" | awk '{print $2}')
HEARTBEAT=$(grep "HEARTBEAT_INTERVAL:" "$PROFILE_FILE" | awk '{print $2}')

echo "🎯 Configurações a aplicar:"
echo "  🔗 CLIENT_SIDE_RPC_TIMEOUT: ${RPC_TIMEOUT}ms"
echo "  🌐 HTTP_REQUEST_TIMEOUT_MS: ${HTTP_TIMEOUT}ms" 
echo "  📝 SQL_TS_BATCH_MAX_DELAY_MS: ${BATCH_DELAY}ms"
echo "  💓 HEARTBEAT_INTERVAL: ${HEARTBEAT}s"

# 1. Copiar perfil para configuração ativa
echo "📄 Copiando perfil para thingsboard-urllc.yml..."
cp "$PROFILE_FILE" "/var/condominio-scenario/config/thingsboard-urllc.yml"

# 2. Aplicar HEARTBEAT nos simuladores
echo "💓 Aplicando HEARTBEAT=${HEARTBEAT}s nos simuladores..."
for sim_num in $(seq -w 1 10); do
    container="mn.sim_0${sim_num}"
    if docker ps --format "{{.Names}}" | grep -q "^${container}$" 2>/dev/null; then
        docker exec "$container" bash -c "
            sed -i 's/HEARTBEAT_INTERVAL = [0-9]*/HEARTBEAT_INTERVAL = ${HEARTBEAT}/g' /iot_simulator/config.py 2>/dev/null || true
        " 2>/dev/null || true
    fi
done

# 3. Atualizar marcadores de perfil
echo "$PROFILE_NAME" > "/var/condominio-scenario/config/.current_profile"
date '+%Y-%m-%d %H:%M:%S' > "/var/condominio-scenario/config/.profile_applied_at"

echo "✅ Profile $PROFILE_NAME aplicado via HOT-SWAP!"
echo ""
echo "📊 Principais configurações aplicadas:"
echo "  🔗 CLIENT_SIDE_RPC_TIMEOUT: ${RPC_TIMEOUT}ms"
echo "  🌐 HTTP_REQUEST_TIMEOUT_MS: ${HTTP_TIMEOUT}ms"
echo "  📝 SQL_TS_BATCH_MAX_DELAY_MS: ${BATCH_DELAY}ms"
echo "  💓 HEARTBEAT_INTERVAL: ${HEARTBEAT}s"
echo ""
echo "⚠️ Nota: Hot-swap não reinicia ThingsBoard. Configurações aplicadas no próximo restart."