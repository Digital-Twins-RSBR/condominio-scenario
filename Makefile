.PHONY: setup install-docker build-images topo draw clean

setup: install-docker
    @echo "[✓] Setup completo. Pronto para build-images."

install-docker:
    @echo "[Setup] Instalando Docker e repositórios"
    ./setup.sh

build-images:
    @echo "[🐳] Construindo imagens locais MiddTS e IoT Simulator"
    docker build -t middts:latest ./middts
    docker build -t iot_simulator:latest ./simulator

topo:
    @echo "[📡] Executando topologia com Containernet"
    sudo python3 topology/topo_qos.py

draw:
    @echo "[🖼️] Gerando visualização da topologia"
    sudo python3 topology/draw_topology.py

clean:
    @echo "[🧼] Limpando ambiente Mininet"
    sudo mn -c
