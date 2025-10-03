#!/bin/bash

# Script para implementar filtragem inteligente de Digital Twins
# baseada nos simuladores ativos

echo "🔍 ANÁLISE DE SIMULADORES ATIVOS E DIGITAL TWINS"
echo "=================================================="

# 1. Identificar simuladores ativos
echo "1. 📱 SIMULADORES ATIVOS:"
ACTIVE_SIMS=$(docker ps --format '{{.Names}}' | grep '^mn.sim_' | sort)
SIM_COUNT=$(echo "$ACTIVE_SIMS" | wc -l)
echo "   Encontrados $SIM_COUNT simuladores ativos:"

for sim in $ACTIVE_SIMS; do
    # Extrair número do simulador (sim_001 -> 1, sim_002 -> 2)
    SIM_NUM=$(echo "$sim" | sed 's/mn\.sim_0*//')
    echo "   - $sim (número: $SIM_NUM)"
done

echo ""

# 2. Listar todos os Digital Twins no middleware
echo "2. 🤖 DIGITAL TWINS NO MIDDLEWARE:"
echo "   Consultando middleware..."

# Usar Python inline para consultar o middleware
docker exec mn.middts python3 -c "
import os, sys
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'middleware-dt.settings')
import django
django.setup()

try:
    from facade.models import Device
    from orchestrator.models import DigitalTwinInstance
    
    print('   === DEVICES ===')
    devices = Device.objects.all()
    print(f'   Total devices: {len(devices)}')
    for i, device in enumerate(devices[:10]):
        print(f'   Device {i+1}: ID={device.id}, TB_ID={device.thingsboard_id}, Name={device.name}')
    
    print('')
    print('   === DIGITAL TWINS ===')
    dt_instances = DigitalTwinInstance.objects.all()
    print(f'   Total Digital Twins: {len(dt_instances)}')
    for i, dt in enumerate(dt_instances[:10]):
        device_name = dt.device.name if dt.device else 'No device'
        print(f'   DT {i+1}: ID={dt.id}, Device={device_name}, Model={dt.model.name if dt.model else \"No model\"}')

except Exception as e:
    print(f'   ERRO: {e}')
" 2>/dev/null || echo "   ❌ Erro ao consultar middleware"

echo ""

# 3. Estratégia de filtragem baseada em padrões conhecidos
echo "3. 🎯 ESTRATÉGIA DE FILTRAGEM:"
echo "   Simuladores seguem padrão: sim_001, sim_002, sim_003, sim_004, sim_005"
echo "   Devices provavelmente seguem padrão similar ou têm referência aos simuladores"
echo ""

# 4. Implementação da filtragem
echo "4. 🚀 IMPLEMENTANDO FILTRAGEM INTELIGENTE:"
echo "   Criando comando update_causal_property com filtro..."

# Criar lista de IDs de simuladores ativos para usar como filtro
ACTIVE_SIM_NUMBERS=$(echo "$ACTIVE_SIMS" | sed 's/mn\.sim_0*//' | tr '\n' ' ')
echo "   Números de simuladores ativos: $ACTIVE_SIM_NUMBERS"

echo ""
echo "5. 💡 PRÓXIMOS PASSOS:"
echo "   - Identificar padrão de mapeamento simulador -> device_id -> digital_twin_id"
echo "   - Executar update_causal_property apenas para Digital Twins dos simuladores ativos"
echo "   - Validar melhoria de performance"