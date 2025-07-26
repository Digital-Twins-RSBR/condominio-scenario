#!/bin/bash

# Caminho absoluto do seu projeto
PROJECT_PATH="/var/condominio-scenario"

# Diretório a montar (por exemplo, scripts)
SHARED_DIR="$PROJECT_PATH/scripts"

# Lista de hosts a montar (tb, middts, sim_001 a sim_100)
HOSTS="tb middts"
for i in $(seq -w 1 100); do
    HOSTS="$HOSTS sim_$i"
done

echo "[✓] Montando '$SHARED_DIR' como /mnt/scripts em cada host..."

for host in $HOSTS; do
    if ip netns identify $host > /dev/null 2>&1; then
        echo "[→] Host: $host"
        sudo ip netns exec $host mkdir -p /mnt/scripts
        sudo mount --bind "$SHARED_DIR" "/var/run/netns/$host/mnt/scripts"
    else
        echo "[!] Namespace '$host' não encontrado. Ignorando..."
    fi
done

echo "[✓] Diretório montado com sucesso!"
