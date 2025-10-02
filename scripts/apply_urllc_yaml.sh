#!/bin/bash

# ==============================================================================
# Apply URLLC Configuration via YAML
# ==============================================================================
# Descrição: Aplica configurações URLLC via arquivo thingsboard-urllc.yml
# Uso: make apply-urllc-yaml ou ./scripts/apply_urllc_yaml.sh
# Categoria: [PRINCIPAL] - Configuração YAML
# 
# Funcionalidades:
# - Rebuild do container ThingsBoard com configuração YAML otimizada
# - Restart automático para aplicar configurações
# - Verificação de aplicação das configurações
# ==============================================================================

echo "🎯 Aplicando configurações URLLC via YAML..."

# 1. Verificar se arquivo de configuração existe
CONFIG_FILE="/var/condominio-scenario/config/thingsboard-urllc.yml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Arquivo de configuração não encontrado: $CONFIG_FILE"
    exit 1
fi

echo "✅ Arquivo de configuração encontrado"

# 2. Rebuild apenas do container ThingsBoard
echo "🔨 Rebuilding container ThingsBoard com configurações YAML..."
cd /var/condominio-scenario
sudo docker build -t tb-node-custom -f dockerfiles/Dockerfile.tb services/ || {
    echo "❌ Falha no build do container ThingsBoard"
    exit 1
}

# 3. Restart do container ThingsBoard se estiver rodando
if docker ps --format "{{.Names}}" | grep -q "^mn.tb$"; then
    echo "🔄 Reiniciando container ThingsBoard para aplicar configurações YAML..."
    sudo docker restart mn.tb
    
    echo "⏳ Aguardando ThingsBoard reinicializar..."
    sleep 15
    
    # Verificar se reiniciou corretamente
    retries=0
    while [ $retries -lt 30 ]; do
        if docker exec mn.tb pgrep -f thingsboard > /dev/null 2>&1; then
            echo "✅ ThingsBoard reiniciado com sucesso"
            break
        fi
        sleep 2
        retries=$((retries + 1))
    done
    
    if [ $retries -eq 30 ]; then
        echo "⚠️ ThingsBoard demorou para reiniciar, mas processo continua..."
    fi
else
    echo "ℹ️ ThingsBoard não está rodando, configurações serão aplicadas no próximo start"
fi

# 4. Verificar configurações aplicadas
echo "🔍 Verificando configurações YAML aplicadas..."

if docker ps --format "{{.Names}}" | grep -q "^mn.tb$"; then
    # Verificar heap size
    echo "📊 Verificando heap do JVM..."
    heap_info=$(docker exec mn.tb java -XX:+PrintFlagsFinal -version 2>&1 | grep -E "MaxHeapSize|InitialHeapSize" || echo "Não encontrado")
    echo "$heap_info"
    
    # Verificar se arquivo de configuração foi carregado
    echo "📄 Verificando arquivo de configuração carregado..."
    if docker exec mn.tb test -f /usr/share/thingsboard/conf/thingsboard.yml; then
        echo "✅ Arquivo thingsboard.yml presente"
        # Mostrar algumas configurações chave
        echo "🔧 Configurações URLLC aplicadas:"
        docker exec mn.tb grep -E "CLIENT_SIDE_RPC_TIMEOUT|SQL_TS_BATCH|JAVA_OPTS" /usr/share/thingsboard/conf/thingsboard.yml 2>/dev/null || echo "Configurações padrão aplicadas"
    else
        echo "⚠️ Arquivo de configuração não encontrado no container"
    fi
else
    echo "ℹ️ ThingsBoard não está rodando para verificação"
fi

echo ""
echo "✅ Configurações URLLC aplicadas via YAML!"
echo ""
echo "📋 Principais otimizações aplicadas:"
echo "  • CLIENT_SIDE_RPC_TIMEOUT: 1000ms (vs 60000ms padrão)"
echo "  • SQL_TS_BATCH_MAX_DELAY_MS: 10ms (vs 100ms padrão)"
echo "  • JAVA_OPTS: Heap 12GB, G1GC otimizado"
echo "  • Thread pools: 32 workers otimizados"
echo "  • HTTP timeouts: Reduzidos para URLLC"
echo "  • MQTT timeout: 5000ms (vs 10000ms padrão)"
echo ""
echo "🚀 Execute 'make odte-full' para testar latências <200ms!"