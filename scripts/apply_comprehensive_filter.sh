#!/bin/bash

# Script para aplicar filtro mais abrangente baseado em proporção correta
# Versão que considera que 5 simuladores ativos = 50% dos dispositivos

echo "🚀 APLICANDO FILTRO ABRANGENTE PARA MÁXIMA CONECTIVIDADE"
echo "======================================================="

# 1. Calcular proporção correta
ACTIVE_SIMS=$(docker ps --format '{{.Names}}' | grep '^mn.sim_' | wc -l)
TOTAL_SIMS=10
PROPORTION=$(echo "scale=2; $ACTIVE_SIMS / $TOTAL_SIMS" | bc -l)

echo "1. 📊 CÁLCULO DA PROPORÇÃO:"
echo "   - Simuladores ativos: $ACTIVE_SIMS"
echo "   - Simuladores totais: $TOTAL_SIMS"
echo "   - Proporção: $PROPORTION (${ACTIVE_SIMS}0%)"

# 2. Obter IDs diretamente do banco de dados via Django shell
echo ""
echo "2. 🔍 CONSULTANDO IDs DIRETAMENTE NO BANCO DE DADOS:"

# Consultar dispositivos diretamente via Django shell - método mais confiável
echo "   📡 Executando consulta no Django shell (com retries)..."

ALL_IDS=""
TOTAL_IDS=0
RETRIES=4
SLEEP=2
for attempt in $(seq 1 $RETRIES); do
    DJANGO_QUERY="
from middleware.models import Device
devices = Device.objects.all()
device_ids = [str(device.thingsboard_id) for device in devices if device.thingsboard_id]
print('DEVICE_IDS_START')
for device_id in device_ids:
    print(device_id)
print('DEVICE_IDS_END')
print(f'TOTAL_COUNT:{len(device_ids)}')
"

    DB_RESULT=$(docker exec mn.middts bash -c "cd /middleware-dt && echo \"$DJANGO_QUERY\" | python3 manage.py shell" 2>/dev/null || true)

    if echo "$DB_RESULT" | grep -q "DEVICE_IDS_START"; then
        ALL_IDS=$(echo "$DB_RESULT" | sed -n '/DEVICE_IDS_START/,/DEVICE_IDS_END/p' | grep -v "DEVICE_IDS_" | grep -E "^[a-f0-9-]{36}$" | tr '\n' ' ')
        TOTAL_IDS=$(echo "$DB_RESULT" | grep "TOTAL_COUNT:" | cut -d: -f2 || echo "0")
        if [ -n "$ALL_IDS" ] && [ "$TOTAL_IDS" -gt "0" ]; then
            echo "   ✅ Consulta Django bem-sucedida (attempt $attempt)!"
            break
        fi
    fi
    echo "   ⚠️ Tentativa $attempt/$RETRIES: nenhum device detectado — esperando $SLEEP s e retry..."
    sleep $SLEEP
done

if [ -z "$ALL_IDS" ] || [ "$TOTAL_IDS" -eq "0" ]; then
    echo "   ❌ Consulta Django falhou após retries, tentando método alternativo (SQL)..."
    SQL_RESULT=$(docker exec mn.db psql -U postgres -d middts -tAc "SELECT thingsboard_id FROM middleware_device WHERE thingsboard_id IS NOT NULL;" 2>/dev/null || true)
    if [ -n "$SQL_RESULT" ]; then
        ALL_IDS=$(echo "$SQL_RESULT" | grep -E "^[a-f0-9-]{36}$" | tr '\n' ' ')
        TOTAL_IDS=$(echo "$ALL_IDS" | wc -w)
        echo "   ✅ Consulta SQL direta bem-sucedida! IDs: $TOTAL_IDS"
    else
        echo "   ⚠️ Nenhum método de consulta funcionou - banco pode estar vazio ainda"
        TOTAL_IDS=0
        ALL_IDS=""
    fi
fi

# If still no IDs found, try using a cached file if available to avoid testing empty set
if [ "$TOTAL_IDS" -eq "0" ]; then
    CACHE_FILE="/var/condominio-scenario/config/device_id_cache.txt"
    if [ -f "$CACHE_FILE" ]; then
        echo "   🔁 Usando cache local de device IDs: $CACHE_FILE"
        ALL_IDS=$(cat "$CACHE_FILE" | tr '\n' ' ')
        TOTAL_IDS=$(echo "$ALL_IDS" | wc -w)
        echo "   📊 IDs carregados do cache: $TOTAL_IDS"
    fi
fi

echo "   📊 Total de IDs únicos coletados: $TOTAL_IDS"

# Check if we have any device IDs
if [ "$TOTAL_IDS" -eq "0" ]; then
    echo ""
    echo "⚠️  NENHUM ID DE DISPOSITIVO ENCONTRADO NO BANCO!"
    echo "   - Banco de dados pode estar vazio (dispositivos ainda não cadastrados)"
    echo "   - Middleware pode ainda estar processando registros iniciais"
    echo "   - Tentando aplicar filtro sem restrições (todos os dispositivos)..."
    TARGET_IDS=0
    COVERAGE="N/A"
