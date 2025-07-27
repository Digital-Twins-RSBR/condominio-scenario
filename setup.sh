#!/usr/bin/env bash
set -euo pipefail

LOGFILE="setup.log"
exec > >(tee -i "$LOGFILE") 2>&1

echo "###############################################"
echo "🔧 [1/6] Atualizando cache apt e instalando pacotes básicos"
echo "###############################################"

sudo rm -rf /var/lib/apt/lists/* || true
sudo apt clean
sudo apt update || { echo "[ERROR] apt update falhou"; exit 1; }
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common

echo ""
echo "###############################################"
echo "🔑 [2/6] Adicionando chave GPG oficial do Docker"
echo "###############################################"

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
 $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update || { echo "[ERROR] apt update após adicionar Docker repo falhou"; exit 1; }

echo ""
echo "###############################################"
echo "🐳 [3/6] Instalando Docker Engine + Compose Plugin"
echo "###############################################"

sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
    echo "[ERROR] instalação Docker falhou"; exit 1;
}

sudo systemctl enable --now docker
echo "[INFO] Docker instalado e ativo: $(docker --version)"

echo ""
echo "###############################################"
echo "👥 [4/6] Configurando grupo docker para acesso sem sudo"
echo "###############################################"

sudo groupadd -f docker
sudo usermod -aG docker "$USER" || true
echo "[INFO] Usuário '$USER' adicionado ao grupo 'docker'. Você pode precisar relogar."

echo ""
echo "###############################################"
echo "📦 [5/6] Instalando dependências gerais"
echo "###############################################"

sudo apt install -y ansible git python3-pip python3-venv make
echo "[INFO] Dependências gerais instaladas."

echo ""
echo "###############################################"
echo "🛠️  [6/6] Clonando/Atualizando Containernet e executando Ansible"
echo "###############################################"

if [ ! -d "containernet" ]; then
    echo "[INFO] Clonando Containernet..."
    git clone https://github.com/containernet/containernet.git
else
    echo "[INFO] Diretório containernet já existe, atualizando..."
    cd containernet && git pull && cd ..
fi

echo "[INFO] Executando Ansible playbook de instalação"
cd containernet
ansible-playbook -i "localhost," -c local ansible/install.yml -v || {
    echo "[ERROR] Ansible falhou. Veja '$LOGFILE' para detalhes."; exit 1;
}
cd ..

echo ""
echo "✅ Setup concluído com sucesso!"
echo "📄 Logs em '$LOGFILE'"
echo "➡️ Use 'make setup build-images topo draw' ou conforme README"

