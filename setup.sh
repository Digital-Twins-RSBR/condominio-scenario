#!/bin/bash
set -e
LOG="setup.log"
exec 2> >(tee -a "$LOG") # redireciona stderr

echo "###############################################"
echo "🔧 [1/5] Preparando ambiente (APT, GPG e repositórios)"
echo "###############################################"

sudo rm -rf /var/lib/apt/lists/*
sudo apt-get clean
echo "[INFO] Baixando chave GPG do Docker e configurando repositório"
sudo mkdir -p /etc/apt/keyrings
sudo chmod 755 /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "[INFO] Criando sources.list para Docker"
REPO="deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
echo "$REPO" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "[INFO] Atualizando repositórios com apt update"
if ! sudo apt-get update; then
  echo "[ERROR] apt update falhou. Verifique '$LOG' e o content de docker.list"
  exit 1
fi

echo "###############################################"
echo "🐳 [2/5] Instalando Docker Engine e componentes"
echo "###############################################"
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || {
  echo "[ERROR] Instalação do Docker Falhou"
  exit 1
}

echo "🚀 Adicionando usuário '$USER' ao grupo docker"
sudo groupadd -f docker
sudo usermod -aG docker "$USER"

echo "###############################################"
echo "🛠️  [3/5] Instalando outras dependências"
echo "###############################################"
sudo apt-get install -y ansible git python3-pip python3-venv python3-dev make socat net-tools bridge-utils iproute2 tcpdump graphviz xterm unzip curl wget || {
  echo "[ERROR] Erro na instalação de dependências base"
  exit 1
}

echo "###############################################"
echo "⚙️  [4/5] Instalando Containernet via Ansible"
echo "###############################################"
if [ ! -d containernet ]; then
  git clone https://github.com/containernet/containernet.git
else
  cd containernet && git pull && cd ..
fi
cd containernet
if ! ansible-playbook -i "localhost," -c local ansible/install.yml; then
  echo "[ERROR] Falha na instalação via Ansible, veja '$LOG'"
  exit 1
fi
cd ..

echo "###############################################"
echo "✅ [5/5] Setup concluído com sucesso"
echo "###############################################"
echo "✅ Consulte '$LOG' se houver falhas."
echo "🎯 Agora use 'make build-images topo draw' conforme README."
