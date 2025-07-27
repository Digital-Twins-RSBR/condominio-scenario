.PHONY: setup build-images topo draw clean

setup:
	@echo "[Setup] Executando setup.sh"
	@bash setup.sh

build-images:
	@echo "[Build] Construindo imagens docker internas..."
	@docker build -t middts:latest ./middts
	@docker build -t iot_simulator:latest ./simulator

topo:
	@echo "[Topo] Iniciando topologia com Containernet..."
	@PYTHONPATH=./containernet sudo python3 topology/topo_qos.py || { echo "[ERROR] topo execution failed."; exit 1; }

draw:
	@echo "[Draw] Gerando visualização da topologia..."
	@PYTHONPATH=./containernet sudo python3 topology/draw_topology.py || { echo "[ERROR] draw execution failed."; exit 1; }

clean:
	@echo "[Clean] Limpando ambiente Mininet/Containernet..."
	@sudo mn -c || echo "[WARN] mn -c encontrou erro."
