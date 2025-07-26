include .env

.PHONY: setup install net net-qos net-qos-screen net-qos-detach net-qos-interactive net-clean net-cli net-screen-kill net-sessions net-status \
        thingsboard run reset clean uninstall sims-start sims-stop sims-call sims-call-all

# 🔧 Setup dos repositórios
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

# 📦 Instalação de pacotes necessários
install:
	@echo "[✓] Instalando dependências: Mininet, Docker, Socat..."
	sudo apt update
	sudo apt install -y mininet docker.io docker-compose socat net-tools openjdk-11-jdk graphviz xdot screen

# 🔁 Topologia básica
net:
	@echo "[✓] Iniciando topologia Mininet básica..."
	sudo python3 mininet/topo.py

# ⚙️ Criação da topologia com QoS (em segundo plano com screen)
net-qos:
	@echo "[✓] Iniciando topologia Mininet com QoS Slices (detach)..."
	@screen -dmS mininet-session sudo python3 mininet/topo_qos.py

# 👨‍💻 Criação da topologia com CLI ativa (modo interativo)
net-qos-interactive:
	@echo "[🧩] Rodando topo_qos.py diretamente (modo interativo)..."
	sudo python3 mininet/topo_qos.py

# 📺 Criação da topologia com CLI dentro de uma screen (anexada)
net-qos-screen:
	@echo "[🧠] Rodando topo_qos.py dentro de screen 'mininet-session'..."
	screen -S mininet-session sudo python3 mininet/topo_qos.py

# 🧼 Limpeza da topologia
net-clean:
	@echo "[🧼] Limpando topologia Mininet anterior..."
	sudo mn -c

# 💻 Acessar CLI da screen se ativa
net-cli:
	@echo "[🖥️] Acessando CLI do Mininet (screen)..."
	screen -r mininet-session || echo "Mininet não está rodando. Use 'make net-qos-screen' ou 'make net-qos-interactive'."

# 💣 Matar screen da topologia
net-screen-kill:
	@echo "[💥] Matando screen 'mininet-session'..."
	screen -S mininet-session -X quit

# 📋 Listar sessões screen
net-sessions:
	@echo "[📋] Sessões screen ativas:"
	screen -ls

# 🔍 Verificar status da sessão screen
net-status:
	@echo "[🔍] Verificando se screen 'mininet-session' está ativa..."
	screen -ls | grep mininet-session || echo "Nenhuma sessão ativa."

# 📋 Listar hosts e switches do Mininet
net-list:
	@echo "[📋] Listando Hosts e Switches Mininet..."
	@echo "Hosts:"
	@ip netns list | awk '{print " - " $$1}' | grep -E '^ - (tb|middts|sim_)'
	@echo "Switches (do sistema):"
	@sudo ovs-vsctl list-br | awk '{print " - " $$1}'

# 🔍 Acessar um host específico no namespace do Mininet
net-enter:
	@if [ -z "$(host)" ]; then \
		echo "[❌] Informe o host com 'make net-enter host=sim_001'"; \
	else \
		echo "[🔍] Acessando host $(host)..."; \
		sudo ip netns exec $(host) bash || echo "[❌] Host $(host) não encontrado."; \
	fi

# 📡 Executar comando ping entre dois hosts
net-ping:
	@if [ -z "$(from)" ] || [ -z "$(to)" ]; then \
		echo "[❌] Use: make net-ping from=sim_001 to=tb"; \
	else \
		echo "[📡] Ping de $(from) para $(to):"; \
		sudo ip netns exec $(from) ping -c 4 $(to) || echo "[❌] Erro ao executar ping."; \
	fi

# 📡 Instalação do ThingsBoard dentro do host tb
thingsboard:
	@echo "[✓] Instalando ThingsBoard no host tb (Mininet)..."
	mininet> tb ./install_thingsboard_in_namespace.sh

# 🚀 Subida de containers (MidDiTS, TB, Simuladores)
run:
	@echo "[🚀] Iniciando containers do experimento..."
	docker-compose up -d

# 🔄 Reset geral
reset:
	@echo "[🧼] Resetando ambiente: containers e Mininet..."
	sudo mn -c
	docker stop `docker ps -q` || true
	docker rm `docker ps -aq` || true

# 🧽 Limpeza de repositórios locais
clean:
	@echo "[🧽] Limpando tudo..."
	rm -rf middts simulator

# 🧹 Desinstalação completa
uninstall:
	@echo "[🧹] Executando desinstalação completa..."
	./commands/uninstall_all.sh

# 🔧 Simuladores
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

mount-shared-dirs:
	@echo "[🔗] Montando diretório compartilhado nos hosts da topologia..."
	@chmod +x scripts/*.sh
	@./scripts/mount_shared_dirs.sh

net-unmount-shared-dirs:
	@echo "[🗑️] Desmontando diretório compartilhado dos hosts..."
	@HOSTS="tb middts"; \
	for i in $(shell seq -w 1 100); do \
		HOSTS="$$HOSTS sim_$$i"; \
	done; \
	for host in $$HOSTS; do \
		if ip netns list | grep -q "^$$host"; then \
			sudo umount -l "/var/run/netns/$$host/mnt/scripts" 2>/dev/null && echo "[✓] $$host desmontado" || echo "[!] $$host já desmontado ou inexistente"; \
		else \
			echo "[!] Namespace '$$host' não encontrado. Ignorando..."; \
		fi; \
	done

