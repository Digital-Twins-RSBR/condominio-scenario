#!/usr/bin/env python3
import sys
import os

from time import sleep
from mininet.log import setLogLevel, info
from mininet.cli import CLI

# Insere path para a versão local do Containernet
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../containernet')))

from mininet.net import Containernet
from mininet.node import Controller, Docker
from mininet.link import TCLink
from docker.errors import NotFound, APIError
import docker

def ensure_image(client, name):
    try:
        client.images.get(name)
        info(f"Image '{name}' exists locally\n")
    except NotFound:
        info(f"Pulling image '{name}'...\n")
        client.images.pull(name)
    except APIError as e:
        info(f"Error pulling image {name}: {e}\n")

def safe_add_docker(net, name, image, **kwargs):
    client = docker.from_env()
    # remove container if exists
    try:
        c = client.containers.get(f"mn.{name}")
        info(f"Container 'mn.{name}' exists, removing...\n")
        c.remove(force=True)
    except NotFound:
        pass
    except APIError as e:
        info(f"Error removing container {name}: {e}\n")

    ensure_image(client, image)
    return net.addDocker(name, dimage=image, dcmd="/bin/bash", **kwargs)

def run_topo(num_sims=100):
    setLogLevel('info')
    net = Containernet(controller=Controller)

    info('*** Adding controller\n')
    net.addController('c0')

    info('*** Adding core Docker containers\n')
    tb = safe_add_docker(net, 'tb', 'thingsboard/tb:3.3.4.1-CVE22965')
    middts = safe_add_docker(net, 'middts', 'middts:latest')

    s_tb = net.addSwitch('s_tb')
    s_md = net.addSwitch('s_md')

    net.addLink(tb, s_tb)
    net.addLink(middts, s_md)
    net.addLink(s_tb, s_md, cls=TCLink, bw=100, delay='5ms')

    for i in range(1, num_sims + 1):
        name = f'sim_{i:03d}'
        sim = safe_add_docker(net, name, 'iot_simulator:latest')
        s = net.addSwitch(f'sw_{i:03d}')
        net.addLink(sim, s)
        net.addLink(s, s_tb, cls=TCLink, bw=10, delay='2ms')
        net.addLink(s, s_tb, cls=TCLink, bw=5, delay='20ms')
        net.addLink(s, s_tb, cls=TCLink, bw=1, delay='50ms', loss=5)

    net.start()
    info('*** Network started\n')
    CLI(net)
    net.stop()

if __name__ == '__main__':
    run_topo()
