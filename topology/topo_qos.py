#!/usr/bin/env python3
import os
import time
from mininet.net import Containernet
from mininet.node import Controller, Docker
from mininet.link import TCLink
from mininet.cli import CLI
from mininet.log import setLogLevel, info

def run_topo(num_sims=100):
    setLogLevel('info')
    net = Containernet(controller=Controller)
    info('*** Adicionando controller\n')
    net.addController('c0')

    def safe_add(name, image, **kwargs):
        try:
            info(f"{name}: kwargs {kwargs}\n")
            container = net.addDocker(name, dimage=image, **kwargs)
            info(f"{name}: update resources {{}}\n")
            return container
        except Exception as e:
            info(f"[WARN] falha ao criar {name}: {e}\n")
            return None


    info('*** Criando hosts principais\n')

    # PostgreSQL para ThingsBoard
    pg = safe_add('pg', 'postgres:13',
        environment={
            'POSTGRES_DB': 'thingsboard',
            'POSTGRES_USER': 'tb',
            'POSTGRES_PASSWORD': 'tb'
        },
        ports=[5432],
        port_bindings={5432: 5432}
    )

    # ThingsBoard apontando para o PostgreSQL
    tb = safe_add('tb', 'thingsboard/tb-postgres:3.3.4.1-CVE22965',
        environment={
            'SPRING_DATASOURCE_URL': 'jdbc:postgresql://pg:5432/thingsboard',
            'SPRING_DATASOURCE_USERNAME': 'tb',
            'SPRING_DATASOURCE_PASSWORD': 'tb',
            'TB_QUEUE_TYPE': 'in-memory'
        },
        ports=[8080, 1883],
        port_bindings={8080: 8080, 1883: 1883}
    )

    middts = safe_add(
        'middts',
        os.getenv('MIDDTS_IMAGE', 'middts:latest'),
        dcmd="/bin/bash",
        ports=[8000],
        port_bindings={8000: 8000}
    )

    s_pg = net.addSwitch('s1')
    s_tb = net.addSwitch('s2')
    s_md = net.addSwitch('s3')

    net.addLink(pg, s_pg)
    net.addLink(tb, s_tb)
    net.addLink(middts, s_md)

    net.addLink(s_pg, s_tb, cls=TCLink, bw=100, delay='1ms')
    net.addLink(s_tb, s_md, cls=TCLink, bw=100, delay='5ms')

    info('*** Criando simuladores IoT\n')
    for i in range(1, num_sims + 1):
        name = f'sim_{i:03d}'
        sim = safe_add(name, os.getenv('SIM_IMAGE', 'iot_simulator:latest'), dcmd="/bin/bash")
        s = net.addSwitch(f's{i+10}')
        if sim:
            net.addLink(sim, s)
            net.addLink(s, s_tb, cls=TCLink, bw=10, delay='2ms')
            net.addLink(s, s_tb, cls=TCLink, bw=5, delay='20ms')
            net.addLink(s, s_tb, cls=TCLink, bw=1, delay='50ms', loss=5)

    info('*** Iniciando rede\n')
    net.start()

    info('*** Aguardando ThingsBoard inicializar (30s)\n')
    time.sleep(30)

    CLI(net)
    info('*** Parando rede\n')
    net.stop()

if __name__ == '__main__':
    run_topo(5)
