# Makefile reorganizado para melhor legibilidade e manutenção
# ==========================================================

# === VARIÁVEIS DE IMAGEM E CAMINHO ===
MIDDTS_IMAGE = middts:latest
MIDDTS_CUSTOM_IMAGE = middts-custom:latest
IOT_SIM_IMAGE = iot_simulator:latest
TB_IMAGE = tb-node-custom
PG_IMAGE = postgres:13-tools
NEO4J_IMAGE = neo4j-tools:latest
PARSER_IMAGE = parserwebapi-tools:latest
INFLUX_IMAGE = influxdb-tools:latest

MIDDTS_PATH = services/middleware-dt/
SIMULATOR_PATH = services/iot_simulator/
DOCKER_PATH = dockerfiles
# === SETUP E LIMPEZA ===
.PHONY: setup clean clean-containers reset-db reset-db-tb reset-db-middts reset-db-influx reset-db-neo4j reset-db-sims reset-tb

setup:
	@echo "[Setup] Executar ./scripts/setup.sh"
	./scripts/setup.sh

clean:
	@echo "[🧼] Limpando ambiente Mininet/Containernet e containers órfãos"
	-sudo mn -c || echo "[WARN] mn -c falhou"
	-docker ps -a --filter "name=mn." -q | xargs -r docker rm -f
	-docker network ls --filter "name=mn." -q | xargs -r docker network rm
	-docker volume ls --filter "name=mn." -q | xargs -r docker volume rm
	@echo "[🧯] Limpando interfaces de rede restantes"
	-ip -o link show | awk -F': ' '{print $$2}' | grep -E '^(mn-|sim_|s[0-9]+-eth[0-9]+)' | xargs -r -n1 sudo ip link delete
	@echo "[🧯] Limpando interfaces veth Mininet/Containernet"
	@ip -o link show | awk -F': ' '{print $$2}' | cut -d'@' -f1 | grep -E '^(mn-|sim_|s[0-9]+-eth[0-9]+)' | sort | uniq | xargs -r -n1 sudo ip link delete || true

clean-containers:
	docker ps -a --filter "name=mn." -q | xargs -r docker rm -f

## High level reset: calls focused reset targets so operator can compose actions
reset-db: reset-db-tb reset-db-middts reset-db-influx reset-db-neo4j reset-db-sims
	@echo "[reset-db] Reset completo executado (best-effort)."

# Reset ThingsBoard volumes (db + assets + logs)
reset-db-tb:
	@echo "[reset-db-tb] Removendo volumes do ThingsBoard (db_data, tb_assets, tb_logs)..."
	-@docker volume rm db_data tb_assets tb_logs || true
	@echo "[reset-db-tb] Volumes do ThingsBoard removidos (se existiam)."

# Reset MidDiTS related volumes
reset-db-middts:
	@echo "[reset-db-middts] Removendo volumes relacionados ao MidDiTS"
	-@docker volume ls --format '{{.Name}}' | grep -E 'middts|middleware' | xargs -r -n1 docker volume rm || true
	@echo "[reset-db-middts] Concluído (best-effort)."

# Reset InfluxDB volumes
reset-db-influx:
	@echo "[reset-db-influx] Removendo volumes relacionados ao InfluxDB"
	-@docker volume rm influx_data influx_logs || true
	-@docker volume ls --format '{{.Name}}' | grep -E 'influx|influxdb' | xargs -r -n1 docker volume rm || true
	@echo "[reset-db-influx] Concluído (best-effort)."

# Reset Neo4j volumes
reset-db-neo4j:
	@echo "[reset-db-neo4j] Removendo volumes relacionados ao Neo4j"
	-@docker volume rm neo4j_data neo4j_logs || true
	-@docker volume ls --format '{{.Name}}' | grep -E 'neo4j' | xargs -r -n1 docker volume rm || true
	@echo "[reset-db-neo4j] Concluído (best-effort)."

# Reset simulator host files and simulator volumes
reset-db-sims:
	@echo "[reset-db-sims] Removendo volumes e dados locais dos simuladores"
	-@docker volume ls --format '{{.Name}}' | grep -E 'parser|sim_|simulator' | xargs -r -n1 docker volume rm || true
	-@find services/iot_simulator -maxdepth 1 -type f -name 'db.sqlite3' -exec rm -f {} \; || true
	@mkdir -p deploy || true
	@touch deploy/.reset_sim_db
	@echo "[reset-db-sims] Simulators: host DB removido; deploy/.reset_sim_db criado."

reset-tb:
	@echo "Removendo volumes do ThingsBoard (db_data, tb_assets, tb_logs)..."
	-docker volume rm db_data tb_assets tb_logs
	@echo "Volumes removidos. O banco e dados do TB serão recriados limpos no próximo start."

# === PRUNE VOLUMES POR SERVIÇO ===
.PHONY: prune-vol-influx prune-vol-neo4j prune-vol-middts prune-vol-tb prune-vol-simulators prune-vol-all

prune-vol-influx:
	@echo "[🗑️] Removendo volumes relacionados ao InfluxDB (nomes contendo 'influx' ou 'influxdb')"
	-@docker volume ls --format '{{.Name}}' | grep -E 'influx|influxdb' | xargs -r -n1 docker volume rm || true
	@echo "Prune InfluxDB: concluído"

