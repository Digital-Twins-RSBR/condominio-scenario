.PHONY: setup build-images topo draw clean

setup:
	@echo "[Setup] Iniciando ambiente..."
	@./setup.sh

build-images:
	@echo "[🐳] Construindo imagens Docker..."
	@docker build -t middts:latest ./middts
	@docker build -t iot_simulator:latest ./simulator

topo:
	@echo "[📡] Executando topologia com Containernet..."
	@PYTHONPATH=./containernet sudo python3 topology/topo_qos.py

draw:
	@echo "[🖼️] Gerando visualização da topologia..."
	@PYTHONPATH=./containernet sudo python3 topology/draw_topology.py

clean:
	@echo "[🧼] Limpando ambientes Mininet antigo..."
	@sudo mn -c
