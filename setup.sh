#!/bin/bash
set -e

echo ""
echo "###############################################"
echo "🔧 [1/5] Instalando dependências do sistema..."
echo "###############################################"

sudo apt update

# Pacotes essenciais para Mininet + Docker + Python + Git + etc
sudo apt install -y \
    python3 \
    python3-pip \
    make \
    git \
    docker.io \
    docker-compose \
    mininet \
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
    libssl-dev

echo ""
echo "✅ [✓] Dependências instaladas com sucesso."
echo ""

# Verifica se Docker está rodando
echo "🧪 Verificando se o Docker está em execução..."
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
echo "📁 [3/5] Clonando ou atualizando repositórios..."
echo "###############################################"

make setup

echo ""
echo "###############################################"
echo "⚙️  [4/5] Instalando ambiente local..."
echo "###############################################"

make install

echo ""
echo "###############################################"
echo "🏁 [5/5] Ambiente pronto!"
echo "###############################################"
echo "✅ Todos os componentes foram preparados com sucesso."
echo ""
echo "👉 Agora, siga os próximos passos do README para iniciar o cenário."