else
    # 3. Calcular quantos IDs usar baseado na proporção + margem de segurança
    TARGET_IDS=$(echo "$TOTAL_IDS * $PROPORTION + 2" | bc | cut -d. -f1)  # +2 para margem
    # Garantir pelo menos 1 ID se existirem IDs
    if [ "$TARGET_IDS" -lt "1" ] && [ "$TOTAL_IDS" -gt "0" ]; then
        TARGET_IDS=1
    fi
    # Não exceder o total disponível
    if [ "$TARGET_IDS" -gt "$TOTAL_IDS" ]; then
        TARGET_IDS=$TOTAL_IDS
    fi
    COVERAGE=$(echo "scale=1; $TARGET_IDS * 100 / $TOTAL_IDS" | bc -l)
fi

echo ""
echo "3. 📋 CÁLCULO DE DISPOSITIVOS:"
echo "   - Total de IDs únicos coletados: $TOTAL_IDS"
echo "   - IDs alvo (proporção + margem): $TARGET_IDS"
echo "   - Cobertura: ${COVERAGE}%"

# 4. Selecionar IDs (primeiros N + alguns extras para variedade)
if [ "$TOTAL_IDS" -gt "0" ]; then
    SELECTED_IDS=$(echo $ALL_IDS | tr ' ' '\n' | head -$TARGET_IDS | tr '\n' ' ')
    SELECTED_COUNT=$(echo $SELECTED_IDS | wc -w)
else
    SELECTED_IDS=""
    SELECTED_COUNT=0
fi

echo ""
echo "4. 🎯 FILTRO SELECIONADO:"
echo "   - Dispositivos selecionados: $SELECTED_COUNT"
echo "   - Expectativa de conectividade: >80%"

# 5. Aplicar filtro
echo ""
echo "5. 🚀 APLICANDO FILTRO INTELIGENTE:"

# Parar processo atual
docker exec mn.middts bash -c "pkill -f 'manage.py update_causal_property' || true; rm -f /tmp/update_causal_property*.pid || true"
sleep 2

# Aplicar novo filtro
if [ "$SELECTED_COUNT" -gt "0" ]; then
    echo "   📤 Executando update_causal_property com $SELECTED_COUNT dispositivos..."
    docker exec -d mn.middts bash -c "
        cd /middleware-dt && 
        nohup python3 manage.py update_causal_property --thingsboard-ids $SELECTED_IDS > /middleware-dt/update_causal_property_abrangente.out 2>&1 & 
        echo \$! > /tmp/update_causal_property_abrangente.pid
    "
else
    echo "   📤 Executando update_causal_property sem filtros (todos os dispositivos)..."
    docker exec -d mn.middts bash -c "
        cd /middleware-dt && 
        nohup python3 manage.py update_causal_property > /middleware-dt/update_causal_property_abrangente.out 2>&1 & 
        echo \$! > /tmp/update_causal_property_abrangente.pid
    "
fi

# Verificar se iniciou
sleep 3
PROCESS_RUNNING=$(docker exec mn.middts bash -c "ps -ef | grep -v grep | grep 'update_causal_property.*--thingsboard-ids' | wc -l")

if [ "$PROCESS_RUNNING" -gt "0" ]; then
    echo "   ✅ Processo filtrado iniciado com sucesso!"
    
    # Calcular estatísticas
    if [ "$TOTAL_IDS" -gt "0" ]; then
        REDUCTION_PERCENT=$(echo "scale=1; ($TOTAL_IDS - $SELECTED_COUNT) * 100 / $TOTAL_IDS" | bc -l)
    else
        REDUCTION_PERCENT="N/A"
    fi
    
    echo ""
    echo "6. 📊 VERIFICAÇÃO INICIAL:"
    sleep 5
    docker exec mn.middts tail -8 /middleware-dt/update_causal_property_abrangente.out
    
    echo ""
    echo "✅ FILTRO INTELIGENTE APLICADO!"
    echo "=============================="
    echo "📊 Nova Configuração:"
    echo "   - Simuladores ativos: $ACTIVE_SIMS de $TOTAL_SIMS"
    echo "   - Dispositivos processados: $SELECTED_COUNT de $TOTAL_IDS"
    echo "   - Redução de carga: ~${REDUCTION_PERCENT}%"
    echo "   - Expectativa de conectividade: >80%"
    echo ""
    echo "🔍 Para monitorar:"
    echo "   docker exec mn.middts tail -f /middleware-dt/update_causal_property_abrangente.out"
    echo ""
    echo "📊 Para verificar conectividade em tempo real:"
    echo "   ./scripts/monitor_realtime_connectivity.sh"
    echo ""
    echo "🚀 PRÓXIMO TESTE:"
    echo "   make odte-full DURATION=300"
    
else
    echo "   ❌ Falha ao iniciar processo filtrado"
    docker exec mn.middts tail -10 /middleware-dt/update_causal_property_abrangente.out
fi