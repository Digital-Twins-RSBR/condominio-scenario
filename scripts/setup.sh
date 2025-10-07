#!/bin/bash
set -e

LOG="scripts/setup.log"
exec > >(tee -a "$LOG") 2>&1

# Carregar variáveis do .env
set -a
[ -f .env ] && . .env
set +a

echo "###############################################"
echo "🔧 [1/7] Atualizando apt e instalando dependências básicas"
echo "###############################################"
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update || { echo "[ERROR] apt update falhou"; exit 1; }
sudo apt-get install -y \
  ansible git python3 python3-pip python3-venv make postgresql-client \
  curl wget socat net-tools xterm bridge-utils iproute2 tcpdump \
  python3-dev libffi-dev libssl-dev graphviz docker.io docker-compose || {
    echo "[ERROR] Falha ao instalar pacotes essenciais"; exit 1; }

echo "✅ Dependências instaladas com sucesso."

echo "###############################################"
echo "🧪 [2/7] Ativando Docker e adicionando usuário ao grupo"
echo "###############################################"
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER" || echo "[WARN] não foi possível adicionar usuário ao grupo docker"

echo "✅ Docker pronto."

echo "###############################################"
echo "🛠️ [3/7] Subindo ThingsBoard no Containernet"
echo "###############################################"

docker volume create tb_db_data
docker volume create tb_assets
docker volume create tb_logs

echo "###############################################"
echo "📦 [4/7] Clonando/Atualizando Containernet, Middts e Simulator"
echo "###############################################"

# Containernet
if [ ! -d services/containernet ]; then
  git clone https://github.com/containernet/containernet.git services/containernet
else
  cd services/containernet && git pull && cd -
fi

# Middts
if [ ! -d services/middleware-dt ]; then
  git clone "$MIDDTS_REPO_URL" services/middleware-dt
else
  cd services/middleware-dt && git pull && cd -
fi

# Simulator
if [ ! -d services/iot_simulator ]; then
  git clone "$SIMULATOR_REPO_URL" services/iot_simulator
else
  cd services/iot_simulator && git pull && cd -
fi

echo "✅ Containernet atualizado."

echo "###############################################"
echo "🩹 [5/7] Instalando Containernet em virtualenv (services/containernet/venv)"
echo "###############################################"
cd services/containernet
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip setuptools wheel
pip install -e . || { echo "[ERROR] pip install Containernet falhou"; exit 1; }
deactivate
cd -
echo "✅ Containernet instalado com sucesso."

echo "###############################################"
echo "📦 [6/7] Criando pastas de montagem para os containers"
echo "###############################################"
mkdir -p /var/lib/tb-data /var/log/tb /var/lib/pg-data
chmod 777 /var/lib/tb-data /var/log/tb /var/lib/pg-data

echo "###############################################"
echo "📚 [6.5/7] Instalando dependências de documentação e relatórios (requirements/local.txt)"
echo "###############################################"
if [ -f requirements/local.txt ]; then
  # Use a local virtualenv to avoid installing into system-managed Python (PEP 668)
  DOCS_VENV=".venv-docs"
  if [ ! -d "$DOCS_VENV" ]; then
    python3 -m venv "$DOCS_VENV" || { echo "[WARN] falha ao criar virtualenv $DOCS_VENV"; }
  fi
  # Activate and install requirements without sudo
  # shellcheck disable=SC1091
  . "$DOCS_VENV/bin/activate"
  pip install --upgrade pip setuptools wheel
  pip install -r requirements/local.txt || echo "[WARN] Falha ao instalar requirements-docs (ignore se já estiverem instalados)"
  deactivate
  echo "✅ Installed docs requirements into $DOCS_VENV"
else
  echo "[WARN] requirements/local.txt não encontrado, pulando"
fi


echo "###############################################"
echo "🏁 [7/7] Ambiente pronto"
echo "###############################################"
echo "Agora execute: source containernet/venv/bin/activate && sudo -E env PATH=\"\$PATH\" make build-images topo draw"
