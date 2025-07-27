.PHONY: setup build-images topo draw clean

setup:
	@echo "[Setup] Limpando cache apt e configurando PostgreSQL..."
	sudo rm -rf /var/lib/apt/lists/* && sudo apt clean
	@echo "🔧 Adicionando chave PostgreSQL e configurando repositório..."
	sudo curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
	    | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.asc
	. /etc/os-release && \
	sudo sh -c "echo 'deb [signed-by=/etc/apt/trusted.gpg.d/postgresql.asc] https://apt.postgresql.org/pub/repos/apt $${VERSION_CODENAME}-pgdg main' \
	   > /etc/apt/sources.list.d/pgdg.list"
	@echo "📦 Executando apt update..."
	sudo apt update
	cd containernet && ansible-playbook -i "localhost," -c local ansible/install.yml

build-images:
	@echo "[🐳] Construindo imagens MidDiTS e IoT Simulator..."
	docker build -t middts:latest ./middts
	docker build -t iot_simulator:latest ./simulator

topo:
	@echo "[📡] Executando topologia com Containernet..."
	PYTHONPATH=containernet sudo python3 topology/topo_qos.py

draw:
	@echo "[🖼️] Gerando visualização da topologia..."
	PYTHONPATH=containernet sudo python3 topology/draw_topology.py

clean:
	@echo "[🧼] Limpeza Mininet..."
	sudo mn -c
