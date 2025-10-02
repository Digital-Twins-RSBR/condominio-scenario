#!/bin/bash
echo "[⚠️] Desinstalando ambiente..."

echo "[🧼] Removendo ThingsBoard (se instalado)..."
sudo systemctl stop thingsboard || true
sudo apt remove --purge -y thingsboard* || true
sudo rm -rf /etc/thingsboard /usr/share/thingsboard /var/log/thingsboard /data/thingsboard

echo "[🧼] Limpando Mininet..."
sudo mn -c

echo "[🧼] Removendo pacotes instalados..."
sudo apt remove --purge -y mininet socat docker.io openjdk-11-jdk wget unzip net-tools
sudo apt autoremove -y

echo "[🧹] Limpando repositórios clonados..."
rm -rf middts simulator

echo "[✅] Ambiente limpo com sucesso."
