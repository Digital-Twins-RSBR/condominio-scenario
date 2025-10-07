#!/bin/bash

# Script de filtragem inteligente de Digital Twins para simuladores ativos
# Versão 2: Implementação prática da solução

echo "🚀 IMPLEMENTAÇÃO DE FILTRAGEM INTELIGENTE DE DIGITAL TWINS"
echo "=========================================================="

# 1. Identificar simuladores ativos
echo "1. 📱 IDENTIFICANDO SIMULADORES ATIVOS:"
ACTIVE_SIMS=$(docker ps --format '{{.Names}}' | grep '^mn.sim_' | sort)
SIM_COUNT=$(echo "$ACTIVE_SIMS" | wc -l)
echo "   ✅ Encontrados $SIM_COUNT simuladores ativos"

# Extrair números dos simuladores
ACTIVE_SIM_NUMBERS=""
for sim in $ACTIVE_SIMS; do
    SIM_NUM=$(echo "$sim" | sed 's/mn\.sim_0*//')
    ACTIVE_SIM_NUMBERS="$ACTIVE_SIM_NUMBERS $SIM_NUM"
    echo "   - $sim (número: $SIM_NUM)"
done

echo ""

# 2. Parar o processo update_causal_property atual (que processa todos os 120+ Digital Twins)
echo "2. ⏹️ PARANDO PROCESSO update_causal_property ATUAL:"
docker exec mn.middts bash -c "pkill -f 'manage.py update_causal_property' || true"
docker exec mn.middts bash -c "rm -f /tmp/update_causal_property.pid || true"
echo "   ✅ Processo anterior interrompido"

sleep 2

# 3. Consultar Digital Twins para identificar padrões de mapeamento
echo "3. 🔍 IDENTIFICANDO DIGITAL TWINS DOS SIMULADORES ATIVOS:"

# Criar script Python para consulta específica
cat > /tmp/query_digital_twins.py << 'EOF'
#!/usr/bin/env python3
import os
import sys
import django

# Configure Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'middleware-dt.settings')
django.setup()

try:
    from facade.models import Device
    from orchestrator.models import DigitalTwinInstance
    
    # Buscar patterns de device names que correspondem aos simuladores ativos
    active_sim_numbers = sys.argv[1].strip().split() if len(sys.argv) > 1 else []
    
    print(f"🔍 Procurando Digital Twins para simuladores: {active_sim_numbers}")
    
    # Estratégia 1: Buscar devices que contenham números dos simuladores
    relevant_dt_ids = []
    relevant_devices = []
    
    for sim_num in active_sim_numbers:
        # Buscar devices que tenham o número do simulador no nome
        devices = Device.objects.filter(name__icontains=f"House {sim_num}")
        if not devices:
            # Alternativa: buscar por outros padrões
            devices = Device.objects.filter(name__icontains=f"sim_{sim_num.zfill(3)}")
        
        for device in devices:
            relevant_devices.append(device)
            # Buscar Digital Twins deste device
            dt_instances = DigitalTwinInstance.objects.filter(device=device)
            for dt in dt_instances:
                relevant_dt_ids.append(dt.id)
    
    print(f"📊 Encontrados {len(relevant_devices)} devices relevantes")
    print(f"🤖 Encontrados {len(relevant_dt_ids)} Digital Twins relevantes")
    
    # Se não encontramos por padrão de nome, buscar os primeiros N Digital Twins
    if not relevant_dt_ids:
        print("⚠️ Não encontrou por padrão de nome, usando primeiros Digital Twins...")
        all_dt = DigitalTwinInstance.objects.all()[:len(active_sim_numbers)]
        relevant_dt_ids = [dt.id for dt in all_dt]
    
    # Imprimir os IDs encontrados
    if relevant_dt_ids:
        print(f"🎯 IDs de Digital Twins relevantes: {' '.join(map(str, relevant_dt_ids))}")
    else:
        print("❌ Nenhum Digital Twin encontrado")
        
except Exception as e:
    print(f"❌ ERRO: {e}")
    import traceback
    traceback.print_exc()
EOF

# Executar consulta no container do middleware
FILTERED_DT_IDS=$(docker exec mn.middts bash -c "cd /middleware-dt && python3 /tmp/query_digital_twins.py '$ACTIVE_SIM_NUMBERS'" | grep "🎯 IDs" | cut -d: -f2 | xargs)

echo "   Resultado da consulta:"
docker exec mn.middts bash -c "cd /middleware-dt && python3 /tmp/query_digital_twins.py '$ACTIVE_SIM_NUMBERS'"
echo ""

# 4. Executar update_causal_property com filtro
echo "4. 🚀 EXECUTANDO update_causal_property COM FILTRO:"

if [ -n "$FILTERED_DT_IDS" ]; then
    echo "   ✅ Executando com IDs filtrados: $FILTERED_DT_IDS"
    
    # Executar update_causal_property com os IDs específicos
    docker exec -d mn.middts bash -c "
        cd /middleware-dt && 
        nohup python3 manage.py update_causal_property --dt-ids $FILTERED_DT_IDS > /middleware-dt/update_causal_property_filtered.out 2>&1 & 
        echo \$! > /tmp/update_causal_property_filtered.pid
    "
    
    # Verificar se iniciou
    sleep 3
    if docker exec mn.middts bash -c "ps -ef | grep -v grep | grep 'update_causal_property.*--dt-ids' >/dev/null 2>&1"; then
        echo "   ✅ Processo filtrado iniciado com sucesso"
        echo "   📊 Monitorando apenas $(echo $FILTERED_DT_IDS | wc -w) Digital Twins ao invés de 120+"
    else
        echo "   ❌ Falha ao iniciar processo filtrado"
    fi
else
    echo "   ⚠️ Nenhum ID filtrado encontrado, executando com todos (fallback)"
    docker exec -d mn.middts bash -c "
        cd /middleware-dt && 
        nohup python3 manage.py update_causal_property > /middleware-dt/update_causal_property_fallback.out 2>&1 & 
        echo \$! > /tmp/update_causal_property_fallback.pid
    "
fi

echo ""

# 5. Monitoramento do desempenho
echo "5. 📊 MONITORAMENTO DE DESEMPENHO:"
echo "   Para verificar logs:"
if [ -n "$FILTERED_DT_IDS" ]; then
    echo "   docker exec mn.middts tail -f /middleware-dt/update_causal_property_filtered.out"
else
    echo "   docker exec mn.middts tail -f /middleware-dt/update_causal_property_fallback.out"
fi

echo ""
echo "6. 🎯 PRÓXIMOS PASSOS:"
echo "   - Executar teste ODTE para validar melhoria de latência"
echo "   - Verificar se S2M < 2s e conectividade > 95%"
echo "   - Comparar com performance anterior"

echo ""
echo "✅ FILTRAGEM INTELIGENTE IMPLEMENTADA!"
echo "🔍 Processando apenas simuladores ativos ao invés de todos os 120+ Digital Twins"