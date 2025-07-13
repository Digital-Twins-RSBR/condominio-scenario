#!/bin/bash
set -e


# Instala dependências do sistema
echo "[✓] Instalando dependências do sistema: Python, Make, Git, Docker, Docker Compose, Mininet, Socat..."
sudo apt update
sudo apt install -y python3 python3-pip make git docker.io docker-compose mininet socat net-tools openjdk-11-jdk unzip wget

# Carrega variáveis do .env
ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
    echo "Carregando variáveis de $ENV_FILE..."
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo "Arquivo .env não encontrado. Abortando."
    exit 1
fi

# Executa setup e install do Makefile
echo "[✓] Executando make setup..."
make setup
echo "[✓] Executando make install..."
make install

echo "[✓] Ambiente preparado. Siga os próximos passos do README para subir o cenário."
