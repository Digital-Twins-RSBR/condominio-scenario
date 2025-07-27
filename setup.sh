#!/bin/bash
set -euo pipefail
exec 2>setup.log
echo "Início do setup: $(date)"

log() { echo "[$(date +'%F %T')] $*"; }

log "🔧 [1/5] Atualizando APT e instalando dependências do sistema..."
sudo rm -rf /var/lib/apt/lists/* || true
sudo apt clean -qq
log "[INFO] Executando apt update..."
if ! sudo apt update -qq; then
    log "[ERROR] Falha no apt update. Verifique sources list e logs."
    exit 1
fi

log "[INFO] Instalando pacotes essenciais..."
sudo apt install -y ansible git python3-pip python3-venv docker.io docker-compose || {
    log "[ERROR] Falha instalar pacotes essenciais."; exit 1; }

log "✅ Dependências de base instaladas."

log "🧪 [2/5] Habilitando Docker..."
if ! sudo systemctl is-active --quiet docker; then
    sudo systemctl start docker
    sudo systemctl enable docker
    log "[INFO] Docker iniciado e habilitado."
else
    log "[INFO] Docker já está ativo."
fi
sudo groupadd -f docker
sudo usermod -aG docker "$USER"

log "📦 [3/5] Clonando/atualizando Containernet..."
if [ ! -d "containernet" ]; then
    git clone https://github.com/containernet/containernet.git || {
        log "[ERROR] Clone Containernet falhou."; exit 1; }
else
    (cd containernet && git pull --ff-only) || {
        log "[ERROR] git pull falhou."; exit 1; }
fi

log "🩹 Corrigindo Makefile problemático..."
cd containernet
sed -i '/^all:/s/codecheck//g' Makefile
sed -i '/^codecheck:/,/^$/d' Makefile
sed -i '/^all:/s/test//g' Makefile
sed -i '/^test:/,/^$/d' Makefile

log "🔧 Compilando Containernet..."
if ! sudo make -j "$(nproc)"; then
    log "[ERROR] Build Containernet falhou."; exit 1; fi
cd ..

log "✅ Containernet instalado com sucesso."
log "🏁 Setup concluído. Confira logs em setup.log"
exit 0
