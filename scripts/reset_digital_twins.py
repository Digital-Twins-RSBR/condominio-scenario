#!/usr/bin/env python
"""
Script para reset completo de Digital Twins e recriação automática
Comportamento:
1. Apaga todos os Digital Twins existentes e suas propriedades
2. Identifica devices que possuem modelagem DTDL definida 
3. Cria novos Digital Twins automaticamente para esses devices
4. Associa as propriedades dos devices aos Digital Twins criados
"""

import os
import django
import sys
from django.db import transaction

# Setup Django
sys.path.append('/var/condominio-scenario/services/middleware-dt')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'middleware_dt.settings')
django.setup()

from facade.models import Device, Property, DeviceType
from orchestrator.models import (
    DigitalTwinInstance, DigitalTwinInstanceProperty, DigitalTwinInstanceRelationship,
    DTDLModel, ModelElement, SystemContext
)
from orchestrator.utils import normalize_name
import re


def print_status(message, level="INFO"):
    """Print status message with formatting"""
    levels = {
        "INFO": "🔵",
        "SUCCESS": "✅", 
        "WARNING": "⚠️",
        "ERROR": "❌",
        "STEP": "📋"
    }
    icon = levels.get(level, "ℹ️")
    print(f"{icon} {message}")


def delete_all_digital_twins():
    """Remove todos os Digital Twins e relacionamentos existentes"""
    print_status("STEP 1: Removendo todos os Digital Twins existentes", "STEP")
    
    # Count before deletion
    dt_count = DigitalTwinInstance.objects.count()
    prop_count = DigitalTwinInstanceProperty.objects.count()
    rel_count = DigitalTwinInstanceRelationship.objects.count()
    
    print_status(f"Found {dt_count} Digital Twins, {prop_count} properties, {rel_count} relationships")
    
    # Delete in correct order to avoid constraint violations
    with transaction.atomic():
        DigitalTwinInstanceRelationship.objects.all().delete()
        print_status(f"Deleted {rel_count} Digital Twin relationships")
        
        DigitalTwinInstanceProperty.objects.all().delete()
        print_status(f"Deleted {prop_count} Digital Twin properties")
        
        DigitalTwinInstance.objects.all().delete()
        print_status(f"Deleted {dt_count} Digital Twin instances")
    
    print_status("All Digital Twins removed successfully", "SUCCESS")


def get_devices_with_modeling():
    """Identifica devices que possuem modelagem DTDL disponível"""
    print_status("STEP 2: Identificando devices com modelagem DTDL", "STEP")
    
    devices = Device.objects.all()
    models = DTDLModel.objects.all()
    
    print_status(f"Found {devices.count()} total devices")
    print_status(f"Found {models.count()} DTDL models available")
    
    devices_with_modeling = []
    devices_without_modeling = []
    
    for device in devices:
        # Check if device type has corresponding DTDL model
        device_type_name = device.type.name if device.type else ""
        device_name = device.name or ""
        
        # Find matching DTDL model
        matching_model = find_best_model_for_device(device, models)
        
        if matching_model:
            devices_with_modeling.append((device, matching_model))
            print_status(f"✓ Device '{device.name}' ({device_type_name}) -> Model '{matching_model.name}'")
        else:
            devices_without_modeling.append(device)
            print_status(f"✗ Device '{device.name}' ({device_type_name}) -> No matching model", "WARNING")
    
    print_status(f"Devices WITH modeling: {len(devices_with_modeling)}", "SUCCESS")
    print_status(f"Devices WITHOUT modeling: {len(devices_without_modeling)}", "WARNING")
    
    return devices_with_modeling, devices_without_modeling


def find_best_model_for_device(device, models):
    """Encontra o melhor modelo DTDL para um device usando heurísticas"""
    device_type_name = normalize_name(device.type.name) if device.type else ""
    device_name = normalize_name(device.name or "")
    
    # 1. Exact match com device type
    for model in models:
        model_name = normalize_name(model.name)
        if device_type_name and device_type_name == model_name:
            return model
    
    # 2. Device type contains model name ou vice-versa
    for model in models:
        model_name = normalize_name(model.name)
        if device_type_name and (device_type_name in model_name or model_name in device_type_name):
            return model
    
    # 3. Match com tokens do device name
    device_tokens = [t for t in re.split(r'\W+', device_name) if t and len(t) > 2]
    for model in models:
        model_name = normalize_name(model.name)
        for token in device_tokens:
            if token in model_name:
                return model
    
    # 4. Match por similaridade semântica (se disponível)
    try:
        return find_model_by_similarity(device, models)
    except:
        pass
    
    return None


