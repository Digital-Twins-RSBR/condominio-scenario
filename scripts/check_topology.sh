#!/usr/bin/env bash
# Topology health checks for Condominio scenario
# Run via: sudo ./scripts/check_topology.sh

ROOT_DIR=$(dirname "$(dirname "$(readlink -f "$0")")")
RET=0
failures=()

info() { printf "[INFO] %s\n" "$*"; }
ok() { printf "[OK] %s\n" "$*"; }
err() { printf "[FAIL] %s\n" "$*"; failures+=("$*"); RET=1; }

get_ip() {
  local name=$1
  sudo docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name" 2>/dev/null || true
}

exists() {
  local name=$1
  sudo docker ps -a --format '{{.Names}}' | grep -x "$name" >/dev/null 2>&1
}

info "Starting topology checks"

# 1) Postgres running
if exists mn.db; then
  info "Checking Postgres container mn.db is running"
  if sudo docker ps --format '{{.Names}} {{.Status}}' | grep '^mn.db' | grep -i up >/dev/null 2>&1; then
    ok "mn.db is running"
  else
    err "mn.db is not running (docker ps shows not up)"
  fi
else
  err "mn.db container not found"
fi

# 2) middts DB exists in Postgres
if exists mn.db; then
  info "Checking for 'middts' database in Postgres"
  out=$(sudo docker exec mn.db psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='middts';" 2>/dev/null || true)
  if [ "$(echo "$out" | tr -d '[:space:]')" = "1" ]; then
    ok "Database 'middts' exists"
  else
    err "Database 'middts' not found in Postgres (psql output: '${out}')"
  fi
fi

# 3) middts and tb can ping the DB
DB_IP=$(get_ip mn.db)
if [ -n "$DB_IP" ]; then
  info "DB IP: $DB_IP"
  for n in mn.middts mn.tb; do
    if exists $n; then
      info "Pinging DB from $n"
      if sudo docker exec $n ping -c1 -W1 "$DB_IP" >/dev/null 2>&1; then
        ok "$n can ping Postgres ($DB_IP)"
      else
        err "$n cannot ping Postgres ($DB_IP)"
      fi
    else
      err "$n not found"
    fi
  done
else
  err "Could not determine DB IP"
fi

# 4) Influx running
info "Checking Influx health (HTTP /health)"
HEALTH_CODE=$(curl -sS -o /dev/null -w "%{http_code}" http://127.0.0.1:8086/health || true)
if [ "$HEALTH_CODE" = "200" ]; then
  ok "Influx /health returned 200"
else
  err "Influx /health returned $HEALTH_CODE"
fi

# 5) simulators and middts can ping influx
INFLUX_IP=$(get_ip mn.influxdb)
if [ -n "$INFLUX_IP" ]; then
  info "Influx IP: $INFLUX_IP"
  for n in mn.middts mn.sim_001; do
    if exists $n; then
      info "Pinging Influx from $n"
      if sudo docker exec $n ping -c1 -W1 "$INFLUX_IP" >/dev/null 2>&1; then
        ok "$n can ping Influx ($INFLUX_IP)"
      else
        err "$n cannot ping Influx ($INFLUX_IP)"
      fi
    else
      err "$n not found"
    fi
  done
else
  err "Could not determine Influx IP"
fi

# 6) simulators and middts have same INFLUX config and can write to bucket
info "Checking INFLUX configuration consistency and write access"
REPO_ENV="$ROOT_DIR/.env"
REPO_TOKEN=$(grep -E '^INFLUXDB_TOKEN=' "$REPO_ENV" | cut -d= -f2- || true)
REPO_BUCKET=$(grep -E '^INFLUXDB_BUCKET=' "$REPO_ENV" | cut -d= -f2- || true)
REPO_ORG=$(grep -E '^INFLUXDB_ORG=|^INFLUXDB_ORGANIZATION=' "$REPO_ENV" | head -n1 | cut -d= -f2- || true)

for c in mn.middts mn.sim_001; do
  if exists $c; then
    # path differs: middts mounts /middleware-dt/.env, sims mount /iot_simulator/.env
    if [ "$c" = "mn.middts" ]; then
      path="/middleware-dt/.env"
    else
      path="/iot_simulator/.env"
    fi
    info "Reading INFLUX env from $c:$path"
    token=$(sudo docker exec $c sh -c "[ -f $path ] && grep -E '^INFLUXDB_TOKEN=' $path | cut -d= -f2- || true" )
    bucket=$(sudo docker exec $c sh -c "[ -f $path ] && grep -E '^INFLUXDB_BUCKET=' $path | cut -d= -f2- || true" )
    org=$(sudo docker exec $c sh -c "[ -f $path ] && (grep -E '^INFLUXDB_ORG=' $path || grep -E '^INFLUXDB_ORGANIZATION=' $path) | cut -d= -f2- || true" )
    if [ -z "$token" ] || [ -z "$bucket" ]; then
      err "$c missing INFLUXDB_TOKEN/INFLUXDB_BUCKET in $path"
    else
      ok "$c has INFLUX token and bucket"
    fi
    if [ "$token" != "$REPO_TOKEN" ] || [ "$bucket" != "$REPO_BUCKET" ]; then
      err "$c INFLUX config differs from repo (.env): token/bucket"
    else
      ok "$c INFLUX config matches repo"
    fi
  else
    err "$c not found"
  fi
done

# Try writing a sample point using repo token to Influx write API
if [ -n "$REPO_TOKEN" ] && [ -n "$REPO_BUCKET" ] && [ -n "$REPO_ORG" ]; then
  info "Attempting to write a sample point to Influx (bucket=$REPO_BUCKET)"
  CODE=$(curl -sS -o /dev/null -w "%{http_code}" -XPOST "http://127.0.0.1:8086/api/v2/write?org=${REPO_ORG}&bucket=${REPO_BUCKET}&precision=ms" -H "Authorization: Token ${REPO_TOKEN}" --data-binary 'topo_check,host=check value=1' || true)
  if [ "$CODE" = "204" ]; then
    ok "Write to Influx succeeded (204)"
  else
    err "Write to Influx failed (HTTP $CODE)"
  fi
else
  err "Repo INFLUX token/org/bucket not found, skipping write test"
fi

# 6) Neo4j running
if exists mn.neo4j; then
  if sudo docker ps --format '{{.Names}} {{.Status}}' | grep '^mn.neo4j' | grep -i up >/dev/null 2>&1; then
    ok "mn.neo4j is running"
  else
    err "mn.neo4j not running"
  fi
else
  err "mn.neo4j container not found"
fi

# 7) middts can ping neo4j
NEO4J_IP=$(get_ip mn.neo4j)
if [ -n "$NEO4J_IP" ]; then
  if exists mn.middts; then
    if sudo docker exec mn.middts ping -c1 -W1 "$NEO4J_IP" >/dev/null 2>&1; then
      ok "mn.middts can ping Neo4j ($NEO4J_IP)"
    else
      err "mn.middts cannot ping Neo4j ($NEO4J_IP)"
    fi
  else
    err "mn.middts not found"
  fi
else
  err "Could not determine Neo4j IP"
fi

# 8) middts can write to neo4j using NEO4J_AUTH from middleware .env
if exists mn.middts && exists mn.neo4j; then
  # read NEO4J_AUTH from middleware env inside container
  auth=$(sudo docker exec mn.middts sh -c "[ -f /middleware-dt/.env ] && grep -E '^NEO4J_AUTH=' /middleware-dt/.env | cut -d= -f2- || true")
  if [ -z "$auth" ]; then
    err "NEO4J_AUTH not found in middts .env"
  else
    user=$(echo "$auth" | cut -d/ -f1)
    pass=$(echo "$auth" | cut -d/ -f2-)
    info "Attempting a simple Cypher write to Neo4j"
    CODE=$(curl -sS -o /dev/null -w "%{http_code}" -u "$user:$pass" -H "Content-Type: application/json" -d '{"statements":[{"statement":"CREATE (t:topo_check {ts:timestamp()}) RETURN t"}]}' "http://${NEO4J_IP}:7474/db/neo4j/tx/commit" || true)
    if [ "$CODE" = "200" ]; then
      ok "Write to Neo4j succeeded"
    else
      err "Write to Neo4j failed (HTTP $CODE)"
    fi
  fi
fi

echo
if [ "$RET" -eq 0 ]; then
  ok "All topology checks passed"
else
  err "Some topology checks failed"; printf "\nFailures:\n"; printf "%s\n" "${failures[@]}"
fi
exit $RET
