.PHONY: setup topo clean

setup:
	@echo "[✓] Configurando ambiente..."
	sudo apt update
	sudo apt install -y ansible git python3-pip python3-venv
	@if [ ! -d "containernet" ]; then \
		git clone https://github.com/containernet/containernet.git; \
	fi
	cd containernet && sudo ansible-playbook -i "localhost," -c local ansible/install.yml

topo:
	@echo "[📡] Executando topologia com Containernet..."
	PYTHONPATH=containernet sudo python3 topology/topo_qos.py

draw:
	@echo "[📡] Executando draw topologia..."
	PYTHONPATH=containernet sudo python3 topology/draw_topology.py

clean:
	sudo mn -c
