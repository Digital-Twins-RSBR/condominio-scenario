#!/bin/bash
set -e
LOGFILE="setup.log"

exec > >(tee -a "${LOGFILE}") 2>&1

echo "###############################################"
echo "🔧 [1/5] Instalando dependências do sistema..."
echo "###############################################"

# Atualiza apt e remove possíveis conflitos anteriores de Docker/containerd/runc
sudo rm -rf /var/lib/apt/lists/* ||:
sudo apt-get clean
echo "[INFO] Atualizando cache APT..."
sudo apt-get update

echo "[INFO] Removendo pacotes conflitantes (containerd, runc, docker.*)..."
sudo apt-get remove -y containerd runc docker docker.io docker-compose podman-docker || true

echo "[INFO] Instalando dependências base..."
sudo apt-get install -y \
    ansible \
    python3-pip \
    python3-venv \
    python3 \
    make \
    git \
    curl \
    wget \
    bridge-utils \
    iproute2 \
    socat \
    net-tools \
    openjdk-11-jdk \
    unzip \
    graphviz \
    xterm

echo "✅ Dependências base instaladas."

echo "###############################################"
echo "🧪 [2/5] Instalando Docker (Engine e Compose)..."
echo "###############################################"
# Configura repositório oficial do Docker
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.asc
source /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
echo "[INFO] Instalando Docker Engine e Compose plugin..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

echo "[INFO] Garantindo Docker ativo..."
sudo systemctl enable docker
sudo systemctl start docker

sudo groupadd -f docker
sudo usermod -aG docker "$USER" || echo "[WARN] Não pôde adicionar usuário ao grupo docker (talvez root)."

echo "✅ Docker instalado e em execução."

echo "###############################################"
echo "📦 [3/5] Clonando e instalando Containernet"
echo "###############################################"
if [ ! -d "containernet" ]; then
    echo "[INFO] Clonando Containernet..."
    git clone https://github.com/containernet/containernet.git
else
    echo "[INFO] Atualizando Containernet..."
    cd containernet && git pull && cd ..
fi

echo "[INFO] Executando playbook Ansible para instalação..."
cd containernet
sudo ansible-playbook -i "localhost," -c local ansible/install.yml || {
    echo "[ERROR] Falha na instalação via Ansible. Consulte ${LOGFILE}."
    exit 1
}
cd ..

echo "✅ Containernet instalado com sucesso."

echo "###############################################"
echo "⚙️ [4/5] Construindo imagens de MidDiTS e Simulator"
echo "###############################################"
if [ -d "middts" ]; then
    (cd middts && docker build -t middts:latest .) || {
        echo "[ERROR] Falha ao buildar imagem MidDiTS."
        exit 1
    }
else
    echo "[WARN] Pasta 'middts' não encontrada. Pule create image."
fi
if [ -d "simulator" ]; then
    (cd simulator && docker build -t iot_simulator:latest .) || {
        echo "[ERROR] Falha ao buildar imagem iot_simulator."
        exit 1
    }
else
    echo "[WARN] Pasta 'simulator' não encontrada."
fi
echo "✅ Images construídas."

echo "###############################################"
echo "🏁 [5/5] Setup concluído com sucesso!"
echo "➤ Use 'make topo' para iniciar a topologia Containernet."
echo "➤ Consulte ${LOGFILE} para logs completos de execução."
