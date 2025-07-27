#!/usr/bin/env python3
import sys, os
from mininet.net import Containernet
from mininet.node import Controller, Docker
from mininet.link import TCLink
from mininet.cli import CLI
from mininet.log import setLogLevel, info
import docker

def ensure_remove(name):
    client = docker.from_env()
    try:
        c = client.containers.get(f"mn.{name}")
        info(f"*** Container '{name}' já existe. Removendo...\n")
        c.remove(force=True)
    except docker.errors.NotFound:
        pass

def run_topo(num_sims=100):
    setLogLevel('info')
    net = Containernet(controller=Controller)

    info('*** Verificando containers existentes...\n')
    ensure_remove('tb')
    ensure_remove('middts')
    for i in range(1, num_sims + 1):
        ensure_remove(f"sim_{i:03d}")

    info('*** Adding controller\n')
    net.addController('c0')

    info('*** Adding core containers\n')
    tb = net.addDocker('tb', dimage="thingsboard/tb:latest", dcmd="/bin/bash")
    middts = net.addDocker('middts', dimage="middts:latest", dcmd="/bin/bash")

    s_tb = net.addSwitch('s_tb')
    s_md = net.addSwitch('s_md')
    net.addLink(tb, s_tb)
    net.addLink(middts, s_md)
    net.addLink(s_tb, s_md, cls=TCLink, bw=100, delay='5ms')

    info('*** Adicionando simuladores...\n')
    for i in range(1, num_sims + 1):
        name = f"sim_{i:03d}"
        sim = net.addDocker(name, dimage="iot_simulator:latest", dcmd="/bin/bash")
        s = net.addSwitch(f"sw_{i:03d}")
        net.addLink(sim, s)
        net.addLink(s, s_tb, cls=TCLink, bw=10, delay='2ms')
        net.addLink(s, s_tb, cls=TCLink, bw=5, delay='20ms')
        net.addLink(s, s_tb, cls=TCLink, bw=1, delay='50ms', loss=5)
    info('*** Iniciando rede\n')
    net.start()

    CLI(net)
    net.stop()

if __name__ == "__main__":
    run_topo(num_sims=int(os.environ.get('SIMULATOR_COUNT', 100)))
