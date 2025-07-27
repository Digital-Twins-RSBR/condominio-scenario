.PHONY: setup build-images topo draw clean

setup:
	@echo "[Makefile] Executando setup via script"
	@./setup.sh

build-images:
	@echo "[🐳] Construindo imagens Docker do MidDiTS e IoT Simulator"
	docker build -t middts:latest ./middts
	docker build -t iot_simulator:latest ./simulator

topo:
	@echo "[📡] Executando topologia com Containernet"
ifndef NUM_SIMS
	$(error NUM_SIMS não definido. Ex.: make topo NUM_SIMS=50)
endif
	@PYTHONPATH=./containernet sudo python3 topology/topo_qos.py $(NUM_SIMS)

draw:
	@echo "[🖼️] Gerando representação da topologia (draw)"
	@PYTHONPATH=./containernet sudo python3 topology/draw_topology.py $(NUM_SIMS)

clean:
	@echo "[🧼] Limpando ambiente Mininet"
	@sudo mn -c
