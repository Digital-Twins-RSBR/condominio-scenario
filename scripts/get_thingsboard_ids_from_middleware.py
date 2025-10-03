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
