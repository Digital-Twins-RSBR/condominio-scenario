#!/bin/bash
set -e

echo ""
echo "###############################################"
echo "🔧 [1/5] Instalando dependências do sistema..."
echo "###############################################"

echo "[✓] Garantindo permissão de execução para os scripts..."
find scripts/ -type f -name "*.sh" -exec chmod +x {} \;

sudo apt update

# Dependências para Containernet, Docker e ferramentas úteis
sudo apt install -y \
    ansible \
    python3 \
    python3-pip \
    python3-venv \
    make \
    git \
    docker.io \
    docker-compose \
    socat \
    net-tools \
    openjdk-11-jdk \
    unzip \
    curl \
    wget \
    bridge-utils \
    iproute2 \
    tcpdump \
    python3-setuptools \
    python3-dev \
    libffi-dev \
    libssl-dev \
    graphviz \
    xterm

echo ""
echo "✅ Dependências instaladas com sucesso."
echo ""

echo ""
echo "###############################################"
echo "🧪 Verificando se o Docker está em execução..."
echo "###############################################"

if ! sudo systemctl is-active --quiet docker; then
    echo "🚀 Iniciando Docker..."
    sudo systemctl start docker
    sudo systemctl enable docker
else
    echo "✅ Docker já está em execução."
fi

echo ""
echo "###############################################"
echo "📦 [2/5] Carregando variáveis do arquivo .env..."
echo "###############################################"

ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
    echo "🗂️  Carregando variáveis de $ENV_FILE..."
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo "❌ Arquivo .env não encontrado. Abortando."
    exit 1
fi

echo ""
echo "###############################################"
echo "🛠️  [3/5] Instalando Containernet..."
echo "###############################################"

if [ ! -d "containernet" ]; then
    echo "📥 Clonando repositório Containernet..."
    git clone https://github.com/containernet/containernet.git
    cd containernet
    echo "🔁 Alternando para a branch legacy..."
    git checkout legacy
    cd ..
fi

echo "🔧 Instalando Containernet (branch legacy)..."
cd containernet
sudo ./install.sh
cd ..

echo ""
echo "###############################################"
echo "🏁 [5/5] Ambiente pronto!"
echo "###############################################"
echo "✅ Todos os componentes foram preparados com sucesso."
echo ""
echo "👉 Agora, use 'make topo' ou 'make topo-qos' para iniciar o cenário com Containernet."
