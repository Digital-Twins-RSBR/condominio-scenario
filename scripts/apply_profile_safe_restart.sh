#!/bin/bash

# ==============================================================================
# Apply Profile with Safe ThingsBoard Restart
# ==============================================================================
# Descrição: Aplica perfil COM restart seguro e verificação de subida do TB
# Uso: ./scripts/apply_profile_safe_restart.sh <profile_name>
# Categoria: [PRINCIPAL] - Restart Seguro
# 
# Garante que:
# - Configurações são aplicadas via rebuild
# - ThingsBoard sobe corretamente após restart
# - Fallback para configuração anterior se falhar
# - Verificação completa de saúde do container
# ==============================================================================

PROFILE_NAME="$1"
PROFILES_DIR="/var/condominio-scenario/config/profiles"
CONFIG_DIR="/var/condominio-scenario/config"
BACKUP_CONFIG="$CONFIG_DIR/thingsboard-urllc.yml.backup_safe"

# Função para mostrar perfis disponíveis
show_available_profiles() {
    echo "📁 Perfis disponíveis:"
    for profile in "$PROFILES_DIR"/*.yml; do
        if [ -f "$profile" ]; then
            basename "$profile" .yml | sed 's/^/  • /'
        fi
    done
}

# Função para verificar saúde do ThingsBoard
check_thingsboard_health() {
    local retries=0
    local max_retries=60  # 2 minutos
    
    echo "🏥 Verificando saúde do ThingsBoard..."
    
    while [ $retries -lt $max_retries ]; do
        # Verificar se container está rodando
        if ! docker ps --format "{{.Names}}" | grep -q "^mn.tb$"; then
            echo "⚠️ Container ThingsBoard não está rodando (tentativa $((retries+1))/$max_retries)"
            sleep 2
            retries=$((retries + 1))
            continue
        fi
        
        # Verificar se processo Java está ativo
        if ! docker exec mn.tb pgrep -f thingsboard > /dev/null 2>&1; then
            echo "⚠️ Processo ThingsBoard não está ativo (tentativa $((retries+1))/$max_retries)"
            sleep 2
            retries=$((retries + 1))
            continue
        fi
        
        # Verificar se porta 8080 está respondendo
        if docker exec mn.tb netstat -tlnp 2>/dev/null | grep -q ":8080 "; then
            echo "✅ ThingsBoard está saudável e respondendo na porta 8080"
            return 0
        fi
        
        echo "⚠️ ThingsBoard ainda não está respondendo (tentativa $((retries+1))/$max_retries)"
        sleep 2
        retries=$((retries + 1))
    done
    
    echo "❌ ThingsBoard falhou em subir corretamente após $max_retries tentativas"
    return 1
}

# Função para restaurar configuração anterior
restore_previous_config() {
    echo "🔄 Restaurando configuração anterior..."
    if [ -f "$BACKUP_CONFIG" ]; then
        cp "$BACKUP_CONFIG" "$CONFIG_DIR/thingsboard-urllc.yml"
        echo "✅ Configuração anterior restaurada"
    else
        echo "⚠️ Backup anterior não encontrado"
    fi
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

echo "🛡️ Aplicando perfil com RESTART SEGURO: $PROFILE_NAME"

# Ler informações do perfil
PROFILE_DISPLAY_NAME=$(grep "PROFILE_NAME:" "$PROFILE_FILE" | cut -d'"' -f2 || echo "$PROFILE_NAME")
PROFILE_DESCRIPTION=$(grep "PROFILE_DESCRIPTION:" "$PROFILE_FILE" | cut -d'"' -f2 || echo "")
HEARTBEAT_INTERVAL=$(grep "HEARTBEAT_INTERVAL:" "$PROFILE_FILE" | cut -d' ' -f2 || echo "4")
RPC_TIMEOUT=$(grep "CLIENT_SIDE_RPC_TIMEOUT:" "$PROFILE_FILE" | awk '{print $2}')

echo "📋 Perfil: $PROFILE_DISPLAY_NAME"
echo "📝 Descrição: $PROFILE_DESCRIPTION"
echo "🔗 RPC Timeout: ${RPC_TIMEOUT}ms"
echo "💓 HEARTBEAT_INTERVAL: ${HEARTBEAT_INTERVAL}s"
echo ""

# 1. Backup da configuração atual
echo "💾 Fazendo backup da configuração atual..."
if [ -f "$CONFIG_DIR/thingsboard-urllc.yml" ]; then
    cp "$CONFIG_DIR/thingsboard-urllc.yml" "$BACKUP_CONFIG"
    echo "✅ Backup salvo em: $BACKUP_CONFIG"
fi

# 2. Aplicar novo perfil
echo "📄 Aplicando novo perfil..."
cp "$PROFILE_FILE" "$CONFIG_DIR/thingsboard-urllc.yml"

# 3. Rebuild do ThingsBoard
echo "🔨 Rebuilding ThingsBoard com novo perfil..."
cd /var/condominio-scenario
if ! sudo docker build -t tb-node-custom -f dockerfiles/Dockerfile.tb services/ > /dev/null 2>&1; then
    echo "❌ Falha no build do container ThingsBoard"
    restore_previous_config
    exit 1
fi
echo "✅ Build concluído com sucesso"

# 4. Verificar se ThingsBoard está rodando e parar se necessário
if docker ps --format "{{.Names}}" | grep -q "^mn.tb$"; then
    echo "🛑 Parando ThingsBoard atual..."
    docker stop mn.tb > /dev/null 2>&1
    sleep 5
fi

# 5. Restart completo do ThingsBoard (container + serviço)
echo "🚀 Restart completo do ThingsBoard (container + serviço)..."

# Stop container
if docker ps --format "{{.Names}}" | grep -q "^mn.tb$"; then
    echo "� Parando container ThingsBoard..."
    docker stop mn.tb > /dev/null 2>&1
    sleep 3
fi

# Start container
    echo "🔄 Restarting ThingsBoard using service management..."
    sudo docker exec mn.tb service thingsboard restart# 6. Verificar saúde do ThingsBoard
if ! check_thingsboard_health; then
    echo "❌ ThingsBoard falhou em subir corretamente"
    echo "🔄 Tentando restaurar configuração anterior..."
    
    # Restaurar configuração
    restore_previous_config
    
    # Rebuild com configuração anterior
    echo "🔨 Rebuilding com configuração anterior..."
    sudo docker build -t tb-node-custom -f dockerfiles/Dockerfile.tb services/ > /dev/null 2>&1
    
    # Restart com configuração anterior
    docker stop mn.tb > /dev/null 2>&1
    sleep 5
    docker start mn.tb > /dev/null 2>&1
    
    echo "⚠️ Configuração anterior restaurada. Verifique logs do ThingsBoard."
    exit 1
fi

# 7. Aplicar HEARTBEAT nos simuladores
echo "💓 Aplicando HEARTBEAT=${HEARTBEAT_INTERVAL}s nos simuladores..."
for sim_num in $(seq -w 1 10); do
    container="mn.sim_0${sim_num}"
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        docker exec "$container" bash -c "
            sed -i 's/HEARTBEAT_INTERVAL = [0-9]*/HEARTBEAT_INTERVAL = ${HEARTBEAT_INTERVAL}/g' /iot_simulator/config.py 2>/dev/null || true
        " 2>/dev/null || true
    fi
done

# 8. Atualizar marcadores de perfil
echo "$PROFILE_NAME" > "$CONFIG_DIR/.current_profile" 2>/dev/null || sudo bash -c "echo '$PROFILE_NAME' > '$CONFIG_DIR/.current_profile'"
date '+%Y-%m-%d %H:%M:%S' > "$CONFIG_DIR/.profile_applied_at" 2>/dev/null || sudo bash -c "date '+%Y-%m-%d %H:%M:%S' > '$CONFIG_DIR/.profile_applied_at'"

echo ""
echo "🎉 Perfil '$PROFILE_NAME' aplicado com SUCESSO e ThingsBoard verificado!"
echo ""
echo "📊 Configurações aplicadas:"
grep -E "CLIENT_SIDE_RPC_TIMEOUT|HTTP_REQUEST_TIMEOUT_MS|SQL_TS_BATCH_MAX_DELAY_MS" "$PROFILE_FILE" | head -5 | sed 's/^/  • /'
echo ""
echo "🚀 Execute 'make odte-full' para testar com o novo perfil!"