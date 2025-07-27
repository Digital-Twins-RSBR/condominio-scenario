.PHONY: setup build-images topo draw clean

setup:
	@echo "[✓] Configurando ambiente Containernet"
	sudo apt update
	sudo apt install -y ansible git python3-pip python3-venv docker.io
	@if [ ! -d containernet ]; then git clone https://github.com/containernet/containernet.git; fi
	cd containernet && sudo ansible-playbook -i "localhost," -c local ansible/install.yml

build-images:
	@echo "[🐳] Construindo imagens"
	docker build -t middts:latest ./middts
	docker build -t iot_simulator:latest ./simulator

topo:
	@echo "[📡] Executando topologia Containernet"
	source containernet/venv/bin/activate && sudo -E python3 topology/topo_qos.py

draw:
	@echo "[🖼️] Gerando gráfico da topologia"
	source containernet/venv/bin/activate && sudo -E python3 topology/draw_topology.py

clean:
	@echo "[🧼] Limpando ambiente Mininet"
	sudo mn -c
