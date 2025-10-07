#!/bin/sh
set -e
echo "[install-logrotate] Instalando configuração de logrotate para deploy/logs (requer sudo)"
if [ ! -f deploy/logs/logrotate/condominio-scenario ]; then
  echo "[ERRO] deploy/logs/logrotate/condominio-scenario não encontrado"
  exit 1
fi
sudo cp deploy/logs/logrotate/condominio-scenario /etc/logrotate.d/condominio-scenario || {
  echo "[WARN] falha ao copiar; verifique permissões"
  exit 1
}
echo "[install-logrotate] Configuração instalada em /etc/logrotate.d/condominio-scenario"
