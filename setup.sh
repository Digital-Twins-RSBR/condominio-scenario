#!/bin/bash
set -e

echo ""
echo "###############################################"
echo "🔧 [1/5] Instalando dependências do sistema..."
echo "###############################################"

echo "[✓] Garantindo permissão de execução para os scripts..."
find scripts/ -type f -name "*.sh" -exec chmod +x {} \;

sudo apt update

# Dependências para Containernet
sudo apt install -y \
    ansible \
    python3-pip \
    python3-venv \
    python3 \
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
echo "✅ [✓] Dependências instaladas com sucesso."
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
    echo "📥 Clonando repositório Containernet (branch padrão)..."
    git clone https://github.com/containernet/containernet.git
else
    echo "✅ Containernet já está clonado. Atualizando..."
    cd containernet && git pull && cd ..
fi

echo "🔧 Compilando e instalando Containernet com make..."
cd containernet
sudo make
cd ..

echo "✅ Containernet instalado com sucesso."


echo ""
echo "###############################################"
echo "🏁 [5/5] Ambiente pronto!"
echo "###############################################"
echo "✅ Todos os componentes foram preparados com sucesso."
echo ""
echo "👉 Agora, use 'sudo python3 topology/topo_qos.py' para iniciar o cenário."
