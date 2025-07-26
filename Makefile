.PHONY: containernet topo run clean

containernet:
	git clone https://github.com/containernet/containernet.git
	cd containernet && sudo ./install.sh

topo:
	sudo python3 containernet/topo_qos.py

run:
	sudo docker ps

clean:
	sudo mn -c
	sudo docker rm -f $(docker ps -aq) || true
