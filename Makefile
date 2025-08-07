check-network:
	@echo "[🔎] Testando conectividade de rede entre containers (tb, tb-db, middts)"
	@echo "[tb] IPs e interfaces:"
	docker exec -it mn.tb ip addr || echo "[ERRO] Falha ao obter IP do tb"
	@echo "[tb-db] IPs e interfaces:"
	docker exec -it mn.tb-db ip addr || echo "[ERRO] Falha ao obter IP do tb-db"
	@echo "[middts] IPs e interfaces:"
	docker exec -it mn.middts ip addr || echo "[ERRO] Falha ao obter IP do middts"

	@echo "[tb] ping tb-db (10.0.0.10):"
	docker exec -it mn.tb ping -c 4 10.0.0.10 || echo "[ERRO] tb não consegue pingar tb-db"

	@echo "[tb-db] ping tb (10.0.0.11):"
	docker exec -it mn.tb-db ping -c 4 10.0.0.11 || echo "[ERRO] tb-db não consegue pingar tb"

	@echo "[tb] ping middts:"
	docker exec -it mn.tb ping -c 4 mn.middts || echo "[ERRO] tb não consegue pingar middts (por nome)"

	@echo "[tb-db] ping middts:"
	docker exec -it mn.tb-db ping -c 4 mn.middts || echo "[ERRO] tb-db não consegue pingar middts (por nome)"

	@echo "[tb] Testando TCP para Postgres (10.0.0.10:5432):"
	docker exec -it mn.tb bash -c 'nc -vz -w 2 10.0.0.10 5432' || echo "[ERRO] tb não conecta TCP 5432 em tb-db"

	@echo "[tb] Testando TCP para middts (8000):"
	docker exec -it mn.tb bash -c 'nc -vz -w 2 mn.middts 8000' || echo "[ERRO] tb não conecta TCP 8000 em middts"

	@echo "[middts] ping tb:"
	docker exec -it mn.middts ping -c 4 10.0.0.11 || echo "[ERRO] middts não consegue pingar tb"

	@echo "[middts] ping tb-db:"
	docker exec -it mn.middts ping -c 4 10.0.0.10 || echo "[ERRO] middts não consegue pingar tb-db"

	@echo "[middts] Testando TCP para tb-db (5432):"
	docker exec -it mn.middts bash -c 'nc -vz -w 2 10.0.0.10 5432' || echo "[ERRO] middts não conecta TCP 5432 em tb-db"

	@echo "[middts] Testando TCP para tb (8080):"
	docker exec -it mn.middts bash -c 'nc -vz -w 2 10.0.0.11 8080' || echo "[ERRO] middts não conecta TCP 8080 em tb"

.PHONY: setup build-images topo draw clean check-tb check-tb-internal

setup:
	@echo "[Setup] Executar ./setup.sh"
	./setup.sh

build-images:
	@echo "[🐳] Construindo imagens Docker"
	docker build -t middts:latest ./middts
	docker build -t iot_simulator:latest ./simulator
	docker build -t tb-node-custom -f Dockerfile.tb .
	docker build -t postgres:13-tools -f Dockerfile.pg13 .


topo:
	@echo "[📡] Executando topologia com Containernet"
	bash -c 'source containernet/venv/bin/activate && sudo -E env PATH="$$PATH" python3 topology/topo_qos.py'

topo-debug:
	@echo "[📡] Executando topologia com Containernet"
	bash -c 'source containernet/venv/bin/activate && sudo -E env PATH="$$PATH" python3 topology/topo_qos_debug.py'

topo-screen:
	@echo "[📡] Executando topologia com Containernet em screen"
	screen -S containernet -dm bash -c 'source containernet/venv/bin/activate && sudo -E env PATH="$$PATH" python3 topology/topo_qos.py'
	@echo "Use: screen -r containernet  para acessar o CLI do Containernet"

draw:
	@echo "[🖼️ ] Gerando visualização da topologia"
	bash -c 'python3 topology/draw_topology.py'

clean:
	@echo "[🧼] Limpando ambiente Mininet/Containernet e containers órfãos"
	# Limpa rede do Mininet
	-sudo mn -c || echo "[WARN] mn -c falhou"

	# Remove containers Docker do Mininet/Containernet
	-docker ps -a --filter "name=mn." -q | xargs -r docker rm -f

	# Remove redes Docker do Mininet/Containernet
	-docker network ls --filter "name=mn." -q | xargs -r docker network rm

	# Remove volumes Docker do Mininet/Containernet
	-docker volume ls --filter "name=mn." -q | xargs -r docker volume rm

	# Apenas interfaces criadas pelo Mininet que começam com 'mn-' ou 'sim_'
	# -ip link show | awk -F': ' '{print $2}' | grep -E '^sim_|^mn-' | xargs -r -n1 sudo ip link delete || true

	@echo "[🧯] Limpando interfaces de rede restantes"
	-ip -o link show | awk -F': ' '{print $$2}' | grep -E '^(mn-|sim_|s[0-9]+-eth[0-9]+)' | xargs -r -n1 sudo ip link delete

clean-veth:
	@echo "[🧯] Limpando interfaces veth Mininet/Containernet"
	@ip -o link show | awk -F': ' '{print $$2}' | cut -d'@' -f1 | grep -E '^(mn-|sim_|s[0-9]+-eth[0-9]+)' | sort | uniq | xargs -r -n1 sudo ip link delete || true

check-tb:
	@echo "[🔎] Verificando ThingsBoard (porta 8080)"
	@curl -fsI http://localhost:8080 > /dev/null && echo "✅ ThingsBoard OK" || echo "❌ ThingsBoard não está ouvindo"

check-db:
	@echo "[🔎] Verificando PostgreSQL (porta 5432)"
	@pg_isready -h 127.0.0.1 -p 5432 -U tb && echo "✅ PostgreSQL OK" || echo "❌ PostgreSQL não está ouvindo"

check-middts:
	@echo "[🔎] Verificando MidDiTS (porta 8000)"
	@curl -fsI http://localhost:8000 > /dev/null && echo "✅ MidDiTS OK" || echo "❌ MidDiTS não está ouvindo"

check-simulators:
	@echo "[🔎] Verificando simuladores IoT (porta 5000 em cada sim_*)"
	@for c in $$(docker ps --format '{{.Names}}' | grep '^mn.sim_'); do \
		ip=$$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $$c); \
		if curl -fsI http://$$ip:5000 > /dev/null; then \
			echo "✅ $$c OK ($$ip:5000)"; \
		else \
			echo "❌ $$c não responde em $$ip:5000"; \
		fi; \
	done

clean-containers:
	docker ps -a --filter "name=mn." -q | xargs -r docker rm -f

reset-db:
    @echo "Removendo volume do banco de dados ThingsBoard (tb_db_data)..."
    -docker volume rm tb_db_data
    @echo "Volume removido. O banco será recriado limpo no próximo start."

reset-tb:
    @echo "Removendo volumes do ThingsBoard (tb_db_data, tb_assets, tb_logs)..."
    -docker volume rm tb_db_data tb_assets tb_logs
    @echo "Volumes removidos. O banco e dados do TB serão recriados limpos no próximo start."