prune-vol-neo4j:
	@echo "[🗑️] Removendo volumes relacionados ao Neo4j (nomes contendo 'neo4j')"
	-@docker volume ls --format '{{.Name}}' | grep -E 'neo4j' | xargs -r -n1 docker volume rm || true
	@echo "Prune Neo4j: concluído"

prune-vol-middts:
	@echo "[🗑️] Removendo volumes relacionados ao MidDiTS (nomes contendo 'middts' ou 'middleware')"
	-@docker volume ls --format '{{.Name}}' | grep -E 'middts|middleware' | xargs -r -n1 docker volume rm || true
	@echo "Prune MidDiTS: concluído"

prune-vol-tb:
	@echo "[🗑️] Removendo volumes do ThingsBoard (db_data, tb_assets, tb_logs)"
	-@docker volume rm db_data tb_assets tb_logs || true
	@echo "Prune ThingsBoard: concluído"

prune-vol-simulators:
	@echo "[🗑️] Removendo volumes relacionados aos simuladores (nomes contendo 'sim_' ou 'simulator')"
	-@docker volume ls --format '{{.Name}}' | grep -E 'sim_|simulator' | xargs -r -n1 docker volume rm || true
	@echo "Prune Simulators: concluído"

prune-vol-all: prune-vol-influx prune-vol-neo4j prune-vol-middts prune-vol-tb prune-vol-simulators
	@echo "[🗑️] Pruning concluído para todos os serviços conhecidos"

# === LOG ROTATION HELPERS ===
.PHONY: install-logrotate run-logrotate truncate-logs

install-logrotate:
	@echo "[install-logrotate] Instalando configuração de logrotate para deploy/logs (requer sudo)"
	@if [ ! -f deploy/logs/logrotate/condominio-scenario ]; then echo "[ERRO] deploy/logs/logrotate/condominio-scenario não encontrado"; exit 1; fi
	-sudo cp deploy/logs/logrotate/condominio-scenario /etc/logrotate.d/condominio-scenario || (echo "[WARN] falha ao copiar; verifique permissões"; exit 1)
	@echo "[install-logrotate] Configuração instalada em /etc/logrotate.d/condominio-scenario"

run-logrotate:
	@echo "[run-logrotate] Forçando execução imediata do logrotate (requer sudo)"
	@if [ ! -f /etc/logrotate.d/condominio-scenario ]; then echo "[WARN] /etc/logrotate.d/condominio-scenario não encontrado. Rode 'make install-logrotate' primeiro"; fi
	-sudo logrotate -f /etc/logrotate.d/condominio-scenario || (echo "[WARN] logrotate retornou erro (verifique /var/log/messages ou syslog)")
	@echo "[run-logrotate] Execução concluída (ou falhou com aviso)."

