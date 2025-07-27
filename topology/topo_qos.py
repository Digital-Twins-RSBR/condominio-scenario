#!/usr/bin/env python3
import os, sys
# garante que mininet do venv seja usado
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../containernet/mininet')))
from mininet.net import Containernet
from mininet.node import Controller
from mininet.link import TCLink
from mininet.cli import CLI
from mininet.log import setLogLevel, info
import docker.errors

def run_topo(num_sims=100):
    setLogLevel('info')
    net = Containernet(controller=Controller)

    info('*** Adding controller\n')
    net.addController('c0')

    for name, dimg in [('tb', os.getenv('THINGSBOARD_IMAGE', 'thingsboard/tb:3.3.4.1-CVE22965')),
                       ('middts', 'middts:latest')]:
        try:
            info(f'*** Adding {name}\n')
            net.addDocker(name, dimage=dimg, dcmd="/bin/bash")
        except docker.errors.APIError as e:
            info(f'⚠️ Container {name} já existe: {e}\n')

    s_tb = net.addSwitch('s_tb')
    s_md = net.addSwitch('s_md')
    net.addLink(net.getNodeByName('tb'), s_tb)
    net.addLink(net.getNodeByName('middts'), s_md)
    net.addLink(s_tb, s_md, cls=TCLink, bw=100, delay='5ms')

    for i in range(1, num_sims+1):
        sim_name = f'sim_{i:03d}'
        try:
            net.addDocker(sim_name, dimage='iot_simulator:latest', dcmd='/bin/bash')
        except docker.errors.APIError:
            info(f'⚠️ {sim_name} já existe, ignorando.\n')
        sw = net.addSwitch(f'sw_{i:03d}')
        net.addLink(sim_name, sw)
        net.addLink(sw, s_tb, cls=TCLink, bw=10, delay='2ms')
        net.addLink(sw, s_tb, cls=TCLink, bw=5, delay='20ms')
        net.addLink(sw, s_tb, cls=TCLink, bw=1, delay='50ms', loss=5)

    net.start()
    info('*** Network started\n')
    CLI(net)
    net.stop()

if __name__ == "__main__":
    num = int(os.getenv('SIMULATOR_COUNT', '100'))
    run_topo(num)
