#!/usr/bin/env python3
import os
import time
import subprocess
from mininet.net import Containernet
from mininet.node import Controller
from mininet.link import TCLink
from mininet.cli import CLI
from mininet.log import setLogLevel, info

# Remove containers e volumes antigos antes de iniciar
def cleanup_containers():
    info("[🧹] Removendo containers e volumes antigos tb/tb-db\n")
    subprocess.run("docker rm -f mn.tb mn.tb-db", shell=True)
    subprocess.run("docker volume rm tb_assets tb_logs", shell=True)

# # Espera até PostgreSQL responder dentro do container
# def wait_for_pg(container, timeout=60):
#     info("🔍 Verificando inicialização via diretório do socket PostgreSQL...\n")
#     for i in range(timeout):
#         result = container.cmd("test -S /var/run/postgresql/.s.PGSQL.5432 && echo OK || echo NOK").strip()
#         # info(f"[{i+1}s] Socket status: {result}\n")
#         if result == "OK":
#             info(f"✅ PostgreSQL socket detectado após {i+1}s\n")
#             return True
#         time.sleep(1)
#     info("❌ Timeout: PostgreSQL não ficou pronto dentro do container.\n")
#     # Tenta mostrar logs do container
#     info(container.cmd("cat /var/log/postgresql/postgresql*.log || echo '[WARN] Sem log PostgreSQL.'\n"))
#     return False

def wait_for_pg_tcp(container, timeout=60):
    info("🔍 Verificando inicialização via TCP na porta 5432...\n")
    for i in range(timeout):
        result = container.cmd("pg_isready -h 10.0.0.10 -p 5432 -U tb || echo NOK").strip()
        info(f"[{i+1}s] pg_isready: {result}\n")
        if "accepting connections" in result:
            info(f"✅ PostgreSQL aceitando conexões após {i+1}s\n")
            return True
        time.sleep(1)
    info("❌ Timeout: PostgreSQL não aceitou conexões TCP.\n")
    info(container.cmd("cat /var/log/postgresql/postgresql*.log || echo '[WARN] Sem log PostgreSQL.'\n"))
    return False

def run_topo(num_sims=5):
    setLogLevel('info')
    cleanup_containers()
    net = Containernet(controller=Controller)
    net.addController('c0')

    def safe_add(name, **kwargs):
        try:
            info(f"➕ Criando {name} — {kwargs}\n")
            return net.addDocker(name=name, **kwargs)
        except Exception as e:
            info(f"[WARN] erro criando {name}: {e}\n")
            return None

    info("*** Serviços principais: PostgreSQL e ThingsBoard\n")
    pg = safe_add('tb-db',
        dimage='postgres:13-tools',
        environment={
            'POSTGRES_DB': 'thingsboard',
            'POSTGRES_USER': 'tb',
            'POSTGRES_PASSWORD': 'tb',
        },
        volumes=['tb_db_data:/var/lib/postgresql/data'],
        ip='10.0.0.10/24',
        ports=[5432],
        port_bindings={5432: 5432},
        dcmd="docker-entrypoint.sh postgres"
    )
    if pg is None:
        info("❌ Falha ao criar o container do Postgres. Abortando topologia.\n")
        net.stop()
        return
    s_db = net.addSwitch('s1')
    net.addLink(pg, s_db)
    # Inicia rede parcialmente para poder fazer docker exec
    net.start()
    info("⏳ Aguardando PostgreSQL dentro do container...\n")
    # if not wait_for_pg(pg, timeout=60):
    #     info("[ERRO] PostgreSQL não inicializou. Abortando.\n")
        # net.stop()
        # return
    if not wait_for_pg_tcp(pg, timeout=60):
        info("[ERRO] PostgreSQL não aceitou conexões TCP. Abortando.\n")
        net.stop()
        return

    tb = safe_add('tb', 
        dimage='tb-node-custom',
        environment={
            'SPRING_DATASOURCE_URL': 'jdbc:postgresql://10.0.0.10:5432/thingsboard',
            'SPRING_DATASOURCE_USERNAME': 'tb',
            'SPRING_DATASOURCE_PASSWORD': 'tb',
            'TB_QUEUE_TYPE': 'in-memory',
            'INSTALL_TB': 'true',
            'LOAD_DEMO': 'true'
        },
        volumes=[
            'tb_assets:/data',
            'tb_logs:/var/log/thingsboard'
        ],
        ports=[8080, 1883],
        port_bindings={8080: 8080, 1883: 1883},
        ip='10.0.0.11/24',
        # dcmd='sh -c "java -jar /usr/share/thingsboard/bin/thingsboard.jar"'
        dcmd='/sbin/init'
    )
    if tb is None:
        info("❌ Falha ao criar o container do ThingsBoard. Abortando topologia.\n")
        net.stop()
        return

    info("*** MidDiTS e simuladores\n")
    middts = safe_add('middts',
        dimage=os.getenv('MIDDTS_IMAGE', 'middts:latest'),
        dcmd="/bin/bash",
        ports=[8000],
        port_bindings={8000: 8000}
    )

    # Switches
    s_tb = net.addSwitch('s2')
    s_md = net.addSwitch('s3')

    net.addLink(tb, s_tb)
    net.addLink(middts, s_md)
    net.addLink(s_db, s_tb, cls=TCLink, bw=200, delay='1ms')
    net.addLink(s_tb, s_md, cls=TCLink, bw=200, delay='5ms')

    # Simuladores IoT
    for i in range(1, num_sims + 1):
        name = f'sim_{i:03d}'
        sim = safe_add(name, dimage=os.getenv('SIM_IMAGE','iot_simulator:latest'), dcmd="/bin/bash")
        s = net.addSwitch(f's{i+10}')
        if sim:
            net.addLink(sim, s)
            net.addLink(s, s_tb, cls=TCLink, bw=10, delay='2ms')
            net.addLink(s, s_tb, cls=TCLink, bw=5, delay='20ms')
            net.addLink(s, s_tb, cls=TCLink, bw=1, delay='50ms', loss=5)

    info("*** Esperando ThingsBoard inicializar (60s)\n")
    time.sleep(60)

    CLI(net)
    net.stop()

if __name__ == '__main__':
    run_topo()
