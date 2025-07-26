include .env

.PHONY: setup install net net-qos thingsboard run reset clean uninstall sims-start sims-stop sims-call sims-call-all

setup:
	@echo "[✓] Verificando repositórios MidDiTS e Simulator..."

	@if [ "$(USE_SSH)" = "true" ]; then \
		MIDDTS_URL=git@github.com:Digital-Twins-RSBR/middleware-dt.git; \
		SIMULATOR_URL=git@github.com:Digital-Twins-RSBR/iot_simulator.git; \
	else \
		MIDDTS_URL=$(MIDDTS_REPO_URL); \
		SIMULATOR_URL=$(SIMULATOR_REPO_URL); \
	fi; \
	\
	if [ ! -d "middts" ]; then \
		echo "[→] Clonando MidDiTS..."; \
		git clone $$MIDDTS_URL middts; \
	else \
		echo "[↻] Atualizando MidDiTS..."; \
		cd middts && git checkout main && git pull; \
	fi; \
	\
	if [ ! -d "simulator" ]; then \
		echo "[→] Clonando Simulator..."; \
		git clone $$SIMULATOR_URL simulator; \
	else \
		echo "[↻] Atualizando Simulator..."; \
		cd simulator && git checkout main && git pull; \
	fi

install:
	@echo "[✓] Instalando dependências: Mininet, Docker, Socat..."
	sudo apt update
	sudo apt install -y mininet docker.io docker-compose socat net-tools openjdk-11-jdk

net:
	@echo "[✓] Iniciando topologia Mininet básica..."
	sudo python3 mininet/topo.py

net-qos:
	@echo "[✓] Iniciando topologia Mininet com QoS Slices..."
	sudo python3 mininet/topo_qos.py

net-clean:
	@echo "[🧼] Limpando topologia Mininet anterior..."
	sudo mn -c

thingsboard:
	@echo "[✓] Instalando ThingsBoard no host tb (Mininet)..."
	mininet> tb ./install_thingsboard_in_namespace.sh

run:
	@echo "[🚀] Iniciando containers do experimento..."
	docker-compose up -d

reset:
	@echo "[🧼] Resetando ambiente: containers e Mininet..."
	sudo mn -c
	docker stop `docker ps -q` || true
	docker rm `docker ps -aq` || true

clean:
	@echo "[🧽] Limpando tudo..."
	rm -rf middts simulator

uninstall:
	@echo "[🧹] Executando desinstalação completa..."
	./commands/uninstall_all.sh

sims-start:
	@echo "[🚀] Subindo todos os simuladores..."
	./commands/manage_simulators.sh start

sims-stop:
	@echo "[🛑] Parando todos os simuladores..."
	./commands/manage_simulators.sh stop

sims-call:
	@echo "[⚙️] Executando comando nos simuladores selecionados..."
	./commands/manage_simulators.sh call $(ARGS)

sims-call-all:
	@echo "[⚙️] Executando comando em todos os simuladores..."
	./commands/manage_simulators.sh call_all $(ARGS)
