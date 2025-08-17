#!/bin/sh
set -eu

ROOT_DIR=$(cd "$(dirname "$0")"/.. && pwd)
ENV_FILE="$ROOT_DIR/services/middleware-dt/.env"

# Load POSTGRES_USER and POSTGRES_PASSWORD from .env if present
POSTGRES_USER=${POSTGRES_USER:-}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-}
if [ -f "$ENV_FILE" ]; then
  u=$(grep -E '^POSTGRES_USER=' "$ENV_FILE" 2>/dev/null | head -n1 | cut -d'=' -f2- || true)
  p=$(grep -E '^POSTGRES_PASSWORD=' "$ENV_FILE" 2>/dev/null | head -n1 | cut -d'=' -f2- || true)
  [ -n "$u" ] && POSTGRES_USER=$u
  [ -n "$p" ] && POSTGRES_PASSWORD=$p
fi

: ${POSTGRES_USER:=postgres}
: ${POSTGRES_PASSWORD:=tb}

echo "[RESTORE-SCRIPT] POSTGRES_USER=$POSTGRES_USER (using .env if present)"

cid=$(docker ps -q -f name=mn.db) || true
if [ -z "$cid" ]; then
  echo "[ERRO] Postgres container mn.db not running"
  exit 1
fi

echo "[RESTORE-SCRIPT] using container id: $cid"

if [ ! -f "$ROOT_DIR/services/middleware-dt/middts.sql" ]; then
  echo "[ERRO] services/middleware-dt/middts.sql not found"
  exit 1
fi

docker cp "$ROOT_DIR/services/middleware-dt/middts.sql" "$cid:/tmp/middts.sql" || { echo "[ERRO] docker cp failed"; exit 1; }

docker exec -i "$cid" bash -lc "PGPASSWORD='$POSTGRES_PASSWORD' psql -U $POSTGRES_USER -c 'DROP DATABASE IF EXISTS middts;'" || echo "[WARN] drop may have failed"
docker exec -i "$cid" bash -lc "PGPASSWORD='$POSTGRES_PASSWORD' psql -U $POSTGRES_USER -c 'CREATE DATABASE middts OWNER $POSTGRES_USER;'" || { echo "[ERRO] create database failed"; exit 1; }
docker exec -i "$cid" bash -lc "PGPASSWORD='$POSTGRES_PASSWORD' psql -U $POSTGRES_USER -d middts -f /tmp/middts.sql" || { echo "[ERRO] import failed (see container logs)"; exit 1; }

echo "[RESTORE-SCRIPT] middts import finished"
