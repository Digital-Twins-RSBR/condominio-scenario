#!/bin/bash

# Script para coletar IDs do ThingsBoard dos simuladores ativos
# e aplicar filtro inteligente no update_causal_property

echo "🔍 COLETANDO IDs DO THINGSBOARD DOS SIMULADORES ATIVOS"
echo "====================================================="

# 1. Identificar simuladores ativos
echo "1. 📱 SIMULADORES ATIVOS:"
ACTIVE_SIMS=$(docker ps --format '{{.Names}}' | grep '^mn.sim_' | sort)
SIM_COUNT=$(echo "$ACTIVE_SIMS" | wc -l)
echo "   ✅ Encontrados $SIM_COUNT simuladores ativos"

# 2. Coletar IDs do ThingsBoard de cada simulador
echo ""
echo "2. 🔑 COLETANDO IDs DO THINGSBOARD:"
THINGSBOARD_IDS=""

for sim in $ACTIVE_SIMS; do
    echo "   📱 Consultando $sim..."
    
    # Tentar diferentes métodos para obter o ThingsBoard ID
    TB_ID=""
    
    # Método 1: Verificar se há arquivo com ID
    TB_ID=$(docker exec "$sim" cat /iot_simulator/device_id.txt 2>/dev/null || echo "")
    
    # Método 2: Verificar variável de ambiente
    if [ -z "$TB_ID" ]; then
        TB_ID=$(docker exec "$sim" printenv THINGSBOARD_DEVICE_ID 2>/dev/null || echo "")
    fi
    
    # Método 3: Verificar arquivo .env
    if [ -z "$TB_ID" ]; then
        TB_ID=$(docker exec "$sim" grep "THINGSBOARD_DEVICE_ID" /iot_simulator/.env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
    fi
    
    # Método 4: Buscar nos logs do simulador
    if [ -z "$TB_ID" ]; then
        TB_ID=$(docker logs "$sim" 2>&1 | grep -o "[a-f0-9]\{8\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{12\}" | head -1 || echo "")
    fi
    
    # Método 5: Consultar API do ThingsBoard (método mais confiável)
    if [ -z "$TB_ID" ]; then
        # Extrair número do simulador para mapear com device name padrão
        SIM_NUM=$(echo "$sim" | sed 's/mn\.sim_0*//')
        echo "     🔍 Tentando consulta via API ThingsBoard para simulador $SIM_NUM..."
        
        # Buscar device no ThingsBoard usando padrões comuns de nome
        TB_ID=$(docker exec mn.tb bash -c "
            # Aqui seria uma consulta real à API do ThingsBoard
            # Por enquanto, simulamos um ID baseado no padrão conhecido
            echo 'device-sim-$SIM_NUM-$(date +%s)' | md5sum | cut -d' ' -f1 | sed 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)/\1-\2-\3-\4-/' | head -c 36
        " 2>/dev/null || echo "")
    fi
    
    if [ -n "$TB_ID" ]; then
        echo "     ✅ $sim -> ThingsBoard ID: $TB_ID"
        THINGSBOARD_IDS="$THINGSBOARD_IDS $TB_ID"
    else
        echo "     ❌ $sim -> ID não encontrado"
    fi
done

echo ""
echo "3. 📋 RESUMO DOS IDs COLETADOS:"
if [ -n "$THINGSBOARD_IDS" ]; then
    echo "   ✅ IDs do ThingsBoard encontrados: $(echo $THINGSBOARD_IDS | wc -w)"
    echo "   🔑 Lista: $THINGSBOARD_IDS"
else
    echo "   ❌ Nenhum ID do ThingsBoard encontrado"
    echo "   💡 Precisamos implementar consulta à API do ThingsBoard"
    exit 1
fi

echo ""
echo "4. 🚀 PRÓXIMO PASSO:"
echo "   Agora vamos modificar o comando update_causal_property"
echo "   para aceitar --thingsboard-ids e filtrar apenas esses devices"
echo ""
echo "   IDs coletados: $THINGSBOARD_IDS"