#!/bin/bash
set -e
echo "[tb] Atualizando pacotes..."
apt update
echo "[tb] Instalando dependências..."
apt install -y openjdk-11-jdk wget unzip net-tools
echo "[tb] Baixando ThingsBoard..."
wget -q https://github.com/thingsboard/thingsboard/releases/download/v3.5.1/thingsboard-3.5.1.deb
echo "[tb] Instalando ThingsBoard..."
dpkg -i thingsboard-3.5.1.deb || apt --fix-broken install -y
echo "[tb] Configurando modo standalone..."
echo "export DATABASE_TS_TYPE=sql" >> /etc/thingsboard/conf/thingsboard.conf
echo "export SPRING_DATASOURCE_URL=jdbc:hsqldb:file:/data/thingsboard;shutdown=true" >> /etc/thingsboard/conf/thingsboard.conf
echo "[tb] Executando instalação interna..."
/usr/share/thingsboard/bin/install/install.sh
echo "[tb] Iniciando serviço ThingsBoard..."
service thingsboard start
