#!/bin/bash
set -e

LOG="setup.log"
exec > >(tee -a "$LOG") 2>&1

echo "###############################################"
echo "🔧 [1/4] Atualizando cache APT e Instalando Dependências Básicas"
echo "###############################################"
sudo rm -rf /var/lib/apt/lists/*
sudo apt clean
if ! sudo apt update; then
  echo "[ERROR] 'apt update' falhou. Verifique repositórios e o log em $LOG"
  exit 1
fi
sudo apt install -y ca-certificates curl gnupg lsb-release software-properties-common

echo
echo "###############################################"
echo "🛠️ [2/4] Configurando GPG e repositório Docker"
echo "###############################################"
sudo mkdir -p /etc/apt/keyrings
sudo chmod 755 /etc/apt/keyrings

if curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
else
  echo "[ERROR] Falha ao baixar ou converter chave GPG Docker"
  exit 1
fi

UBUNTU_CODENAME=$(lsb_release -cs)
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $UBUNTU_CODENAME stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

if ! sudo apt update; then
  echo "[ERROR] 'apt update' após configurar Docker failed. Veja $LOG"
  exit 1
fi

echo
echo "###############################################"
echo "🚀 [3/4] Instalando Docker Engine, CLI e Compose"
echo "###############################################"
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo
echo "###############################################"
echo "✅ [4/4] Instalando Containernet via Ansible"
echo "###############################################"
if [ ! -d "containernet" ]; then
  echo "[INFO] clonando Containernet..."
  git clone https://github.com/containernet/containernet.git
else
  echo "[INFO] Containernet já existe. Atualizando..."
  cd containernet && git pull && cd ..
fi

cd containernet
if ! ansible-playbook -i "localhost," -c local ansible/install.yml; then
  echo "[ERROR] Falha na instalação via Ansible do Containernet. Veja $LOG"
  exit 1
fi
cd ..

echo
echo "✅ Setup concluído com sucesso! Consulte $LOG para detalhes."
