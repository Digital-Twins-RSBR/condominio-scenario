
.PHONY: setup build-images topo draw clean check-tb check-tb-internal

setup:
	@echo "[Setup] Executar ./setup.sh"

build-images:
	@echo "[🐳] Construindo imagens Docker"
	@if [ -d "middts" ]; then \
		echo "[📥] Atualizando repositório middleware-dt..."; \
		cd middts && git pull; \
	else \
		echo "[📥] Clonando repositório middleware-dt..."; \
		git clone git@github.com:Digital-Twins-RSBR/middleware-dt.git; \
		mv middleware-dt middts; \
	fi
	docker build -t middts:latest ./middts
	@if [ -d "simulator" ]; then \
		echo "[📥] Atualizando repositório iot_simulator..."; \
		cd simulator && git pull; \
	else \
		echo "[📥] Clonando repositório iot_simulator..."; \
		git clone git@github.com:Digital-Twins-RSBR/iot_simulator.git; \
		mv iot_simulator simulator; \
	fi
	docker build -t iot_simulator:latest ./simulator

topo:
	@echo "[📡] Executando topologia com Containernet"
	bash -c 'source containernet/venv/bin/activate && sudo -E env PATH="$$PATH" python3 topology/topo_qos.py'

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


check-tb:
	@echo "[🧪] Verificando ThingsBoard na porta 8080 (externo)"
	curl -I http://localhost:8080 || echo "❌ ThingsBoard não está ouvindo na porta 8080"

check-tb-internal:
	@echo "[🔍] Verificando ThingsBoard de dentro do container"
	docker exec mn.tb curl -I http://localhost:8080 || echo "❌ ThingsBoard dentro do container mn.tb não está ativo"
