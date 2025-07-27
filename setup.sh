#!/bin/bash
set -e

echo "🔧 Instalando dependências do sistema..."
sudo apt update
sudo apt install -y ansible git python3-pip python3-venv docker.io docker-compose socat net-tools openjdk-11-jdk curl wget bridge-utils iproute2 tcpdump python3-dev libffi-dev libssl-dev graphviz xterm

echo "🧪 Verificando Docker..."
sudo systemctl enable --now docker

echo "📦 Carregando variáveis do .env..."
if [ -f .env ]; then export $(grep -v '^#' .env | xargs); else echo ".env não encontrado"; exit 1; fi

echo "📥 Clonando ou atualizando Containernet..."
if [ ! -d containernet ]; then
  git clone https://github.com/containernet/containernet.git
else
  cd containernet && git pull && cd ..
fi

echo "🔗 Criando link python e removendo targets problemáticos..."
cd containernet
sudo ln -sf /usr/bin/python3 /usr/bin/python
sed -i '/^all:/s/codecheck//; /^codecheck:/,/^$/d' Makefile
sed -i '/^all:/s/test//; /^test:/,/^$/d' Makefile

echo "🛠️ Compilando Containernet..."
sudo make && cd ..

echo "✅ Setup concluído. Use 'make setup build-images topo draw'."
