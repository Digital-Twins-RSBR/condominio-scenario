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
            print(f"📱 Device encontrado: {device.name} (ID: {device.id})")
            # Buscar Digital Twins deste device
            dt_instances = DigitalTwinInstance.objects.filter(device=device)
            for dt in dt_instances:
                relevant_dt_ids.append(dt.id)
                print(f"🤖 Digital Twin: {dt.id} - {device.name}")
    
    print(f"📊 Encontrados {len(relevant_devices)} devices relevantes")
    print(f"🤖 Encontrados {len(relevant_dt_ids)} Digital Twins relevantes")
    
    # Se não encontramos por padrão de nome, buscar os primeiros N Digital Twins
    if not relevant_dt_ids:
        print("⚠️ Não encontrou por padrão de nome, listando alguns devices para análise...")
        all_devices = Device.objects.all()[:10]
        for device in all_devices:
            print(f"📄 Device sample: {device.name} (ID: {device.id})")
        
        print("🔍 Usando primeiros Digital Twins como fallback...")
        all_dt = DigitalTwinInstance.objects.all()[:len(active_sim_numbers)]
        relevant_dt_ids = [dt.id for dt in all_dt]
        for dt in all_dt:
            device_name = dt.device.name if dt.device else 'No device'
            print(f"🤖 Fallback DT: {dt.id} - {device_name}")
    
    # Imprimir os IDs encontrados
    if relevant_dt_ids:
        print(f"🎯 IDs de Digital Twins relevantes: {' '.join(map(str, relevant_dt_ids))}")
    else:
        print("❌ Nenhum Digital Twin encontrado")
        
except Exception as e:
    print(f"❌ ERRO: {e}")
    import traceback
    traceback.print_exc()