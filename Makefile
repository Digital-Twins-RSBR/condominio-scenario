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

MIDDTS_PATH = services/middts/middts
SIMULATOR_PATH = services/simulator/simulator
DOCKER_PATH = services/docker
# === SETUP E LIMPEZA ===
.PHONY: setup clean clean-veth clean-containers reset-db reset-tb

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

clean-veth:
	@echo "[🧯] Limpando interfaces veth Mininet/Containernet"
	@ip -o link show | awk -F': ' '{print $$2}' | cut -d'@' -f1 | grep -E '^(mn-|sim_|s[0-9]+-eth[0-9]+)' | sort | uniq | xargs -r -n1 sudo ip link delete || true

clean-containers:
	docker ps -a --filter "name=mn." -q | xargs -r docker rm -f

reset-db:
	@echo "Removendo volume do banco de dados ThingsBoard (db_data)..."
	-docker volume rm db_data
	@echo "Volume removido. O banco será recriado limpo no próximo start."

reset-tb:
	@echo "Removendo volumes do ThingsBoard (db_data, tb_assets, tb_logs)..."
	-docker volume rm db_data tb_assets tb_logs
	@echo "Volumes removidos. O banco e dados do TB serão recriados limpos no próximo start."

# === BUILD DE IMAGENS ===
.PHONY: build-images

build-images:
	@echo "[🐳] Construindo imagens Docker personalizadas"
	docker build -t $(MIDDTS_IMAGE) -f $(MIDDTS_PATH)/Dockerfile $(MIDDTS_PATH)
	docker build -t $(MIDDTS_CUSTOM_IMAGE) -f $(DOCKER_PATH)/Dockerfile.middts $(MIDDTS_PATH)
	docker build -t $(IOT_SIM_IMAGE) -f $(SIMULATOR_PATH)/Dockerfile $(SIMULATOR_PATH)
	docker build -t $(TB_IMAGE) -f $(DOCKER_PATH)/Dockerfile.tb services/
	docker build -t $(PG_IMAGE) -f $(DOCKER_PATH)/Dockerfile.pg13 services/
	docker build -t $(NEO4J_IMAGE) -f $(DOCKER_PATH)/Dockerfile.neo4j services/middts
	docker build -t $(PARSER_IMAGE) -f $(DOCKER_PATH)/Dockerfile.parser services/middts
	docker build -t $(INFLUX_IMAGE) -f $(DOCKER_PATH)/Dockerfile.influx services/middts
	
# === TOPOLOGIA E VISUALIZAÇÃO ===
.PHONY: topo topo-debug topo-screen draw

topo:
	@echo "[📡] Executando topologia com Containernet"
	bash -c 'source services/containernet/venv/bin/activate && sudo -E env PATH="$$PATH" python3 services/topology/topology/topo_qos.py'

topo-debug:
	@echo "[📡] Executando topologia com Containernet"
	bash -c 'source services/containernet/venv/bin/activate && sudo -E env PATH="$$PATH" python3 services/topology/topology/topo_qos_debug.py'

topo-screen:
	@echo "[📡] Executando topologia com Containernet em screen"
	screen -S containernet -dm bash -c 'source services/containernet/venv/bin/activate && sudo -E env PATH="$$PATH" python3 services/topology/topology/topo_qos.py'
	@echo "Use: screen -r containernet  para acessar o CLI do Containernet"

draw:
	@echo "[🖼️ ] Gerando visualização da topologia"
	bash -c 'python3 services/topology/topology/draw_topology.py'

# === VERIFICAÇÕES DE STATUS E REDE ===
.PHONY: check-tb check-middts check-db check-influxdb check-neo4j check-parser check-simulator check-simulators check-network check-tb-internal

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
	docker ps --format '{{.Names}}' | grep -q '^mn.parser$$' && echo "✅ Container mn.parser está rodando" || echo "❌ Container mn.parser não está rodando"
	@echo "[🔎] Verificando serviço Parser (porta 8080)"
	docker exec -it mn.parser bash -c 'nc -z -w 2 127.0.0.1 8080' && echo "✅ Parser ouvindo na porta 8080" || echo "❌ Parser não está ouvindo na porta 8080"
	@echo "[🔎] Testando comunicação com middts"
	docker exec -it mn.parser ping -c 2 10.10.2.2 || echo "[ERRO] parser não pinga middts"
	docker exec -it mn.parser bash -c 'nc -vz -w 2 10.10.2.2 8000' || echo "[ERRO] parser não conecta TCP 8000 em middts"

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
	docker exec -it mn.parser ip addr || echo "[ERRO] Falha ao obter IP do parser"
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
	docker exec -it mn.middts ping -c 2 10.10.2.40 || echo "[ERRO] middts não pinga parser"
	docker exec -it mn.parser ping -c 2 10.10.2.2 || echo "[ERRO] parser não pinga middts"
	docker exec -it mn.middts bash -c 'nc -vz -w 2 10.10.2.40 8080' || echo "[ERRO] middts não conecta TCP 8080 em parser"
	@echo "[Simuladores <-> tb] ping e TCP"
	for i in 1 2 3 4 5; do \
	  sim_ip="10.10.$$((10+i)).2"; \
	  tb_ip="10.10.1.2"; \
	  docker exec -it mn.tb ping -c 2 $$sim_ip || echo "[ERRO] tb não pinga sim_$$i"; \
	  docker exec -it mn.sim_`printf '%03d' $$i` ping -c 2 $$tb_ip || echo "[ERRO] sim_$$i não pinga tb"; \
	  docker exec -it mn.tb bash -c "nc -vz -w 2 $$sim_ip 5000" || echo "[ERRO] tb não conecta TCP 5000 em sim_$$i"; \
	  docker exec -it mn.sim_`printf '%03d' $$i` bash -c "nc -vz -w 2 $$tb_ip 8080" || echo "[ERRO] sim_$$i não conecta TCP 8080 em tb"; \
	done
