#!/bin/bash
set -e

echo ""
echo "###############################################"
echo "🔧 [1/5] Instalando dependências do sistema..."
echo "###############################################"

echo "[✓] Garantindo permissão de execução para os scripts..."
find scripts/ -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

sudo apt update

# Dependências para Containernet e Docker
sudo apt install -y \
    ansible \
    python3-pip \
    python3-venv \
    python3 \
    python3-dev \
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
    libffi-dev \
    libssl-dev \
    graphviz \
    xterm \
    python3-networkx \
    python3-matplotlib

echo ""
echo "✅ Dependências instaladas com sucesso."

echo ""
echo "###############################################"
echo "🧪 Verificando Docker..."
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
echo "📦 [2/5] Carregando variáveis do .env (se existir)..."
echo "###############################################"

ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
    echo "🗂️  Carregando variáveis..."
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo "⚠️  Arquivo .env não encontrado. Prosseguindo com valores padrão."
fi

echo ""
echo "###############################################"
echo "🛠️  [3/5] Clonando e Instalando Containernet..."
echo "###############################################"

if [ ! -d "containernet" ]; then
    echo "📥 Clonando repositório Containernet..."
    git clone https://github.com/containernet/containernet.git
else
    echo "🔄 Atualizando Containernet..."
    cd containernet && git pull && cd ..
fi

# Symlink python → python3 (para evitar erros de script antigos)
echo "🔗 Garantindo /usr/bin/python → python3"
if ! [ -x /usr/bin/python ]; then
    sudo ln -s /usr/bin/python3 /usr/bin/python
fi

# Remover targets problemáticos do Makefile
cd containernet
echo "🧹 Limpando Makefile de targets problemáticos..."
sed -i '/^all:/s/codecheck test//g' Makefile
sed -i '/^codecheck:/,/^$/d' Makefile
sed -i '/^test:/,/^$/d' Makefile

echo "🔧 Compilando Containernet..."
sudo make
cd ..

echo ""
echo "✅ Ambiente pronto! Agora rode:"
echo "👉 make build-images"
echo "👉 make topo"
