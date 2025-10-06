#!/bin/bash

# Script para detectar automaticamente o perfil de rede ativo na topologia
# Retorna: urllc, embb, best_effort ou unknown

detect_active_profile() {
    # Verificar se há containers da topologia
    if ! docker ps --filter "name=mn." --format "{{.Names}}" | grep -q "mn."; then
        echo "unknown"
        return 1
    fi

    # Verificar configuração TC (interface Mininet correta)
    tc_info=$(docker exec mn.sim_001 tc class show dev sim_001-eth0 2>/dev/null | head -1 || echo "default")
    
    # Detectar por bandwidth e delay
    if echo "$tc_info" | grep -q "1000Mbit\|1Gbit"; then
        echo "urllc"  # URLLC: 1000Mbit = 1Gbit
    elif echo "$tc_info" | grep -q "300Mbit"; then
        echo "embb"  # eMBB: 300Mbps
    elif echo "$tc_info" | grep -q "200Mbit"; then
        echo "best_effort"  # Best Effort: 200Mbps
    else
        echo "unknown"
    fi
}

# Se chamado diretamente, executar detecção
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    detect_active_profile
fi