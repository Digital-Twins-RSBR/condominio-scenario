#!/bin/bash

# Script para aplicar configurações URLLC otimizadas
# Reduz timeouts e batch delays para latência <1ms

echo "🚀 Aplicando configurações URLLC..."

# Aguardar ThingsBoard estar rodando
echo "⏳ Aguardando ThingsBoard inicializar..."
while ! sudo docker exec mn.tb pgrep -f thingsboard > /dev/null 2>&1; do
    sleep 2
done
sleep 10  # Tempo adicional para garantir inicialização completa

echo "🔧 Modificando CLIENT_SIDE_RPC_TIMEOUT de 60s para 1s..."
sudo docker exec mn.tb sed -i 's/CLIENT_SIDE_RPC_TIMEOUT: 60000/CLIENT_SIDE_RPC_TIMEOUT: 1000/g' /usr/share/thingsboard/conf/thingsboard.yml

echo "🔧 Modificando SQL_TS_BATCH_MAX_DELAY_MS de 100ms para 10ms..."
sudo docker exec mn.tb sed -i 's/SQL_TS_BATCH_MAX_DELAY_MS: 100/SQL_TS_BATCH_MAX_DELAY_MS: 10/g' /usr/share/thingsboard/conf/thingsboard.yml

echo "🔧 Modificando SQL_TS_LATEST_BATCH_MAX_DELAY_MS de 50ms para 5ms..."
sudo docker exec mn.tb sed -i 's/SQL_TS_LATEST_BATCH_MAX_DELAY_MS: 50/SQL_TS_LATEST_BATCH_MAX_DELAY_MS: 5/g' /usr/share/thingsboard/conf/thingsboard.yml

echo "🔄 Reiniciando ThingsBoard para aplicar configurações..."
sudo docker restart mn.tb

echo "⏳ Aguardando ThingsBoard reinicializar..."
while ! sudo docker exec mn.tb pgrep -f thingsboard > /dev/null 2>&1; do
    sleep 2
done
sleep 15  # Tempo para estabilizar

echo "🔧 Atualizando código do middleware com RPC ultra-rápido..."
sudo docker cp services/middleware-dt/facade/models.py mn.middts:/middleware-dt/facade/models.py

echo "✅ Configurações URLLC aplicadas com sucesso!"
echo "📊 Configurações atuais:"
echo "  - CLIENT_SIDE_RPC_TIMEOUT: 1000ms"
echo "  - SQL_TS_BATCH_MAX_DELAY_MS: 10ms"
echo "  - SQL_TS_LATEST_BATCH_MAX_DELAY_MS: 5ms"
echo "  - RPC timeout no middleware: 1.5s"