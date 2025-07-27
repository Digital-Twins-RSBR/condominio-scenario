#!/bin/bash
set -euo pipefail

LOGFILE="setup.log"
echo "" > "$LOGFILE"

log() { echo "[INFO] $*" | tee -a "$LOGFILE"; }
error_exit() { echo "[ERROR] $*" | tee -a "$LOGFILE"; exit 1; }

echo "###############################################"
echo "🔧 [1/6] Atualizando APT e instalando dependências básicas"
echo "###############################################"
log "Limpando listas antigas e cache APT..."
sudo rm -rf /var/lib/apt/lists/* || true
sudo apt-get clean
log "Atualizando repositórios..."
if ! sudo apt-get update -o Acquire::AllowInsecureRepositories=false; then
    error_exit "apt update falhou. Verifique as fontes APT."
fi

log "Instalando pacotes base..."
sudo apt-get install -y ca-certificates curl gnupg lsb-release software-properties-common || error_exit "Falha na instalação dos pacotes base."

echo ""
echo "###############################################"
echo "🛡️ [2/6] Adicionando chave GPG oficial do Docker"
echo "###############################################"
log "Criando diretório /etc/apt/keyrings..."
sudo mkdir -p /etc/apt/keyrings
log "Baixando GPG key..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || error_exit "Falha ao baixar ou converter a chave GPG do Docker."
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo ""
echo "###############################################"
echo "📦 [3/6] Atualizando repositório Docker"
echo "###############################################"
REPO_LINE="deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
log "Escrevendo em /etc/apt/sources.list.d/docker.list: $REPO_LINE"
echo "$REPO_LINE" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo ""
echo "###############################################"
echo "⚙️ [4/6] Atualizando APT novamente com chave Docker"
echo "###############################################"
if ! sudo apt-get update ; then
    error_exit "Atualização pós-inclusão do repositório Docker falhou. Veja o logfile."
fi

echo ""
echo "###############################################"
echo "🐳 [5/6] Instalando Docker Engine e Compose Plugin"
echo "###############################################"
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || error_exit "Falha ao instalar Docker."

log "Garantindo que o Docker esteja ativo..."
sudo systemctl enable docker --now

echo ""
echo "###############################################"
echo "✅ [6/6] Dependências instaladas com sucesso"
echo "###############################################"

log "Docker instalado e configurado corretamente."
log "Verifique executando: docker run hello-world"

echo "Instalação concluída. Logs gravados em $LOGFILE"
