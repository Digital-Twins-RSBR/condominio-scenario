#!/bin/bash
set -euo pipefail

LOGFILE="setup.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "###############################################"
echo "🔧 [1/6] Atualizando cache APT e instalando dependências básicas"
echo "###############################################"
sudo rm -rf /var/lib/apt/lists/* || true
sudo apt clean
if ! sudo apt update; then
    echo "[ERROR] apt update falhou. Verifique fontes APT e chaves GPG."
    exit 1
fi
sudo apt install -y \
  ansible git python3-pip python3-venv make curl wget \
  docker.io docker-compose-plugin socat net-tools \
  openjdk-11-jdk unzip bridge-utils iproute2 tcpdump \
  python3-setuptools python3-dev libffi-dev libssl-dev \
  graphviz xterm

echo "✅ Dependências básicas instaladas com sucesso."

echo
echo "###############################################"
echo "🧪 [2/6] Garantindo Docker ativo"
echo "###############################################"
sudo systemctl enable docker || echo "[WARN] não foi possível habilitar Docker"
sudo systemctl start docker || echo "[WARN] não foi possível iniciar Docker"

echo
echo "###############################################"
echo "📦 [3/6] Carregando variáveis do .env"
echo "###############################################"
if [ -f ".env" ]; then
  echo "[INFO] Carregando .env"
  set -a; source .env; set +a
else
  echo "[ERROR] .env não encontrado. Abortando."
  exit 1
fi

echo
echo "###############################################"
echo "🛠️  [4/6] Clonando ou atualizando Containernet"
echo "###############################################"
if [ ! -d "containernet" ]; then
  git clone https://github.com/containernet/containernet.git || {
    echo "[ERROR] Falha ao clonar Containernet"; exit 1; }
else
  echo "[INFO] Atualizando Containernet"
  cd containernet && git pull || { echo "[ERROR] git pull falhou"; exit 1; } && cd ..
fi

echo
echo "###############################################"
echo "⚙️  [5/6] Instalando Containernet via Ansible"
echo "###############################################"
cd containernet
# ajustar playbook para ignorar downloads existentes e evitar conflito de diretórios
if ! sudo PYTHON=python3 ansible-playbook -i "localhost," -c local ansible/install.yml; then
  echo "[ERROR] Ansible falhou na instalação do Containernet."
  echo "Verifique o conteúdo de $LOGFILE e os conflitos em pastas como 'openflow'."
  exit 1
fi
cd ..

echo
echo "###############################################"
echo "✅ [6/6] Setup concluído com sucesso!"
echo "Veja o log completo em $LOGFILE"
echo "Use 'make setup build-images topo draw' ou 'make topo' para iniciar."
