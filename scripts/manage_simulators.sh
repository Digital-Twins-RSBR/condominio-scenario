#!/bin/bash

ACTION=$1
shift
ARGS=("$@")

NUM_CONTAINERS=100
IMAGE_NAME=simulator
NETWORK=edge

function start_all() {
  echo "[🚀] Iniciando ${NUM_CONTAINERS} simuladores..."
  for i in $(seq -f "%03g" 1 $NUM_CONTAINERS); do
    NAME="sim_$i"
    echo "→ Criando container $NAME"
    docker run -d --rm --name $NAME --network $NETWORK $IMAGE_NAME
  done
}

function stop_all() {
  echo "[🛑] Parando todos os containers com prefixo sim_..."
  docker ps --format '{{.Names}}' | grep '^sim_' | xargs -r docker stop
}

function call_simulators() {
  local sim_ids=()
  local cmd=""
  for arg in "${ARGS[@]}"; do
    if [[ "$arg" == sim_* ]]; then
      sim_ids+=("$arg")
    else
      cmd="$cmd $arg"
    fi
  done

  if [[ ${#sim_ids[@]} -eq 0 ]]; then
    # executar em todos
    echo "[⚙️] Executando em TODOS os simuladores: python manage.py$cmd"
    docker ps --format '{{.Names}}' | grep '^sim_' | while read name; do
      echo "→ $name"
      docker exec "$name" python manage.py$cmd
    done
  else
    echo "[⚙️] Executando comando python manage.py$cmd nos simuladores: ${sim_ids[*]}"
    for sim in "${sim_ids[@]}"; do
      docker exec "$sim" python manage.py$cmd
    done
  fi
}

case "$ACTION" in
  start)
    start_all
    ;;
  stop)
    stop_all
    ;;
  call)
    call_simulators
    ;;
  *)
    echo "Uso: $0 {start|stop|call} [sim_ids...] [manage_cmd]"
    echo "Exemplos:"
    echo "  $0 start                         # inicia todos"
    echo "  $0 stop                          # para todos"
    echo "  $0 call status                   # python manage.py status em todos"
    echo "  $0 call sim_001 sim_002 sync     # python manage.py sync em sim_001 e sim_002"
    ;;
esac
