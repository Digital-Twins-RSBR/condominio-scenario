import os
import yaml

NUM_CONTAINERS = 100
IMAGE_NAME = "iot_simulator:latest"  # Substitua pelo nome da imagem publicada, se necessário
OUTPUT_FILE = "generated/docker-compose.generated.yml"
ENVS_DIR = "generated/envs"
NETWORK_NAME = "middleware-dt_default"

os.makedirs(ENVS_DIR, exist_ok=True)

compose = {
    "version": "3.8",
    "services": {},
    "networks": {
        "default": {
            "external": True,
            "name": NETWORK_NAME
        }
    }
}

for i in range(1, NUM_CONTAINERS + 1):
    service_name = f"simulator_{i}"
    env_file = f"{ENVS_DIR}/{service_name}.env"

    # Criar arquivo .env individual para o container
    with open(env_file, "w") as f:
        f.write(f"DEVICE_ID=simulated-device-{i}\n")
        f.write(f"USE_INFLUX=True\n")
        f.write(f"THINGSBOARD_HOST=thingsboard\n")
        f.write(f"INFLUXDB_HOST=influxdb\n")
        f.write(f"INFLUXDB_PORT=8086\n")
        f.write(f"INFLUXDB_BUCKET=iot_data\n")
        f.write(f"INFLUXDB_ORGANIZATION=middts\n")
        f.write(f"INFLUXDB_TOKEN=admin_token_middts\n")

    # Definir o serviço no docker-compose
    compose["services"][service_name] = {
        "image": IMAGE_NAME,
        "env_file": [env_file],
        "depends_on": ["middleware", "influxdb", "thingsboard"],
        "restart": "unless-stopped"
    }

# Salvar YAML gerado
os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)
with open(OUTPUT_FILE, "w") as f:
    yaml.dump(compose, f)

print(f"Arquivo gerado: {OUTPUT_FILE}")
