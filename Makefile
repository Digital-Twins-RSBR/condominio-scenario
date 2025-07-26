include .env

.PHONY: setup install net net-qos net-clean net-cli net-cli-host net-cli-exec net-kill \
        thingsboard run reset clean uninstall sims-start sims-stop sims-call sims-call-all

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
	sudo apt install -y mininet docker.io docker-compose socat net-tools openjdk-11-jdk graphviz xdot screen

net:
	@echo "[✓] Iniciando topologia Mininet básica..."
	sudo python3 mininet/topo.py

net-qos:
	@echo "[✓] Iniciando topologia Mininet com QoS Slices..."
	@screen -dmS mininet-session sudo python3 mininet/topo_qos.py

net-clean:
	@echo "[🧼] Limpando topologia Mininet..."
	@screen -S mininet-session -X quit || true
	sudo mn -c

net-cli:
	@echo "[🖥️] Acessando CLI do Mininet (screen)..."
	@screen -r mininet-session || echo "Mininet não está rodando. Use 'make net-qos' primeiro."

net-cli-host:
	@echo "[🖥️] Entrando no host $(HOST) pela CLI da sessão Mininet..."
	@screen -S mininet-session -p 0 -X stuff "$(HOST)\n"

net-cli-exec:
	@echo "[⚙️] Executando comando no host $(HOST): $(CMD)"
	@screen -S mininet-session -p 0 -X stuff "$(HOST) $(CMD)\n"

net-kill:
	@echo "[💀] Encerrando a sessão Mininet (kill manual)..."
	@screen -S mininet-session -X quit || echo "Nenhuma sessão ativa."
	@sudo mn -c

net-graph:
	@echo "[📊] Gerando gráfico da topologia com xdot (requer graphviz)..."
	@sudo python3 mininet/draw_topology.py | xdot - || echo "xdot ou GTK pode não estar disponível via terminal puro."

thingsboard:
	@echo "[✓] Instalando ThingsBoard no host tb (Mininet)..."
	@screen -S mininet-session -p 0 -X stuff "tb /mnt/scripts/install_thingsboard_in_namespace.sh\n"

run:
	@echo "[🚀] Iniciando containers do experimento..."
	docker-compose up -d

reset:
	@echo "[🧼] Resetando ambiente: containers e Mininet..."
	sudo mn -c
	docker stop `docker ps -q` || true
	docker rm `docker ps -aq` || true

clean:
	@echo "[🧽] Limpando diretórios de código..."
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

mount-shared:
	@echo "[📂] Montando pastas compartilhadas nos hosts..."
	sudo ./mount_shared_dirs.sh
