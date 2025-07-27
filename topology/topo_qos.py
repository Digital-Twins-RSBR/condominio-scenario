#!/usr/bin/env python3
import os, sys

sys.path.insert(0, os.path.abspath(os.path.join(os.getcwd(), 'containernet')))

from mininet.net import Containernet
from mininet.node import Controller
from mininet.link import TCLink
from mininet.cli import CLI
from mininet.log import setLogLevel, info

def run_topo(num_sims=100):
    setLogLevel('info')
    net = Containernet(controller=Controller)

    info('*** Adding controller\n')
    net.addController('c0')

    info('*** Adding core Docker nodes\n')
    tb = net.addDocker('tb', dimage="thingsboard/tb:3.3.4.1-CVE22965", dcmd="/bin/bash")
    middts = net.addDocker('middts', dimage="middts:latest", dcmd="/bin/bash")

    s_tb = net.addSwitch('s_tb')
    s_md = net.addSwitch('s_md')

    net.addLink(tb, s_tb)
    net.addLink(middts, s_md)
    net.addLink(s_tb, s_md, cls=TCLink, bw=100, delay='5ms')

    for i in range(1, num_sims + 1):
        name = f'sim_{i:03d}'
        sim = net.addDocker(name, dimage="iot_simulator:latest", dcmd="/bin/bash")
        sw = net.addSwitch(f'sw_{i:03d}')
        net.addLink(sim, sw)
        net.addLink(sw, s_tb, cls=TCLink, bw=10, delay='2ms')
        net.addLink(sw, s_tb, cls=TCLink, bw=5, delay='20ms')
        net.addLink(sw, s_tb, cls=TCLink, bw=1, delay='50ms', loss=5)

    net.start()
    info('*** Network started\n')
    CLI(net)
    net.stop()

if __name__ == "__main__":
    run_topo()
