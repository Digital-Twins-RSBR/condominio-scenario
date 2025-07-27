#!/bin/bash
set -euo pipefail
LOGFILE="setup.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "###############################################"
echo "🔧 [1/6] Removendo versões conflitantes de Docker"
echo "###############################################"
sudo apt-get remove -y docker docker-engine docker.io docker-compose docker-compose-v2 podman-docker containerd runc containerd.io || true
sudo rm -rf /var/lib/docker /var/lib/containerd

echo ""
echo "###############################################"
echo "🔐 [2/6] Adicionando chave GPG oficial e repositório Docker"
echo "###############################################"
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

UBU_CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
echo "Utilizando codename Ubuntu: $UBU_CODENAME"
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $UBU_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list

if ! sudo apt-get update -y; then
  echo "[ERROR] erro no 'apt update' — verifique $LOGFILE"
  exit 1
fi

echo ""
echo "###############################################"
echo "🧪 [3/6] Instalando Docker Engine e Compose"
echo "###############################################"
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
  echo "[ERROR] falha ao instalar docker-ce ou containerd.io, verifique conflitos"
  exit 1
}

echo ""
echo "🧾 [4/6] Adicionando usuário ao grupo docker (para evitar sudo)"
echo "###############################################"
sudo groupadd -f docker
sudo usermod -aG docker "$USER" || true
echo "Agora reinicie sua sessão para aplicar o grupo docker."

echo ""
echo "###############################################"
echo "📦 [5/6] Clonando e instalando Containernet via Ansible"
echo "###############################################"
if [ ! -d "containernet" ]; then
  git clone https://github.com/containernet/containernet.git
else
  cd containernet && git pull && cd ..
fi
cd containernet
if ! ansible-playbook -i "localhost," -c local ansible/install.yml; then
  echo "[ERROR] falha no Ansible-install — revisar comandos e rede";
  exit 1
fi
cd ..

echo ""
echo "###############################################"
echo "✅ [6/6] Setup concluído com sucesso!"
echo "Veja logs em $LOGFILE"
echo "Use: make setup build-images topo draw"
