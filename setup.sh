#!/bin/bash
set -e

# Carrega variáveis do .env
ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
    echo "Carregando variáveis de $ENV_FILE..."
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo "Arquivo .env não encontrado. Abortando."
    exit 1
fi

REPO_DIR="$(pwd)/repos"
SIM_COUNT="${SIMULATOR_COUNT:-10}"
NETWORK_NAME="${COMPOSE_NETWORK:-simnet}"

mkdir -p "$REPO_DIR"

function sync_repo() {
  local name="$1"
  local url="$2"
  local path="$REPO_DIR/$name"
  if [ ! -d "$path" ]; then
    git clone "$url" "$path"
  else
    echo "Atualizando $name..."
    git -C "$path" pull
  fi
}

sync_repo "middts" "$MIDDTS_REPO_URL"
sync_repo "iot_simulator" "$SIMULATOR_REPO_URL"

docker build -t middts:latest "$REPO_DIR/middts"
docker build -t iot_simulator:latest "$REPO_DIR/iot_simulator"

cat <<EOF > docker-compose.generated.yml
version: '3.8'

services:
EOF

for i in $(seq -w 1 "$SIM_COUNT"); do
cat <<EOF >> docker-compose.generated.yml
  simulator_$i:
    image: iot_simulator:latest
    container_name: simulator_$i
    environment:
      - DEVICE_ID=device_$i
    networks:
      - $NETWORK_NAME

EOF
done

cat <<EOF >> docker-compose.generated.yml
networks:
  $NETWORK_NAME:
    external: true
EOF

docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 ||     docker network create "$NETWORK_NAME"

docker compose -f docker-compose.base.yml -f docker-compose.generated.yml up -d
