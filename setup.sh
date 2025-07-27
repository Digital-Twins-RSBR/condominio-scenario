#!/bin/bash
set -euo pipefail
LOGFILE="setup.log"

exec > >(tee -a "$LOGFILE") 2>&1

echo "###############################################"
echo "🔧 [1/6] Atualizando cache apt e instalando dependências básicas"
echo "###############################################"
sudo rm -rf /var/lib/apt/lists/*
sudo apt clean
if ! sudo apt update; then
  echo "[ERROR] apt update falhou" >&2
  exit 1
fi
sudo apt install -y ansible git curl gnupg lsb-release ca-certificates make python3-pip python3-venv docker-ce docker-ce-cli containerd.io docker-compose-plugin

echo ""
echo "✅ [1/6] Dependências instaladas."

echo "###############################################"
echo "🔐 [2/6] Corrigindo chave GPG do Docker (PUBKEY: 7EA0A9C3F273FCD8)"
echo "###############################################"
sudo mkdir -p /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg || echo "[WARN] permissão do keyring Docker não pôde ser ajustada"

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "Atualizando repositórios com a nova chave..."
if ! sudo apt update; then
  echo "[ERROR] apt update ainda falha após inserir chave Docker" >&2
  exit 1
fi

echo "✅ [2/6] Repositório Docker adicionado com sucesso."

echo "###############################################"
echo "📦 [3/6] Instalando Docker Engine & Compose plugin"
echo "###############################################"
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
echo "✅ [3/6] Docker instalado e ativo."

echo "###############################################"
echo "⚙️  [4/6] Clonando/atualizando Containernet via Ansible"
echo "###############################################"
if [ ! -d "containernet" ]; then
  echo "[INFO] clonando containernet..."
  git clone https://github.com/containernet/containernet.git
else
  echo "[INFO] atualizando containernet..."
  cd containernet && git pull && cd ..
fi

echo "[INFO] executando Ansible playbook..."
cd containernet
ansible-playbook -i "localhost," -c local ansible/install.yml || {
  echo "[ERROR] Ansible falhou ao instalar Containernet" >&2
  exit 1
}
cd ..

echo "✅ [4/6] Containernet instalado com sucesso."

echo "###############################################"
echo "🐳 [5/6] Construindo imagens MiddTS e IoT Simulator"
echo "###############################################"
docker build -t middts:latest ./middts || { echo "[ERROR] build MiddTS falhou"; exit 1; }
docker build -t iot_simulator:latest ./simulator || { echo "[ERROR] build Simulator falhou"; exit 1; }
echo "✅ [5/6] Imagens construídas."

echo "###############################################"
echo "🚀 [6/6] Setup finalizado com sucesso!"
echo "###############################################"
echo "Para continuar: use 'make topo' para iniciar a topologia com Containernet."
echo "Logs completos: $LOGFILE"