def find_model_by_similarity(device, models):
    """Usa similaridade semântica para encontrar modelo mais próximo"""
    try:
        from sentence_transformers import SentenceTransformer, util
        
        model_st = SentenceTransformer('all-MiniLM-L6-v2')
        
        device_text = f"{device.name} {device.type.name if device.type else ''} {device.metadata or ''}"
        device_embedding = model_st.encode(device_text, convert_to_tensor=True)
        
        best_model = None
        best_score = 0.0
        threshold = 0.6  # Ajustável
        
        for dtdl_model in models:
            model_text = f"{dtdl_model.name} {dtdl_model.description if hasattr(dtdl_model, 'description') else ''}"
            model_embedding = model_st.encode(model_text, convert_to_tensor=True)
            
            score = float(util.cos_sim(device_embedding, model_embedding)[0][0])
            
            if score > best_score and score >= threshold:
                best_score = score
                best_model = dtdl_model
        
        return best_model
    except Exception as e:
        print_status(f"Semantic similarity failed: {e}", "WARNING")
        return None


def create_digital_twins(devices_with_modeling):
    """Cria Digital Twins para devices com modelagem"""
    print_status("STEP 3: Criando novos Digital Twins", "STEP")
    
    created_count = 0
    failed_count = 0
    
    with transaction.atomic():
        for device, model in devices_with_modeling:
            try:
                # Create Digital Twin Instance
                dt_instance = DigitalTwinInstance.objects.create(
                    model=model,
                    name=f"{device.name}",
                    active=True
                )
                
                # Associate device properties to Digital Twin properties
                properties_mapped = associate_device_properties(device, dt_instance)
                
                created_count += 1
                print_status(
                    f"✓ Created Digital Twin '{dt_instance.name}' "
                    f"(model: {model.name}, properties: {properties_mapped})"
                )
                
            except Exception as e:
                failed_count += 1
                print_status(f"✗ Failed to create Digital Twin for device '{device.name}': {e}", "ERROR")
    
    print_status(f"Digital Twins created: {created_count}", "SUCCESS")
    print_status(f"Failed creations: {failed_count}", "ERROR" if failed_count > 0 else "INFO")
    
    return created_count


def associate_device_properties(device, dt_instance):
    """Associa propriedades do device às propriedades do Digital Twin"""
    device_properties = Property.objects.filter(device=device)
    model_elements = ModelElement.objects.filter(dtdl_model=dt_instance.model)
    
    mapped_count = 0
    
    for device_prop in device_properties:
        # Find best matching model element
        best_element = find_best_model_element(device_prop, model_elements)
        
        if best_element:
            # Get or create Digital Twin Instance Property
            dt_prop, created = DigitalTwinInstanceProperty.objects.get_or_create(
                dtinstance=dt_instance,
                property=best_element,
                defaults={'value': device_prop.value}
            )
            
            # Associate with device property
            dt_prop.device_property = device_prop
            dt_prop.value = device_prop.value
            dt_prop.save()
            
            mapped_count += 1
            
            if created:
                print_status(f"  ✓ Mapped property '{device_prop.name}' -> '{best_element.name}'")
        else:
            print_status(f"  ✗ No model element found for property '{device_prop.name}'", "WARNING")
    
    return mapped_count


def find_best_model_element(device_property, model_elements):
    """Encontra o melhor ModelElement para uma Property do device"""
    prop_name = normalize_name(device_property.name)
    
    # 1. Exact match
    for element in model_elements:
        if normalize_name(element.name) == prop_name:
            return element
    
    # 2. Contains match
    for element in model_elements:
        element_name = normalize_name(element.name)
        if prop_name in element_name or element_name in prop_name:
            return element
    
    # 3. Type compatibility
    for element in model_elements:
        if device_property.type and element.schema:
            # Map device property types to DTDL schema types
            type_mapping = {
                'Boolean': ['boolean', 'bool'],
                'Integer': ['integer', 'int', 'long'],
                'Double': ['double', 'float', 'number']
            }
            
            device_type_variants = type_mapping.get(device_property.type, [device_property.type.lower()])
            if any(variant in element.schema.lower() for variant in device_type_variants):
                return element
    
    return None


