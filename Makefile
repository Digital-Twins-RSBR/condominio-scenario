.PHONY: setup build-images topo draw clean

setup:
	@echo "[Setup] Limpando entradas de repositórios conflitantes..."
	sudo rm -f /etc/apt/sources.list.d/pgdg.list
	sudo rm -f /etc/apt/sources.list.d/pgdg.sources
	@echo "[Setup] Atualizando apt..."
	sudo apt update || (echo "❌ apt update falhou" && exit 1)
	@echo "[Docker] inicia Docker..."
	sudo systemctl enable docker
	sudo systemctl start docker
	@echo "[Docker] docker adiciona usuário ao grupo..."
	sudo groupadd -f docker
	sudo usermod -aG docker $(USER)
	docker context use default || true
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
