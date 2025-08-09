#!/bin/bash
echo "=== Healthcheck ThingsBoard ==="
echo "[1] Localhost (externo)..."
curl -I http://localhost:8080 || echo "[ERRO] Não responde em localhost"

echo "[2] Docker mn.tb (interno)..."
docker exec mn.tb curl -I http://localhost:8080 || echo "[ERRO] Container mn.tb não responde"

echo "[3] Verificando processo Java do ThingsBoard..."
docker exec mn.tb ps aux | grep java | grep -v grep || echo "[ERRO] Processo Java não encontrado"