def create_hierarchical_relationships():
    """Cria relacionamentos hierárquicos entre Digital Twins quando aplicável"""
    print_status("STEP 4: Criando relacionamentos hierárquicos", "STEP")
    
    # This is a placeholder for more sophisticated relationship creation
    # Based on device metadata, location, or model relationships
    
    dt_instances = DigitalTwinInstance.objects.all()
    relationships_created = 0
    
    # Example: group devices by common identifiers (house number, room, etc.)
    grouped_instances = {}
    
    for dt in dt_instances:
        # Extract grouping key from device metadata or name
        device = None
        dt_prop = DigitalTwinInstanceProperty.objects.filter(dtinstance=dt).first()
        if dt_prop and dt_prop.device_property:
            device = dt_prop.device_property.device
        
        if device:
            group_key = extract_group_key(device)
            grouped_instances.setdefault(group_key, []).append(dt)
    
    # Create relationships within groups (simplified logic)
    for group_key, instances in grouped_instances.items():
        if len(instances) > 1:
            print_status(f"Group '{group_key}' has {len(instances)} instances")
            # Here you could implement more sophisticated hierarchy creation
    
    print_status(f"Hierarchical relationships created: {relationships_created}")
    return relationships_created


def extract_group_key(device):
    """Extract grouping key from device name/metadata"""
    name = device.name or ""
    metadata = device.metadata or ""
    text = f"{name} {metadata}".lower()
    
    # Look for house/room/apartment patterns
    patterns = [
        r"\b(house|home|apt|apartment|condo|condominium|unit)[\s_-]?(\d+)\b",
        r"\b(room|sala|quarto)[\s_-]?(\d+)\b",
        r"\b(\d+)\b"
    ]
    
    for pattern in patterns:
        match = re.search(pattern, text)
        if match:
            return match.group(0)
    
    # Fallback to first word
    tokens = [t for t in re.split(r'\W+', name) if t]
    return tokens[0] if tokens else "default"


def print_summary():
    """Imprime resumo final"""
    print_status("STEP 5: Resumo Final", "STEP")
    
    dt_count = DigitalTwinInstance.objects.count()
    prop_count = DigitalTwinInstanceProperty.objects.count()
    rel_count = DigitalTwinInstanceRelationship.objects.count()
    device_count = Device.objects.count()
    model_count = DTDLModel.objects.count()
    
    print_status("📊 RESUMO FINAL:")
    print_status(f"  • Total Devices: {device_count}")
    print_status(f"  • Total DTDL Models: {model_count}")
    print_status(f"  • Digital Twins Created: {dt_count}")
    print_status(f"  • Properties Mapped: {prop_count}")
    print_status(f"  • Relationships: {rel_count}")
    
    # Calculate coverage
    devices_with_dt = DigitalTwinInstanceProperty.objects.filter(
        device_property__isnull=False
    ).values('device_property__device').distinct().count()
    
    coverage = (devices_with_dt / device_count * 100) if device_count > 0 else 0
    print_status(f"  • Coverage: {devices_with_dt}/{device_count} devices ({coverage:.1f}%)")
    
    if coverage >= 80:
        print_status("Excellent coverage achieved!", "SUCCESS")
    elif coverage >= 60:
        print_status("Good coverage achieved", "SUCCESS")
    elif coverage >= 40:
        print_status("Moderate coverage - consider adding more DTDL models", "WARNING")
    else:
        print_status("Low coverage - many devices lack appropriate DTDL models", "WARNING")


def main():
    """Função principal do script"""
    print_status("🚀 DIGITAL TWIN RESET & AUTO-CREATION SCRIPT", "STEP")
    print_status("=" * 60)
    
    try:
        # Step 1: Delete all existing Digital Twins
        delete_all_digital_twins()
        
        # Step 2: Identify devices with modeling
        devices_with_modeling, devices_without_modeling = get_devices_with_modeling()
        
        if not devices_with_modeling:
            print_status("No devices with matching DTDL models found!", "ERROR")
            print_status("Please ensure DTDL models are loaded and device types are properly configured", "WARNING")
            return
        
        # Step 3: Create new Digital Twins
        created_count = create_digital_twins(devices_with_modeling)
        
        # Step 4: Create hierarchical relationships (optional)
        create_hierarchical_relationships()
        
        # Step 5: Print summary
        print_summary()
        
        print_status("=" * 60)
        print_status("Digital Twin reset and recreation completed successfully!", "SUCCESS")
        
    except Exception as e:
        print_status(f"Script failed with error: {e}", "ERROR")
        import traceback
        traceback.print_exc()
        return 1
    
    return 0


if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code)