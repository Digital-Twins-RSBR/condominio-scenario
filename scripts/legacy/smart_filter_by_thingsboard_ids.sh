#!/bin/bash

# Script para coletar IDs REAIS do ThingsBoard dos simuladores ativos
# Método robusto usando consulta ao banco do middleware

echo "🔍 COLETANDO IDs REAIS DO THINGSBOARD"
echo "====================================="

# 1. Identificar simuladores ativos
echo "1. 📱 SIMULADORES ATIVOS:"
ACTIVE_SIMS=$(docker ps --format '{{.Names}}' | grep '^mn.sim_' | sort)
SIM_COUNT=$(echo "$ACTIVE_SIMS" | wc -l)
echo "   ✅ Encontrados $SIM_COUNT simuladores: $ACTIVE_SIMS"

echo ""

# 2. Consultar middleware para mapear simuladores para ThingsBoard IDs
echo "2. 🔍 CONSULTANDO MIDDLEWARE PARA MAPEAR SIMULADORES:"

# Criar script Python para consulta precisa
cat > /var/condominio-scenario/scripts/get_thingsboard_ids_from_middleware.py << 'EOF'
#!/usr/bin/env python3
import sys
import re

def extract_sim_numbers(sim_names):
    """Extrai números dos simuladores (sim_001 -> 1, sim_002 -> 2, etc)"""
    numbers = []
    for sim_name in sim_names.split():
        match = re.search(r'sim_0*(\d+)', sim_name)
        if match:
            numbers.append(int(match.group(1)))
    return sorted(numbers)

def main():
    import os
    import django
    
    # Configure Django
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'middleware-dt.settings')
    django.setup()
    
    try:
        from facade.models import Device
        
        sim_names = sys.argv[1] if len(sys.argv) > 1 else ""
        sim_numbers = extract_sim_numbers(sim_names)
        
        print(f"🔍 Procurando devices para simuladores: {sim_numbers}")
        
        thingsboard_ids = []
        
        # Estratégia 1: Buscar por padrões de nome conhecidos
        for sim_num in sim_numbers:
            patterns = [
                f"House {sim_num}",
                f"sim_{sim_num:03d}",
                f"simulator_{sim_num}",
                f"device_{sim_num}",
                f"sim{sim_num}"
            ]
            
            device_found = False
            for pattern in patterns:
                devices = Device.objects.filter(name__icontains=pattern)
                
                for device in devices:
                    if device.thingsboard_id:
                        print(f"📱 Simulador {sim_num}: Device '{device.name}' -> TB ID: {device.thingsboard_id}")
                        thingsboard_ids.append(device.thingsboard_id)
                        device_found = True
                        break
                
                if device_found:
                    break
            
            if not device_found:
                print(f"❌ Simulador {sim_num}: Nenhum device encontrado")
        
        # Se não encontrou por padrão, listar alguns devices para análise
        if not thingsboard_ids:
            print("\n⚠️ Nenhum device encontrado por padrão. Listando devices disponíveis:")
            all_devices = Device.objects.all()[:10]
            for i, device in enumerate(all_devices):
                tb_id = device.thingsboard_id or "N/A"
                print(f"   Device {i+1}: '{device.name}' -> TB ID: {tb_id}")
            
            # Como fallback, pegar os primeiros N devices com ThingsBoard ID
            print(f"\n🔄 Usando fallback: primeiros {len(sim_numbers)} devices com ThingsBoard ID")
            devices_with_tb_id = Device.objects.exclude(thingsboard_id__isnull=True).exclude(thingsboard_id='')[:len(sim_numbers)]
            for device in devices_with_tb_id:
                print(f"📱 Fallback: Device '{device.name}' -> TB ID: {device.thingsboard_id}")
                thingsboard_ids.append(device.thingsboard_id)
        
        # Imprimir resultado final
        if thingsboard_ids:
            print(f"\n🎯 THINGSBOARD_IDS_FOUND: {' '.join(thingsboard_ids)}")
        else:
            print("\n❌ NENHUM THINGSBOARD ID ENCONTRADO")
            
    except Exception as e:
        print(f"❌ ERRO: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()
EOF

# Copiar script para o container e executar
docker cp /var/condominio-scenario/scripts/get_thingsboard_ids_from_middleware.py mn.middts:/middleware-dt/

# Executar consulta
RESULT=$(docker exec mn.middts bash -c "cd /middleware-dt && python3 get_thingsboard_ids_from_middleware.py '$ACTIVE_SIMS'")

echo "$RESULT"

# Extrair IDs encontrados
THINGSBOARD_IDS=$(echo "$RESULT" | grep "THINGSBOARD_IDS_FOUND:" | cut -d: -f2 | xargs)

echo ""
echo "3. 📋 RESULTADO:"
if [ -n "$THINGSBOARD_IDS" ]; then
    echo "   ✅ IDs do ThingsBoard coletados: $(echo $THINGSBOARD_IDS | wc -w)"
    echo "   🔑 Lista: $THINGSBOARD_IDS"
    
    echo ""
    echo "4. 🚀 APLICANDO FILTRO INTELIGENTE:"
    
    # Parar processo atual
    docker exec mn.middts bash -c "pkill -f 'manage.py update_causal_property' || true"
    docker exec mn.middts bash -c "rm -f /tmp/update_causal_property*.pid || true"
    sleep 2
    
    # Executar update_causal_property com ThingsBoard IDs
    echo "   📤 Executando update_causal_property --thingsboard-ids $THINGSBOARD_IDS"
    
    docker exec -d mn.middts bash -c "
        cd /middleware-dt && 
        nohup python3 manage.py update_causal_property --thingsboard-ids $THINGSBOARD_IDS > /middleware-dt/update_causal_property_thingsboard_filter.out 2>&1 & 
        echo \$! > /tmp/update_causal_property_thingsboard_filter.pid
    "
    
    # Verificar se iniciou
    sleep 3
    PROCESS_RUNNING=$(docker exec mn.middts bash -c "ps -ef | grep -v grep | grep 'update_causal_property.*--thingsboard-ids' | wc -l")
    
    if [ "$PROCESS_RUNNING" -gt "0" ]; then
        echo "   ✅ Processo filtrado iniciado com sucesso"
        echo "   📊 Monitorando apenas $(echo $THINGSBOARD_IDS | wc -w) devices ao invés de 120+"
        
        echo ""
        echo "5. 📊 VERIFICAÇÃO INICIAL:"
        sleep 5
        docker exec mn.middts tail -10 /middleware-dt/update_causal_property_thingsboard_filter.out
        
        echo ""
        echo "✅ FILTRO INTELIGENTE APLICADO!"
        echo "🎯 Para monitorar: docker exec mn.middts tail -f /middleware-dt/update_causal_property_thingsboard_filter.out"
        echo "🚀 Execute teste ODTE para validar melhoria: make odte-monitored DURATION=300"
    else
        echo "   ❌ Falha ao iniciar processo filtrado"
    fi
else
    echo "   ❌ Nenhum ID do ThingsBoard encontrado"
    echo "   💡 Verifique se os devices estão cadastrados no middleware"
fi