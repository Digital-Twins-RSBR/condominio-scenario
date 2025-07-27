#!/bin/bash
set -e
LOGFILE="setup.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "###############################################"
echo "🔧 [1/6] Atualizando apt e instalando dependências base"
echo "###############################################"
sudo rm -rf /var/lib/apt/lists/*
sudo apt clean
if ! sudo apt update; then
  echo "[ERROR] apt update falhou — verifique repositórios" >&2
  exit 1
fi
sudo apt install -y ansible python3-pip python3-venv make git curl wget \
  docker.io containerd.io docker-compose-plugin socat net-tools bridge-utils \
  iproute2 tcpdump python3-dev libffi-dev libssl-dev graphviz xterm unzip

echo "###############################################"
echo "🧪 [2/6] Verificando Docker e permissões"
echo "###############################################"
if ! sudo systemctl is-active --quiet docker; then
  echo "[INFO] Ativando Docker..."
  sudo systemctl start docker && sudo systemctl enable docker
fi
sudo groupadd -f docker
sudo usermod -aG docker "$USER"

echo "###############################################"
echo "📦 [3/6] Gerenciando repositórios APT problemáticos"
echo "###############################################"
# Corrige fontes problemáticas do Docker
if grep -R "duplicate" /etc/apt/sources.list.d; then
  sudo rm /etc/apt/sources.list.d/docker*.list
  echo "[INFO] Removidos .list conflitantes do Docker"
fi

echo "###############################################"
echo "🛠️  [4/6] Instalando ou atualizando Containernet via Ansible"
echo "###############################################"
if [ ! -d "containernet" ]; then
  echo "[INFO] Clonando Containernet..."
  git clone https://github.com/containernet/containernet.git
else
  echo "[INFO] Atualizando Containernet existente..."
  cd containernet && git pull && cd ..
fi

cd containernet

# Limpando pasta openflow para evitar conflitos
if [ -d "openflow" ]; then
  echo "[WARN] Diretório 'openflow' já existe — removendo para rebuild"
  rm -rf openflow
fi

echo "[INFO] Executando playbook de instalação"
if ! sudo ansible-playbook -i "localhost," -c local ansible/install.yml; then
  echo "[ERROR] Falha na instalação pelo Ansible — verifique $LOGFILE" >&2
  exit 1
fi

cd ..

echo "###############################################"
echo "✅ [6/6] Setup concluído com sucesso!"
echo "Log completo em: $LOGFILE"
echo "Use: make setup build-images topo draw"
