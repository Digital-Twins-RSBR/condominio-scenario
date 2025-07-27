#!/bin/bash
set -euo pipefail

LOGFILE="setup.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "###############################################"
echo "🔧 [1/5] Atualizando APT e instalando dependências..."
echo "###############################################"
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get clean
echo "[INFO] Atualizando cache APT..."
sudo apt-get update || { echo "[ERROR] 'apt update' falhou."; exit 1; }
echo "[INFO] Instalando ferramentas base..."
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common || { echo "[ERROR] falha ao instalar ferramentas base."; exit 1; }

echo ""
echo "###############################################"
echo "📦 [2/5] (Re)configurando repositório Docker..."
echo "###############################################"
sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
echo "[INFO] Baixando chave GPG Docker..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || { echo "[ERROR] falha ao baixar chave GPG Docker."; exit 1; }
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "[INFO] Adicionando repositório Docker para $(lsb_release -cs)..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "[INFO] Atualizando APT com repo Docker..."
sudo apt-get update || { echo "[ERROR] 'apt update' falhou após adicionar Docker repo."; exit 1; }

echo "[INFO] Instalando Docker Engine..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || { echo "[ERROR] falha na instalação do Docker."; exit 1; }

echo ""
echo "###############################################"
echo "🧪 [3/5] Verificando serviço Docker..."
echo "###############################################"
sudo systemctl enable docker
sudo systemctl start docker
sleep 2
if ! sudo systemctl is-active --quiet docker; then
  echo "[ERROR] Docker não está ativo."; exit 1
fi
echo "[INFO] Docker está funcionando (teste 'hello-world')..."
sudo docker run --rm hello-world >/dev/null 2>&1 && echo "[INFO] Docker OK" || { echo "[ERROR] teste 'hello-world' falhou."; exit 1; }

echo ""
echo "###############################################"
echo "📥 [4/5] Instalando Containernet via Ansible + pip3..."
echo "###############################################"

if [ ! -d "containernet" ]; then
  echo "[INFO] Clonando Containernet..."
  git clone https://github.com/containernet/containernet.git || { echo "[ERROR] clone Containernet falhou."; exit 1; }
else
  echo "[INFO] Atualizando Containernet (git pull)..."
  cd containernet && git pull || { echo "[ERROR] git pull falhou."; exit 1; } && cd ..
fi

echo "[INFO] Executando playbook Ansible..."
cd containernet
ANSIBLE_PYTHON_INTERPRETER=$(which python3) sudo ansible-playbook -i "localhost," -c local ansible/install.yml \
  || { echo "[ERROR] ansible-playbook falhou. Consulte $LOGFILE"; exit 1; }

echo "[INFO] Instalando Containernet no pip (virtualenv)..."
python3 -m venv venv_cn || { echo "[ERROR] criação virtualenv falhou."; exit 1; }
source venv_cn/bin/activate
pip install --no-binary :all: . || { echo "[ERROR] pip install containernet falhou."; deactivate; exit 1; }
deactivate
cd ..

echo ""
echo "###############################################"
echo "✅ [5/5] Setup concluído com sucesso!"
echo "###############################################"
echo "✅ Veja logs em '$LOGFILE'."
echo ""
echo "👉 Agora rode usando: make setup build-images topo draw"
