.PHONY: setup build-images topo draw clean

setup:
	@echo "[Setup] Instalando Containernet via Ansible..."
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