truncate-logs:
	@echo "[truncate-logs] Truncando logs grandes em deploy/logs para liberar espaço imediato (requer sudo)"
	@for f in deploy/logs/*.log; do \
		echo "[truncate] truncating $$f to 0 bytes"; \
		sudo truncate -s 0 "$$f" || echo "[WARN] failed to truncate $$f"; \
	done
	@echo "[truncate-logs] Truncation attempted on matching logs."

# === BUILD DE IMAGENS ===
.PHONY: build-images rebuild-images

build-images:
	@echo "[🐳] Construindo imagens Docker personalizadas"
	docker build -t $(MIDDTS_CUSTOM_IMAGE) -f $(DOCKER_PATH)/Dockerfile.middts services/
	docker build -t $(IOT_SIM_IMAGE) -f $(DOCKER_PATH)/Dockerfile.iot_simulator services/
	docker build -t $(TB_IMAGE) -f $(DOCKER_PATH)/Dockerfile.tb services/
	docker build -t $(PG_IMAGE) -f $(DOCKER_PATH)/Dockerfile.pg13 services/
	docker build -t $(NEO4J_IMAGE) -f $(DOCKER_PATH)/Dockerfile.neo4j services/
	docker build -t $(PARSER_IMAGE) -f $(DOCKER_PATH)/Dockerfile.parser services/
	docker build -t $(INFLUX_IMAGE) -f $(DOCKER_PATH)/Dockerfile.influx services/
	

rebuild-images:
	@echo "[🐳] Rebuilding ALL images from scratch (pulling base images, no cache)"
	# Use --pull to get latest base layers and --no-cache to force full rebuild
	docker build --pull --no-cache -t $(MIDDTS_CUSTOM_IMAGE) -f $(DOCKER_PATH)/Dockerfile.middts services/
	docker build --pull --no-cache -t $(IOT_SIM_IMAGE) -f $(DOCKER_PATH)/Dockerfile.iot_simulator services/
	docker build --pull --no-cache -t $(TB_IMAGE) -f $(DOCKER_PATH)/Dockerfile.tb services/
	docker build --pull --no-cache -t $(PG_IMAGE) -f $(DOCKER_PATH)/Dockerfile.pg13 services/
	docker build --pull --no-cache -t $(NEO4J_IMAGE) -f $(DOCKER_PATH)/Dockerfile.neo4j services/
	docker build --pull --no-cache -t $(PARSER_IMAGE) -f $(DOCKER_PATH)/Dockerfile.parser services/
	docker build --pull --no-cache -t $(INFLUX_IMAGE) -f $(DOCKER_PATH)/Dockerfile.influx services/
	@echo "[🐳] Rebuild completo finalizado. Certifique-se de recriar os containers para usar as novas imagens."

# === USABILITY ALIASES E WORKFLOWS ===
# Comandos mais intuitivos para o dia-a-dia: imagens, containers e um fluxo dev rápido
.PHONY: help images-build images-rebuild containers-recreate dev ps logs-sim

help:
	@echo "Uso: make <target>"
	@echo "Grupos principais:"
	@echo "  images-build        -> Reconstruir imagens (igual a make build-images)"
	@echo "  images-rebuild      -> Rebuild completo (igual a make rebuild-images)"
	@echo "  containers-recreate -> Remove um container mn.<SERVICE> (use SERVICE=tb)"
	@echo "  dev                 -> Fluxo rápido (remove containers, build images, executa topo)"
	@echo "  topo                -> Inicia a topologia (containernet)"
	@echo "  clean               -> Limpeza completa (rede/veth/containers)"
	@echo "  check               -> Health checks dos containers (use make check)"
	@echo "Exemplos: make images-build; make containers-recreate SERVICE=tb; make dev"

# Aliases que delegam para os targets já existentes para manter compatibilidade
images-build:
	@$(MAKE) build-images

images-rebuild:
	@$(MAKE) rebuild-images

containers-recreate:
	@if [ -z "$(SERVICE)" ]; then echo "[USO] make containers-recreate SERVICE=tb"; exit 1; fi
	@$(MAKE) recreate-container SERVICE=$(SERVICE)

# Fluxo diário usado por você: remove apenas containers, rebuild de imagens e sobe a topologia
dev:
	@echo "[DEV] Fluxo: clean-containers -> build-images -> topo"
	@$(MAKE) clean-containers
	@$(MAKE) build-images
	@$(MAKE) topo

# Conveniência: listar containers filtrados pelo prefixo mn.
ps:
	@docker ps --filter "name=mn." --format 'table {{.Names}}	{{.Status}}	{{.Image}}'

# Tail rápido dos logs de um simulador: make logs-sim SIM=sim_001
logs-sim:
	@tail -n 200 -f services/iot_simulator/logs/mn.$(SIM)_start.log || tail -n 200 -f deploy/logs/$(SIM)_start.log || true

# Convenience targets to run the parser as an external Docker container
.PHONY: run-parser stop-parser

run-parser:
	@echo "[run-parser] Starting external parser container (detached) using image $(PARSER_IMAGE)"
	-@docker run -d --name parser -p 8082:8080 -p 8083:8081 --restart unless-stopped $(PARSER_IMAGE) || echo "[WARN] parser already running or failed to start"
	@echo "[run-parser] If you need a different host port, override ports or start the container manually."

stop-parser:
	@echo "[stop-parser] Stopping and removing external parser container 'parser'"
	-@docker rm -f parser || true
	@echo "[stop-parser] Done."
# === TOPOLOGIA E VISUALIZAÇÃO ===
.PHONY: topo topo-screen draw

topo:
	@echo "[📡] Executando topologia com Containernet"
	# Use the helper script to centralize environment handling and defaults.
	# Default behavior preserves state (PRESERVE_STATE=1) unless overridden by caller.
	@sh scripts/run_topo.sh

topo-screen:
	@echo "[📡] Executando topologia com Containernet em screen"
	# Start the topology inside a detached screen session. Honor PRESERVE_STATE if provided,
	# default to 1 inside the screen command.
	@screen -S containernet -dm sh -c 'if [ -z "$$PRESERVE_STATE" ]; then PRESERVE_STATE=1; fi; export PRESERVE_STATE; sh scripts/run_topo.sh'
	@echo "Use: screen -r containernet  para acessar o CLI do Containernet"


# === PREPARE / CLEAN BOOT FOR TOPOLOGY ===
.PHONY: ensure-clean-boot
ensure-clean-boot:
	@echo "[🔁] ensure-clean-boot: verificação de volumes InfluxDB/Neo4j (remover se existirem)"
	@SIM_ENV="$$(pwd)/.env"; \
	if [ ! -f "$$SIM_ENV" ]; then SIM_ENV="$$(pwd)/services/middleware-dt/.env"; fi; \
	if [ -f "$$SIM_ENV" ]; then . "$$SIM_ENV"; fi; \
	# Allow operator to preserve state by passing PRESERVE_STATE=1 to make
	if [ "$$PRESERVE_STATE" = "1" ]; then \
		echo "[ℹ️] PRESERVE_STATE=1 set, skipping automatic volume removal."; \
		exit 0; \
	fi; \
	# Note: ensure-clean-boot no longer auto-deletes InfluxDB/Neo4j data volumes.
	# Use `make reset-db-influx` or `make reset-db-neo4j` to explicitly remove volumes.
	if docker volume ls --format '{{.Name}}' | grep -E 'influx|influxdb' >/dev/null 2>&1; then \
		echo "[⚠️] Influx volumes detected. Run 'make reset-db-influx' to remove them if you really want a fresh bootstrap."; \
	else \
		echo "[🔎] No Influx volumes found."; \
	fi; \
	if docker volume ls --format '{{.Name}}' | grep -E 'neo4j' >/dev/null 2>&1; then \
		echo "[⚠️] Neo4j volumes detected. Run 'make reset-db-neo4j' to remove them if you really want a fresh bootstrap."; \
	else \
		echo "[🔎] No Neo4j volumes found."; \
	fi; \
	echo "[🔁] ensure-clean-boot: concluído. No volumes were removed."

draw:
	@echo "[🖼️ ] Gerando visualização da topologia"
	bash -c 'python3 services/topology/draw_topology.py'

# === VERIFICAÇÕES DE STATUS E REDE ===
.PHONY: check check-tb check-middts check-db check-influxdb check-neo4j check-parser check-simulator check-simulators check-network check-tb-internal

check:
	@echo "[🔎] Verificação rápida dos serviços (resumo em tabela)"
	@printf "%-12s | %-15s | %-20s | %-7s | %-40s | %s\n" "serviço" "ip" "porta exposta" "rodando" "log inicializacao" "outras"
	@printf "%.0s-" {1..120}; echo
	@services="tb middts db influxdb neo4j parser"; \
	for s in $$services; do \
		c=mn.$$s; \
		ip=$$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $$c 2>/dev/null || echo '-'); \
		ports=$$(docker port $$c 2>/dev/null || echo '-'); \
		running=$$(docker ps --filter "name=$$c" --filter "status=running" -q | wc -l | tr -d ' '); \
		if [ "$$running" -gt 0 ]; then r="yes"; else r="no"; fi; \
		case $$s in \
			tb) log="deploy/logs/tb_start.log" ;; \
			middts) log="deploy/logs/middts_start.log" ;; \
			db) log="deploy/logs/db_start.log" ;; \
			influxdb) log="deploy/logs/influx_start.log" ;; \
			neo4j) log="deploy/logs/neo4j_start.log" ;; \
			parser) log="deploy/logs/parser_start.log" ;; \
		esac; \
		printf "%-12s | %-15s | %-20s | %-7s | %-40s | %s\n" $$s $$ip "$$ports" $$r $$log ""; \
	done
	@# simuladores
	@for i in 1 2 3 4 5; do \
		name=`printf 'sim_%03d' $$i`; \
		c=mn.$$name; \
		ip=$$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $$c 2>/dev/null || echo '-'); \
		ports=$$(docker port $$c 2>/dev/null || echo '-'); \
		running=$$(docker ps --filter "name=$$c" --filter "status=running" -q | wc -l | tr -d ' '); \
		if [ "$$running" -gt 0 ]; then r="yes"; else r="no"; fi; \
		log="services/iot_simulator/logs/$$name_start.log"; \
		printf "%-12s | %-15s | %-20s | %-7s | %-40s | %s\n" $$name $$ip "$$ports" $$r $$log ""; \
	done
	@echo "\nPara detalhes em tempo real use: tail -f deploy/logs/<servico>_start.log ou VERBOSE=1 make topo"

# Serviços principais
check-tb:
	@echo "[🔎] Verificando container tb"
	docker ps --format '{{.Names}}' | grep -q '^mn.tb$$' && echo "✅ Container mn.tb está rodando" || echo "❌ Container mn.tb não está rodando"
	@echo "[🔎] Verificando serviço ThingsBoard (porta 8080)"
	docker exec -it mn.tb bash -c 'nc -z -w 2 127.0.0.1 8080' && echo "✅ ThingsBoard ouvindo na porta 8080" || echo "❌ ThingsBoard não está ouvindo na porta 8080"
	@echo "[🔎] Testando comunicação com o banco (db)"
	docker exec -it mn.tb ping -c 2 10.0.0.10 || echo "[ERRO] tb não pinga db (10.0.0.10)"
	docker exec -it mn.tb bash -c 'nc -vz -w 2 10.0.0.10 5432' || echo "[ERRO] tb não conecta TCP 5432 em db (10.0.0.10)"

check-middts:
	@echo "[🔎] Verificando container middts"
	docker ps --format '{{.Names}}' | grep -q '^mn.middts$$' && echo "✅ Container mn.middts está rodando" || echo "❌ Container mn.middts não está rodando"
	@echo "[🔎] Verificando serviço MidDiTS (porta 8000)"
	docker exec -it mn.middts bash -c 'nc -z -w 2 127.0.0.1 8000' && echo "✅ MidDiTS ouvindo na porta 8000" || echo "❌ MidDiTS não está ouvindo na porta 8000"
	@echo "[🔎] Testando comunicação com o banco (db)"
	docker exec -it mn.middts ping -c 2 10.10.2.10 || echo "[ERRO] middts não pinga db"
	docker exec -it mn.middts bash -c 'nc -vz -w 2 10.10.2.10 5432' || echo "[ERRO] middts não conecta TCP 5432 em db"
	@echo "[🔎] Testando comunicação com InfluxDB"
	docker exec -it mn.middts ping -c 2 10.10.2.20 || echo "[ERRO] middts não pinga influxdb"
	docker exec -it mn.middts bash -c 'nc -vz -w 2 10.10.2.20 8086' || echo "[ERRO] middts não conecta TCP 8086 em influxdb"
	@echo "[🔎] Testando comunicação com Neo4j"
	docker exec -it mn.middts ping -c 2 10.10.2.30 || echo "[ERRO] middts não pinga neo4j"
	docker exec -it mn.middts bash -c 'nc -vz -w 2 10.10.2.30 7474' || echo "[ERRO] middts não conecta TCP 7474 em neo4j"

check-db:
	@echo "[🔎] Verificando container db"
	docker ps --format '{{.Names}}' | grep -q '^mn.db$$' && echo "✅ Container mn.db está rodando" || echo "❌ Container mn.db não está rodando"
	@echo "[🔎] Verificando serviço PostgreSQL (porta 5432)"
	docker exec -it mn.db bash -c 'nc -z -w 2 127.0.0.1 5432' && echo "✅ PostgreSQL ouvindo na porta 5432" || echo "❌ PostgreSQL não está ouvindo na porta 5432"
	@echo "[🔎] Testando comunicação com tb (rede local 10.10.1.2 — não é usada pelo ThingsBoard, esperado falhar)"
	docker exec -it mn.db ping -c 2 10.10.1.2 || echo "[ERRO] db não pinga tb (10.10.1.2 — esperado se falhar)"
	docker exec -it mn.db bash -c 'nc -vz -w 2 10.10.1.2 8080' || echo "[ERRO] db não conecta TCP 8080 em tb (10.10.1.2 — esperado se falhar)"
	@echo "[🔎] Testando comunicação com tb (gerenciamento 10.0.0.11 — interface correta segundo a topologia)"
	docker exec -it mn.db ping -c 2 10.0.0.11 || echo "[ERRO] db não pinga tb (10.0.0.11 — deveria funcionar)"
	docker exec -it mn.db bash -c 'nc -vz -w 2 10.0.0.11 8080' || echo "[ERRO] db não conecta TCP 8080 em tb (10.0.0.11 — deveria funcionar)"

check-influxdb:
	@echo "[🔎] Verificando container influxdb"
	docker ps --format '{{.Names}}' | grep -q '^mn.influxdb$$' && echo "✅ Container mn.influxdb está rodando" || echo "❌ Container mn.influxdb não está rodando"
	@echo "[🔎] Verificando serviço InfluxDB (porta 8086 — esperado em 127.0.0.1 e 10.10.2.20, conforme topologia)"
	docker exec -it mn.influxdb bash -c 'nc -z -w 2 127.0.0.1 8086' && echo "✅ InfluxDB ouvindo na porta 8086 (localhost)" || echo "❌ InfluxDB não está ouvindo na porta 8086 (localhost)"
	docker exec -it mn.influxdb bash -c 'nc -z -w 2 10.10.2.20 8086' && echo "✅ InfluxDB ouvindo na porta 8086 (10.10.2.20)" || echo "❌ InfluxDB não está ouvindo na porta 8086 (10.10.2.20)"
	@echo "[🔎] Testando comunicação com middts (10.10.2.2 — interface relevante para MidDiTS)"
	docker exec -it mn.influxdb ping -c 2 10.10.2.2 || echo "[ERRO] influxdb não pinga middts (10.10.2.2 — deveria funcionar)"
	docker exec -it mn.influxdb bash -c 'nc -vz -w 2 10.10.2.2 8000' || echo "[ERRO] influxdb não conecta TCP 8000 em middts (10.10.2.2 — deveria funcionar)"
	@echo "[DEBUG] Interfaces e rotas do influxdb para diagnóstico:"
	docker exec -it mn.influxdb ip addr
	docker exec -it mn.influxdb ip route

check-neo4j:
	@echo "[🔎] Verificando container neo4j"
	docker ps --format '{{.Names}}' | grep -q '^mn.neo4j$$' && echo "✅ Container mn.neo4j está rodando" || echo "❌ Container mn.neo4j não está rodando"
	@echo "[🔎] Verificando serviço Neo4j (porta 7474)"
	docker exec -it mn.neo4j bash -c 'nc -z -w 2 127.0.0.1 7474' && echo "✅ Neo4j ouvindo na porta 7474" || echo "❌ Neo4j não está ouvindo na porta 7474"
	@echo "[🔎] Testando comunicação com middts"
	docker exec -it mn.neo4j ping -c 2 10.10.2.2 || echo "[ERRO] neo4j não pinga middts"
	docker exec -it mn.neo4j bash -c 'nc -vz -w 2 10.10.2.2 8000' || echo "[ERRO] neo4j não conecta TCP 8000 em middts"

check-parser:
	@echo "[🔎] Verificando container parser"
	@# Support either an in-topology mn.parser or an external container named 'parser'
	@if docker ps --format '{{.Names}}' | grep -q '^mn.parser$$'; then \
		echo "✅ Container mn.parser está rodando"; \
		echo "[🔎] Verificando serviço Parser (porta 8080) dentro da topologia"; \
		docker exec -it mn.parser bash -c 'nc -z -w 2 127.0.0.1 8080' && echo "✅ Parser (mn.parser) ouvindo na porta 8080" || echo "❌ Parser (mn.parser) não está ouvindo na porta 8080"; \
		echo "[🔎] Testando comunicação com middts (rede interna)"; \
		docker exec -it mn.parser ping -c 2 10.10.2.2 || echo "[ERRO] parser não pinga middts"; \
		docker exec -it mn.parser bash -c 'nc -vz -w 2 10.10.2.2 8000' || echo "[ERRO] parser não conecta TCP 8000 em middts"; \
	elif docker ps --format '{{.Names}}' | grep -q '^parser$$'; then \
		echo "ℹ️ Container externo 'parser' está rodando (fora da topologia)"; \
		echo "Ports:"; docker port parser || true; \
		echo "Nota: parser é externo — verificações de rede internas (ping entre mn.*) serão ignoradas."; \
		echo "Você pode testar acessibilidade via host com: nc -z -v -w 2 127.0.0.1 8082"; \
	else \
		echo "❌ Nenhum container 'parser' encontrado (nem mn.parser nem parser)"; \
		echo "Inicie o parser externamente: make run-parser"; \
	fi

# Simuladores
check-simulators:
	@echo "[🔎] Verificando todos os simuladores (sim_*)"
	for c in $$(docker ps --format '{{.Names}}' | grep '^mn.sim_'); do \
		echo "[Simulador] $$c"; \
		make check-simulator SIM=$$c; \
	done

check-simulator:
	@if [ -z "$(SIM)" ]; then echo "[ERRO] Use: make check-simulator SIM=mn.sim_001"; exit 1; fi
	@echo "[🔎] Verificando container $(SIM)"
	docker ps --format '{{.Names}}' | grep -q '^$(SIM)$$' && echo "✅ Container $(SIM) está rodando" || echo "❌ Container $(SIM) não está rodando"
	@echo "[🔎] Verificando serviço do simulador (porta 5000)"
	docker exec -it $(SIM) bash -c 'nc -z -w 2 127.0.0.1 5000' && echo "✅ Simulador ouvindo na porta 5000" || echo "❌ Simulador não está ouvindo na porta 5000"
	@echo "[🔎] Testando comunicação com tb"
	docker exec -it $(SIM) ping -c 2 10.10.1.2 || echo "[ERRO] $(SIM) não pinga tb"
	docker exec -it $(SIM) bash -c 'nc -vz -w 2 10.10.1.2 8080' || echo "[ERRO] $(SIM) não conecta TCP 8080 em tb"

# Topology health check: runs the comprehensive check script created in scripts/check_topology.sh
.PHONY: topo-check
topo-check:
	@echo "[🔁] Running topology health checks (scripts/check_topology.sh)"
	@chmod +x scripts/check_topology.sh || true
	@./scripts/check_topology.sh

# === HELPERS PARA EXECUTAR COMANDOS DENTRO DE CONTAINERS ===
.PHONY: exec-middts exec-sim

exec-middts:
	@if [ -z "$(CMD)" ]; then echo "[USO] make exec-middts CMD='bash'"; exit 1; fi
	@echo "[🔧] Executando em mn.middts: $(CMD)"
	-docker exec -it mn.middts sh -c "$(CMD)"

exec-sim:
	@if [ -z "$(SIM)" ] || [ -z "$(CMD)" ]; then echo "[USO] make exec-sim SIM=mn.sim_001 CMD='bash'"; exit 1; fi
	@echo "[🔧] Executando em $(SIM): $(CMD)"
	-docker exec -it $(SIM) sh -c "$(CMD)"

# === Process management helpers (simulators & middts) ===

.PHONY: sims_status sims_call sims_stop sims_kill middts_status middts_call middts_stop middts_kill

# -- Simulator helpers (operate on mn.sim_* by default, or specify SIM=mn.sim_001)
sims_status:
	@echo "[sims_status] Listing manage.py-related processes in simulators"
	@for c in $$(docker ps --format '{{.Names}}' | grep '^mn.sim_' || true); do \
		echo "== $$c =="; \
		docker exec $$c sh -c "ps -eo pid,cmd | grep -E 'manage.py|send_telemetry|runserver' | grep -v grep || echo '  <no manage.py processes>'" || true; \
	done

sims_call:
	@if [ -z "$(ARGS)" ]; then echo "[USO] make sims_call ARGS='--randomize --memory' [SIM=mn.sim_001]"; exit 1; fi
	@for c in $$(if [ -n "$(SIM)" ]; then echo $(SIM); else docker ps --format '{{.Names}}' | grep '^mn.sim_' || true; fi); do \
		echo "[sims_call] Starting send_telemetry in $$c with args: $(ARGS)"; \
		docker exec $$c sh -c "cd /iot_simulator && nohup python manage.py send_telemetry $(ARGS) > /iot_simulator/send_telemetry.out 2>&1 & echo \$$! >/tmp/send_telemetry.pid" || echo "[WARN] failed to exec in $$c"; \
	done

sims_stop:
	@for c in $$(if [ -n "$(SIM)" ]; then echo $(SIM); else docker ps --format '{{.Names}}' | grep '^mn.sim_' || true; fi); do \
		echo "[sims_stop] Stopping send_telemetry in $$c"; \
		docker exec $$c sh -c "pkill -f 'manage.py send_telemetry' || true; rm -f /tmp/send_telemetry.pid || true" || true; \
	done

sims_kill:
	@for c in $$(if [ -n "$(SIM)" ]; then echo $(SIM); else docker ps --format '{{.Names}}' | grep '^mn.sim_' || true; fi); do \
		echo "[sims_kill] Killing send_telemetry in $$c"; \
		docker exec $$c sh -c "pkill -9 -f 'manage.py send_telemetry' || true; rm -f /tmp/send_telemetry.pid || true" || true; \
	done

# -- MiddTS helpers (operate on mn.middts by default)
middts_status:
	@echo "[middts_status] Listing processes related to middts (gunicorn/manage.py)"
	@for c in $$(if [ -n "$(SIM)" ]; then echo $(SIM); else echo mn.middts; fi); do \
		echo "== $$c =="; \
		docker exec $$c sh -c "ps -eo pid,cmd | grep -E 'gunicorn|manage.py|runserver|middts' | grep -v grep || echo '  <no middts processes>'" || true; \
	done

middts_call:
	@if [ -z "$(ARGS)" ]; then echo "[USO] make middts_call ARGS='--some-args' [SIM=mn.middts]"; exit 1; fi
	@for c in $$(if [ -n "$(SIM)" ]; then echo $(SIM); else echo mn.middts; fi); do \
		echo "[middts_call] Running command in $$c: python manage.py $(ARGS)"; \
		docker exec $$c sh -c "cd /middleware-dt && nohup python manage.py $(ARGS) > /middleware-dt/call.out 2>&1 & echo \$$! >/tmp/middts_call.pid" || echo "[WARN] failed to exec in $$c"; \
	done

middts_stop:
	@for c in $$(if [ -n "$(SIM)" ]; then echo $(SIM); else echo mn.middts; fi); do \
		echo "[middts_stop] Stopping manage.py-related processes in $$c"; \
		docker exec $$c sh -c "pkill -f 'manage.py' || true; rm -f /tmp/middts_call.pid || true" || true; \
	done

middts_kill:
	@for c in $$(if [ -n "$(SIM)" ]; then echo $(SIM); else echo mn.middts; fi); do \
		echo "[middts_kill] Killing manage.py-related processes in $$c"; \
		docker exec $$c sh -c "pkill -9 -f 'manage.py' || true; rm -f /tmp/middts_call.pid || true" || true; \
	done

# Recreate a single container by removing it; does not attempt to recreate automatically.
# Usage: make recreate-container SERVICE=tb
.PHONY: recreate-container
recreate-container:
	@if [ -z "$(SERVICE)" ]; then echo "[USO] make recreate-container SERVICE=tb (removerá mn.<service>)"; exit 1; fi
	@echo "[🔁] Recriando container mn.$(SERVICE) -> removendo container atual (se existir)"
	-docker rm -f mn.$(SERVICE) || true
	@echo "[🔁] mn.$(SERVICE) removido. Para recriar o serviço, execute o comando de topologia (ex: make topo) ou o pipeline de deploy apropriado."

# === RESTORE ON-DEMAND (middts + simulators) ===
.PHONY: restore-scenario restore-middts restore-simulators restore-sim

# High-level: restore everything needed for the scenario (middts DB + all simulator sqlite files)
restore-scenario: restore-middts restore-simulators

# Restore middts DB: drop/create middts and import services/middleware-dt/middts.sql
# Requires that the Postgres container be running as 'mn.db' and docker CLI available.
restore-middts:
	@echo "[RESTORE] Delegating middts restore to scripts/restore_middts.sh"; \
	@chmod +x scripts/restore_middts.sh; scripts/restore_middts.sh

# Restore all simulator sqlite files by copying the initial template into the host file mounted into each simulator.
# This assumes simulators mount the host file services/iot_simulator/db.sqlite3 into /iot_simulator/db.sqlite3
restore-simulators:
	@echo "[RESTORE] Restoring simulator sqlite DBs (host file services/iot_simulator/db.sqlite3 will be replaced)"
	@if [ ! -f services/iot_simulator/initial_data/db_scenario.sqlite3 ]; then echo "[ERRO] services/iot_simulator/initial_data/db_scenario.sqlite3 not found"; exit 1; fi
	@cp services/iot_simulator/initial_data/db_scenario.sqlite3 services/iot_simulator/db.sqlite3 || (echo "[ERRO] copy failed"; exit 1); \
	chmod 666 services/iot_simulator/db.sqlite3 || true; \
	echo "[RESTORE] host simulator DB replaced. Restart simulators/entrypoints if necessary."

# Restore single simulator (useful for per-sim debugging). Usage: make restore-sim SIM=mn.sim_001
restore-sim:
	@if [ -z "$(SIM)" ]; then echo "[USO] make restore-sim SIM=mn.sim_001"; exit 1; fi
	@echo "[RESTORE] Restoring simulator $(SIM) sqlite DB from services/iot_simulator/initial_data/db_scenario.sqlite3"
	@if [ ! -f services/iot_simulator/initial_data/db_scenario.sqlite3 ]; then echo "[ERRO] services/iot_simulator/initial_data/db_scenario.sqlite3 not found"; exit 1; fi
	@cp services/iot_simulator/initial_data/db_scenario.sqlite3 services/iot_simulator/db.sqlite3 || (echo "[ERRO] copy failed"; exit 1); \
	chmod 666 services/iot_simulator/db.sqlite3 || true; \
	echo "[RESTORE] host simulator DB replaced. If $(SIM) is running, restart its entrypoint inside the container: make exec-sim SIM=$(SIM) CMD='kill 1 && /entrypoint.sh &'"

# Teste de rede geral
check-network:
	@echo "[🔎] Testando conectividade de rede entre todos os containers principais"
	@echo "[tb] IPs e interfaces:"
	docker exec -it mn.tb ip addr || echo "[ERRO] Falha ao obter IP do tb"
	@echo "[middts] IPs e interfaces:"
	docker exec -it mn.middts ip addr || echo "[ERRO] Falha ao obter IP do middts"
	@echo "[db] IPs e interfaces:"
	docker exec -it mn.db ip addr || echo "[ERRO] Falha ao obter IP do db"
	@echo "[influxdb] IPs e interfaces:"
	docker exec -it mn.influxdb ip addr || echo "[ERRO] Falha ao obter IP do influxdb"
	@echo "[neo4j] IPs e interfaces:"
	docker exec -it mn.neo4j ip addr || echo "[ERRO] Falha ao obter IP do neo4j"
	@echo "[parser] IPs e interfaces:"
		@if docker ps --format '{{.Names}}' | grep -q '^mn.parser$$'; then \
			docker exec -it mn.parser ip addr || echo "[ERRO] Falha ao obter IP do parser"; \
		elif docker ps --format '{{.Names}}' | grep -q '^parser$$'; then \
			echo "[ℹ️] Parser está rodando como container externo 'parser'"; docker port parser || true; \
			echo "[ℹ️] Parser é externo — não é possível exibir interfaces internas da topologia."; \
		else \
			echo "[WARN] Nenhum container parser detectado (mn.parser ou parser)"; \
		fi
	@echo "[tb <-> middts] ping e TCP"
	docker exec -it mn.tb ping -c 2 10.10.2.2 || echo "[ERRO] tb não pinga middts"
	docker exec -it mn.middts ping -c 2 10.10.1.2 || echo "[ERRO] middts não pinga tb"
	docker exec -it mn.tb bash -c 'nc -vz -w 2 10.10.2.2 8000' || echo "[ERRO] tb não conecta TCP 8000 em middts"
	docker exec -it mn.middts bash -c 'nc -vz -w 2 10.10.1.2 8080' || echo "[ERRO] middts não conecta TCP 8080 em tb"
	@echo "[tb <-> db] ping e TCP"
	docker exec -it mn.tb ping -c 2 10.10.1.10 || echo "[ERRO] tb não pinga db"
	docker exec -it mn.db ping -c 2 10.10.1.2 || echo "[ERRO] db não pinga tb"
	docker exec -it mn.tb bash -c 'nc -vz -w 2 10.10.1.10 5432' || echo "[ERRO] tb não conecta TCP 5432 em db"
	docker exec -it mn.db bash -c 'nc -vz -w 2 10.10.1.2 8080' || echo "[ERRO] db não conecta TCP 8080 em tb"
	@echo "[middts <-> db] ping e TCP"
	docker exec -it mn.middts ping -c 2 10.10.2.10 || echo "[ERRO] middts não pinga db"
	docker exec -it mn.db ping -c 2 10.10.2.2 || echo "[ERRO] db não pinga middts"
	docker exec -it mn.middts bash -c 'nc -vz -w 2 10.10.2.10 5432' || echo "[ERRO] middts não conecta TCP 5432 em db"
	docker exec -it mn.db bash -c 'nc -vz -w 2 10.10.2.2 8000' || echo "[ERRO] db não conecta TCP 8000 em middts"
	@echo "[middts <-> influxdb] ping e TCP"
	docker exec -it mn.middts ping -c 2 10.10.2.20 || echo "[ERRO] middts não pinga influxdb"
	docker exec -it mn.influxdb ping -c 2 10.10.2.2 || echo "[ERRO] influxdb não pinga middts"
	docker exec -it mn.middts bash -c 'nc -vz -w 2 10.10.2.20 8086' || echo "[ERRO] middts não conecta TCP 8086 em influxdb"
	docker exec -it mn.influxdb bash -c 'nc -vz -w 2 10.10.2.2 8000' || echo "[ERRO] influxdb não conecta TCP 8000 em middts"
	@echo "[middts <-> neo4j] ping e TCP"
	docker exec -it mn.middts ping -c 2 10.10.2.30 || echo "[ERRO] middts não pinga neo4j"
	docker exec -it mn.neo4j ping -c 2 10.10.2.2 || echo "[ERRO] neo4j não pinga middts"
	docker exec -it mn.middts bash -c 'nc -vz -w 2 10.10.2.30 7474' || echo "[ERRO] middts não conecta TCP 7474 em neo4j"
	@echo "[middts <-> parser] ping e TCP"
	@if docker ps --format '{{.Names}}' | grep -q '^mn.parser$$'; then \
		docker exec -it mn.middts ping -c 2 10.10.2.40 || echo "[ERRO] middts não pinga parser"; \
		docker exec -it mn.parser ping -c 2 10.10.2.2 || echo "[ERRO] parser não pinga middts"; \
		docker exec -it mn.middts bash -c 'nc -vz -w 2 10.10.2.40 8080' || echo "[ERRO] middts não conecta TCP 8080 em parser"; \
	elif docker ps --format '{{.Names}}' | grep -q '^parser$$'; then \
		echo "[ℹ️] Parser rodando externamente — teste de conectividade via host:"; \
		echo "nc -z -v -w 2 127.0.0.1 8082"; \
	else \
		echo "[WARN] Nenhum parser detectado para testar (mn.parser ou parser)"; \
	fi
	@echo "[Simuladores <-> tb] ping e TCP"
	for i in 1 2 3 4 5; do \
	  sim_ip="10.10.$$((10+i)).2"; \
	  tb_ip="10.10.1.2"; \
	  docker exec -it mn.tb ping -c 2 $$sim_ip || echo "[ERRO] tb não pinga sim_$$i"; \
	  docker exec -it mn.sim_`printf '%03d' $$i` ping -c 2 $$tb_ip || echo "[ERRO] sim_$$i não pinga tb"; \
	  docker exec -it mn.tb bash -c "nc -vz -w 2 $$sim_ip 5000" || echo "[ERRO] tb não conecta TCP 5000 em sim_$$i"; \
	  docker exec -it mn.sim_`printf '%03d' $$i` bash -c "nc -vz -w 2 $$tb_ip 8080" || echo "[ERRO] sim_$$i não conecta TCP 8080 em tb"; \
	done
