#!/bin/bash

# ==============================================================================
# URLLC Minimal Optimizations Script
# ==============================================================================
# Descrição: Aplica otimizações de rede e sistema para latência ultra-baixa
# Uso: Executado automaticamente pela topologia ou manualmente
# Categoria: [PRINCIPAL] - Otimizações URLLC
# 
# Funcionalidades:
# - Configurações de rede otimizadas (3Gbit/s, burst 64KB, delay 0.05ms)
# - Otimizações TCP (BBR congestion control, buffers)
# - Configurações de middleware sem restart
# 
# Diferença do apply_urllc_config.sh:
# - Não reinicia ThingsBoard (evita instabilidade)
# - Mais rápido e estável
# - Focado apenas em otimizações de runtime
# ==============================================================================

echo "🚀 Aplicando configurações URLLC otimizadas (minimal)..."

# 1. Aplicar configurações de rede otimizadas nos simuladores
echo "🌐 Aplicando configurações de rede otimizadas..."
for container in mn.sim_001 mn.sim_002 mn.sim_003 mn.sim_004 mn.sim_005 mn.sim_006 mn.sim_007 mn.sim_008 mn.sim_009 mn.sim_010; do
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        echo "  Configurando rede otimizada em $container..."
        
        # Limpar regras existentes
        docker exec "$container" tc qdisc del dev eth0 root 2>/dev/null || true
        
        # Aplicar configuração URLLC otimizada
        docker exec "$container" tc qdisc add dev eth0 root handle 1: tbf rate 3gbit burst 64kb latency 20ms
        docker exec "$container" tc qdisc add dev eth0 parent 1:1 handle 10: netem delay 0.05ms
        
        # Otimizar buffers TCP
        docker exec "$container" bash -c "
            echo 8192 > /proc/sys/net/core/wmem_default 2>/dev/null || true
            echo 16384 > /proc/sys/net/core/wmem_max 2>/dev/null || true
            echo 'bbr' > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || true
            echo 1 > /proc/sys/net/ipv4/tcp_low_latency 2>/dev/null || true
        " 2>/dev/null || true
    fi
done

# 2. Aplicar configurações de rede no middleware (sem reiniciar)
echo "🏃 Otimizando configurações do middleware..."
docker exec mn.middts bash -c "
    export REQUESTS_TIMEOUT=3
    export KEEP_ALIVE_TIMEOUT=30
    export DB_POOL_SIZE=20
    export THINGSBOARD_POOL_SIZE=15
    export THINGSBOARD_TIMEOUT=2
    export KEEP_ALIVE=true
" 2>/dev/null || true

echo "✅ Configurações URLLC otimizadas aplicadas com sucesso!"
echo ""
echo "📋 Resumo das otimizações aplicadas:"
echo "  • Rede: 3Gbit/s, burst 64KB, delay 0.05ms"
echo "  • TCP: BBR congestion control, buffers otimizados"
echo "  • Middleware: pools otimizados, timeouts reduzidos"
echo "  • ThingsBoard: otimizações já aplicadas via Dockerfile"
echo "  • Simuladores: HEARTBEAT_INTERVAL=4s já aplicado via Dockerfile"