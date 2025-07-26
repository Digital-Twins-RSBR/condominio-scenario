#!/bin/bash

# Caminho absoluto do seu projeto
PROJECT_PATH="/var/condominio-scenario"

# Diretório a montar (por exemplo, scripts)
SHARED_DIR="$PROJECT_PATH/scripts"

# Nome da screen do Mininet
MININET_SCREEN="mininet-session"

# Lista de hosts a montar (ex: tb, middts, sim_001 a sim_100)
HOSTS="tb middts"
for i in $(seq -w 1 100); do
    HOSTS="$HOSTS sim_$i"
done

echo "[✓] Montando '$SHARED_DIR' como /mnt/scripts em cada host..."

for host in $HOSTS; do
    sudo ip netns exec $host mkdir -p /mnt/scripts
    sudo mount --bind "$SHARED_DIR" "/var/run/netns/$host/mnt/scripts"
done

echo "[✓] Diretório montado com sucesso!"
