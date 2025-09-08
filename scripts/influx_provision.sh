#!/usr/bin/env bash
set -euo pipefail

# idempotent InfluxDB v2 provisioner
# Usage: influx_provision.sh --host HOST --port PORT --token DESIRED_TOKEN --org ORG --bucket BUCKET [--admin-token ADMIN]

usage() {
  cat <<EOF
Usage: $0 --host HOST --port PORT --token DESIRED_TOKEN --org ORG --bucket BUCKET [--admin-token ADMIN]
This script will try to ensure org and bucket exist and create DESIRED_TOKEN if an ADMIN token is provided.
On success it exits 0. If it creates a new token it prints a line like: CREATED_TOKEN=<token>
EOF
  exit 2
}

HOST=127.0.0.1
PORT=8086
DESIRED_TOKEN=
ADMIN_TOKEN=
ORG=
BUCKET=

while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --token) DESIRED_TOKEN="$2"; shift 2;;
    --admin-token) ADMIN_TOKEN="$2"; shift 2;;
    --org) ORG="$2"; shift 2;;
    --bucket) BUCKET="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1" >&2; usage;;
  esac
done

if [ -z "$DESIRED_TOKEN" ] || [ -z "$ORG" ] || [ -z "$BUCKET" ]; then
  usage
fi

BASE_URL="http://${HOST}:${PORT}"

wait_health() {
  local tries=0
  while [ $tries -lt 30 ]; do
    # health endpoint is unauthenticated in many Influx setups
    code=$(curl -sS -o /dev/null -w '%{http_code}' "${BASE_URL}/health" || true)
    if [ "$code" = "200" ]; then
      return 0
    fi
    tries=$((tries+1))
    sleep 1
  done
  return 1
}

json_field() {
  # Use python for robust JSON parsing (available in our environments)
  python3 - <<PY
import sys, json
try:
  obj = json.load(sys.stdin)
except Exception as e:
  sys.exit(2)
path = sys.argv[1].split('.') if len(sys.argv) > 1 else []
cur = obj
for p in path:
  if isinstance(cur, dict) and p in cur:
    cur = cur[p]
  else:
    sys.exit(3)
print(cur)
PY
}

check_token_valid() {
  local token="$1"
  if [ -z "$token" ]; then return 1; fi
  # try to list orgs using the token
  out=$(curl -sS -H "Authorization: Token ${token}" "${BASE_URL}/api/v2/orgs?org=${ORG}" || true)
  if [ -z "$out" ]; then return 1; fi
  # parse 'orgs' array length
  has=$(printf '%s' "$out" | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d.get('orgs',[])))" 2>/dev/null || echo 0)
  if [ "$has" -ge 1 ]; then return 0; fi
  return 1
}

create_org_if_missing() {
  local token="$1"
  out=$(curl -sS -H "Authorization: Token ${token}" "${BASE_URL}/api/v2/orgs?org=${ORG}" || true)
  has=$(printf '%s' "$out" | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d.get('orgs',[])))" 2>/dev/null || echo 0)
  if [ "$has" -ge 1 ]; then
    org_id=$(printf '%s' "$out" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('orgs',[{}])[0].get('id',''))")
    printf '%s' "$org_id"
    return 0
  fi
  # create org
  r=$(curl -sS -X POST -H "Authorization: Token ${token}" -H 'Content-Type: application/json' -d "{\"name\": \"${ORG}\"}" "${BASE_URL}/api/v2/orgs" || true)
  org_id=$(printf '%s' "$r" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('id',''))" 2>/dev/null || echo '')
  if [ -n "$org_id" ]; then
    printf '%s' "$org_id"
    return 0
  fi
  return 1
}

ensure_bucket() {
  local token="$1"; local org_id="$2"; local bucket_name="$3"
  out=$(curl -sS -H "Authorization: Token ${token}" "${BASE_URL}/api/v2/buckets?orgID=${org_id}" || true)
  bid=$(printf '%s' "$out" | python3 -c "import sys,json;d=json.load(sys.stdin);bs=d.get('buckets',[]);print([b.get('id') for b in bs if b.get('name')=='${bucket_name}'][0] if any(b.get('name')=='${bucket_name}' for b in bs) else '')" 2>/dev/null || echo '')
  if [ -n "$bid" ]; then
    printf '%s' "$bid"
    return 0
  fi
  # create bucket
  payload=$(python3 - <<PY
import json
print(json.dumps({"orgID": "${org_id}", "name": "${bucket_name}", "retentionRules": []}))
PY
)
  r=$(curl -sS -X POST -H "Authorization: Token ${token}" -H 'Content-Type: application/json' -d "$payload" "${BASE_URL}/api/v2/buckets" || true)
  bid=$(printf '%s' "$r" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('id',''))" 2>/dev/null || echo '')
  if [ -n "$bid" ]; then
    printf '%s' "$bid"
    return 0
  fi
  return 1
}

create_token_for_bucket() {
  local token="$1"; local org_id="$2"; local bucket_id="$3"
  # permissions: read & write on the bucket
  payload=$(python3 - <<PY
import json
perms = [
  {"action":"read","resource":{"type":"buckets","orgID":"%s","id":"%s"}},
  {"action":"write","resource":{"type":"buckets","orgID":"%s","id":"%s"}}
]
obj = {"orgID":"%s","description":"provisioner-created-token","permissions":perms}
print(json.dumps(obj))
PY
  )
  r=$(curl -sS -X POST -H "Authorization: Token ${token}" -H 'Content-Type: application/json' -d "$payload" "${BASE_URL}/api/v2/authorizations" || true)
  tkn=$(printf '%s' "$r" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('token',''))" 2>/dev/null || echo '')
  if [ -n "$tkn" ]; then
    printf '%s' "$tkn"
    return 0
  fi
  return 1
}

main() {
  if ! wait_health; then
    echo "[ERROR] Influx /health did not become available on ${BASE_URL}" >&2
    return 2
  fi

  # 1) if desired token already valid -> success
  if check_token_valid "$DESIRED_TOKEN"; then
    echo "[OK] desired token valid"
    return 0
  fi

  # 2) try admin token if available
  if [ -n "$ADMIN_TOKEN" ] && check_token_valid "$ADMIN_TOKEN"; then
    # ensure org
    org_id=$(create_org_if_missing "$ADMIN_TOKEN") || true
    if [ -z "$org_id" ]; then
      echo "[ERROR] failed to ensure org ${ORG}" >&2
      return 3
    fi
    # ensure bucket
    bucket_id=$(ensure_bucket "$ADMIN_TOKEN" "$org_id" "$BUCKET") || true
    if [ -z "$bucket_id" ]; then
      echo "[ERROR] failed to ensure bucket ${BUCKET} in org ${ORG}" >&2
      return 4
    fi
    # create token with permissions on bucket
    newtkn=$(create_token_for_bucket "$ADMIN_TOKEN" "$org_id" "$bucket_id" ) || true
    if [ -n "$newtkn" ]; then
      # print a machine-friendly line for the caller
      echo "CREATED_TOKEN=${newtkn}"
      return 0
    fi
    echo "[ERROR] failed to create token via admin token" >&2
    return 5
  fi

  echo "[WARN] desired token invalid and no usable admin token available to create one. Manual intervention required." >&2
  return 6
}

main
