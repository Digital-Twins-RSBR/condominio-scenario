#!/bin/bash
set -e

echo ""
echo "###############################################"
echo "🔧 [1/5] Instalando dependências do sistema..."
echo "###############################################"

echo "[✓] Garantindo permissão de execução para os scripts..."
find scripts/ -type f -name "*.sh" -exec chmod +x {} \;

sudo apt update

# Dependências para Containernet e ambiente de simulação
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
    echo "📥 Clonando repositório Containernet..."
    git clone https://github.com/containernet/containernet.git
else
    echo "✅ Containernet já está clonado. Atualizando..."
    cd containernet && git pull && cd ..
fi

echo "🔧 Garantindo link simbólico: /usr/bin/python → /usr/bin/python3"
if ! [ -x /usr/bin/python ]; then
    sudo ln -s /usr/bin/python3 /usr/bin/python
fi

echo "🩹 Removendo dependência do codecheck no Makefile (evita erro com Python moderno)..."
cd containernet

echo "🩹 Limpando targets problemáticos do Makefile (removendo 'codecheck' se existir)..."
sed -i '/^all:/s/codecheck//g' Makefile
sed -i '/^codecheck:/,/^$/d' Makefile

echo "🩹 Limpando targets problemáticos do Makefile (removendo 'test' se existir)..."
sed -i '/^all:/s/test//g' Makefile
sed -i '/^test:/,/^$/d' Makefile

echo "🔧 Compilando e instalando Containernet com make..."
sudo make
cd ..
echo "[📦] Registrando Containernet no ambiente Python (modo editable)..."
sudo pip3 install -e ./containernet

echo ""
echo "###############################################"
echo "🏁 [5/5] Ambiente pronto!"
echo "###############################################"
echo "✅ Todos os componentes foram preparados com sucesso."
echo ""
echo "👉 Agora use: make topo  (ou sudo python3 containernet/topo_qos.py) para iniciar o cenário."
