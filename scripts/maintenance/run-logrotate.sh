#!/bin/sh
set -e
echo "[run-logrotate] Forçando execução imediata do logrotate (requer sudo)"
if [ ! -f /etc/logrotate.d/condominio-scenario ]; then
  echo "[WARN] /etc/logrotate.d/condominio-scenario não encontrado. Rode 'install-logrotate.sh' primeiro"
fi
sudo logrotate -f /etc/logrotate.d/condominio-scenario || echo "[WARN] logrotate retornou erro (verifique /var/log/messages ou syslog)"
echo "[run-logrotate] Execução concluída (ou falhou com aviso)."
