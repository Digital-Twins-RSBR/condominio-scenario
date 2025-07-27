#!/bin/bash
set -e
LOG="setup.log"
exec > >(tee -a "$LOG") 2>&1

echo "###############################################"
echo "🔧 [1/5] Atualizando apt e instalando dependências básicas"
echo "###############################################"
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update || { echo "[ERROR] apt update falhou"; exit 1; }
sudo apt-get install -y \
  ansible git python3 python3-pip python3-venv make \
  curl wget socat net-tools xterm bridge-utils iproute2 tcpdump \
  python3-dev libffi-dev libssl-dev graphviz docker.io docker-compose || {
    echo "[ERROR] Falha ao instalar pacotes essenciais"; exit 1; }

echo "✅ Dependências instaladas com sucesso."

echo "###############################################"
echo "🧪 [2/5] Ativando Docker e adicionando usuário ao grupo"
echo "###############################################"
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER" || echo "[WARN] não foi possível adicionar usuário ao grupo docker"

echo "✅ Docker pronto."

echo "###############################################"
echo "📦 [3/5] Clonando/Atualizando Containernet"
echo "###############################################"
if [ ! -d containernet ]; then
  git clone https://github.com/containernet/containernet.git
else
  cd containernet && git pull && cd ..
fi

echo "✅ Containernet atualizado."

echo "###############################################"
echo "🩹 [4/5] Instalando Containernet em virtualenv"
echo "###############################################"
cd containernet
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip setuptools wheel
pip install -e . --no-binary :all: || { echo "[ERROR] pip install Containernet falhou"; exit 1; }
deactivate
cd ..

echo "✅ Containernet instalado com sucesso."

echo "###############################################"
echo "🏁 [5/5] Ambiente pronto"
echo "###############################################"
echo "Agora execute: source containernet/venv/bin/activate && sudo -E env PATH=\"\$PATH\" make build-images topo draw"
