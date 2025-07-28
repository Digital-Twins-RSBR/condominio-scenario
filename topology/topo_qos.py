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
    
    # Força limpeza antes de iniciar
    info('*** Limpando ambiente anterior\n')
    os.system('sudo mn -c > /dev/null 2>&1')
    
    net = Containernet(controller=Controller)
    info('*** Adicionando controller\n')
    net.addController('c0')

    def safe_add(name, image, **kwargs):
        try:
            info(f"*** Criando container {name} com imagem {image}\n")
            # Verifica se já existe container com esse nome
            existing = os.popen(f'docker ps -a --filter "name=mn.{name}" -q').read().strip()
            if existing:
                info(f"[WARN] Removendo container existente mn.{name}\n")
                os.system(f'docker rm -f mn.{name} > /dev/null 2>&1')
                time.sleep(1)  # Aguarda remoção completa
            
            container = net.addDocker(name, dimage=image, **kwargs)
            info(f"*** Container {name} criado com sucesso\n")
            return container
        except Exception as e:
            info(f"[ERROR] Falha ao criar {name}: {e}\n")
            return None


    info('*** Criando hosts principais\n')

    # PostgreSQL para ThingsBoard
    pg = safe_add('pg', 'postgres:15',
        environment={
            'POSTGRES_DB': 'thingsboard',
            'POSTGRES_USER': 'tb',
            'POSTGRES_PASSWORD': 'tb'
        },
        volumes=['pg_data:/var/lib/postgresql/data'],
        ports=[5432],
        port_bindings={5432: 5432}
    )

    # ThingsBoard apontando para o PostgreSQL
    tb = safe_add('tb', 'thingsboard/tb-postgres:latest',
        environment={
            'SPRING_DATASOURCE_URL': 'jdbc:postgresql://pg:5432/thingsboard',
            'SPRING_DATASOURCE_USERNAME': 'tb',
            'SPRING_DATASOURCE_PASSWORD': 'tb',
            'TB_QUEUE_TYPE': 'in-memory'
        },
        ports=[9090, 1883],
        port_bindings={9090: 8080, 1883: 1883},
        volumes=['tb_data:/data', 'tb_logs:/var/log/thingsboard'],
    )

    influx=safe_add('influx-dbmain', 'influxdb:2.7', ports=[8086],
        port_bindings={8086: 8086},
        environment={
            'DOCKER_INFLUXDB_DB': 'iot_data',
            'DOCKER_INFLUXDB_ADMIN_USER': 'admin',
            'DOCKER_INFLUXDB_ADMIN_PASSWORD': 'admin123',
            'DOCKER_INFLUXDB_INIT_ORG': 'middts',
            'DOCKER_INFLUXDB_INIT_BUCKET': 'iot_data',
            'DOCKER_INFLUXDB_INIT_ADMIN_TOKEN': 'admin_token_middts'
        },
        volumes=['influx_data:/var/lib/influxdb2']
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
    s_influx = net.addSwitch('s4')

    info('*** Criando links entre containers e switches\n')
    # Adiciona links apenas se os containers foram criados com sucesso
    if pg:
        net.addLink(pg, s_pg)
    if tb:
        net.addLink(tb, s_tb)
    if middts:
        net.addLink(middts, s_md)
    if influx:
        net.addLink(influx, s_influx)

    # Links entre switches
    net.addLink(s_pg, s_tb, cls=TCLink, bw=100, delay='1ms')
    net.addLink(s_tb, s_md, cls=TCLink, bw=100, delay='5ms')
    net.addLink(s_tb, s_influx, cls=TCLink, bw=100, delay='2ms')

    info('*** Criando simuladores IoT\n')
    for i in range(1, num_sims + 1):
        name = f'sim_{i:03d}'
        sim = safe_add(name, os.getenv('SIM_IMAGE', 'iot_simulator:latest'), dcmd="/bin/bash")
        s = net.addSwitch(f's{i+10}')
        if sim:
            net.addLink(sim, s)
            # Conecta switch do simulador ao switch do ThingsBoard apenas se TB existe
            if tb:
                net.addLink(s, s_tb, cls=TCLink, bw=10, delay='2ms')
            # Removidas as conexões duplicadas que causavam problemas

    info('*** Verificando integridade da topologia\n')
    containers_created = [c for c in [pg, tb, middts, influx] if c is not None]
    info(f'*** {len(containers_created)} containers principais criados com sucesso\n')
    
    if len(containers_created) == 0:
        info('[ERROR] Nenhum container principal foi criado. Abortando.\n')
        return

    info('*** Iniciando rede\n')
    try:
        net.start()
    except Exception as e:
        info(f'[ERROR] Falha ao iniciar rede: {e}\n')
        info('*** Limpando e abortando\n')
        net.stop()
        return

    if tb:
        info('*** Aguardando ThingsBoard inicializar (30s)\n')
        time.sleep(30)

    CLI(net)
    info('*** Parando rede\n')
    net.stop()

if __name__ == '__main__':
    run_topo(5)
