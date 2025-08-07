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

    s1 = net.addSwitch('s1')
    net.addLink(pg, s1)

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
        dcmd='/bin/bash'
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

    # Slices: high (URLLC), medium (padrão), low (best effort)
    # URLLC: baixa latência, alta banda
    net.addLink(tb, s1, cls=TCLink, bw=100, delay='1ms', loss=0)
    net.addLink(tb, s1, cls=TCLink, bw=30, delay='10ms', loss=1)
    net.addLink(tb, s1, cls=TCLink, bw=5, delay='50ms', loss=5)

    net.addLink(middts, s1, cls=TCLink, bw=100, delay='1ms', loss=0)
    net.addLink(middts, s1, cls=TCLink, bw=30, delay='10ms', loss=1)
    net.addLink(middts, s1, cls=TCLink, bw=5, delay='50ms', loss=5)

    # Simuladores IoT: cada um com 3 links para tb (alta, média, baixa)
    simuladores = []
    for i in range(1, num_sims + 1):
        name = f'sim_{i:03d}'
        sim = safe_add(name, dimage=os.getenv('SIM_IMAGE','iot_simulator:latest'), dcmd="/bin/bash")
        if sim:
            # URLLC
            net.addLink(sim, tb, cls=TCLink, bw=100, delay='1ms', loss=0)
            # padrão
            net.addLink(sim, tb, cls=TCLink, bw=30, delay='10ms', loss=1)
            # best effort
            net.addLink(sim, tb, cls=TCLink, bw=5, delay='50ms', loss=5)
            simuladores.append(sim)

    # Agora sim, inicia a rede
    net.start()

    # Pós-configuração de IPs nas interfaces (garante IP correto)
    info("[net] Configurando IPs nas interfaces dos containers\n")
    pg.cmd("ip addr flush dev tb-db-eth0 scope global || true")
    pg.cmd("ip addr add 10.0.0.10/24 dev tb-db-eth0 || true")
    pg.cmd("ip link set tb-db-eth0 up")
    pg.cmd("ip route add 10.0.0.0/24 dev tb-db-eth0 || true")

    tb.cmd("ip addr flush dev tb-eth0 scope global || true")
    tb.cmd("ip addr add 10.0.0.11/24 dev tb-eth0 || true")
    tb.cmd("ip link set tb-eth0 up")
    tb.cmd("ip route add 10.0.0.0/24 dev tb-eth0 || true")

    middts.cmd("ip addr flush dev middts-eth0 scope global || true")
    middts.cmd("ip addr add 10.0.0.12/24 dev middts-eth0 || true")
    middts.cmd("ip link set middts-eth0 up")
    middts.cmd("ip route add 10.0.0.0/24 dev middts-eth0 || true")

    for idx, sim in enumerate(simuladores, 1):
        sim_if = f"sim_{idx:03d}-eth0"
        sim_ip = f"10.0.0.{20+idx}/24"
        sim.cmd(f"ip addr flush dev {sim_if} scope global || true")
        sim.cmd(f"ip addr add {sim_ip} dev {sim_if} || true")
        sim.cmd(f"ip link set {sim_if} up")
        sim.cmd(f"ip route add 10.0.0.0/24 dev {sim_if} || true")

    # Bloco de debug automático: mostra links, interfaces, rotas e ARP
    info("\n[DEBUG] Topologia, interfaces e rotas:\n")
    info("[net] Links:\n" + str(net.links) + "\n")
    info("[pg] Interfaces: " + str(pg.intfList()) + "\n")
    info("[tb] Interfaces: " + str(tb.intfList()) + "\n")
    info("[middts] Interfaces: " + str(middts.intfList()) + "\n")
    info("[pg] ip route:\n" + pg.cmd("ip route") + "\n")
    info("[tb] ip route:\n" + tb.cmd("ip route") + "\n")
    info("[middts] ip route:\n" + middts.cmd("ip route") + "\n")
    info("[pg] arp:\n" + pg.cmd("arp -n") + "\n")
    info("[tb] arp:\n" + tb.cmd("arp -n") + "\n")
    info("[middts] arp:\n" + middts.cmd("arp -n") + "\n")

    # Agora sim, aguarde o banco subir
    info("⏳ Aguardando PostgreSQL dentro do container...\n")
    if not wait_for_pg_tcp(pg, timeout=60):
        info("[ERRO] PostgreSQL não aceitou conexões TCP. Abortando.\n")
        net.stop()
        return

    # Start manual do ThingsBoard
    info("[tb] Iniciando ThingsBoard manualmente\n")
    # Instala o schema do banco antes de iniciar o serviço
    tb.cmd('mkdir -p /var/log/thingsboard && chmod 777 -R /var/log/thingsboard')
    tb.cmd('sh -c "/usr/share/thingsboard/bin/install/install.sh --loadDemo > /var/log/thingsboard/install.log 2>&1"')
    tb.cmd('sh -c "java -jar /usr/share/thingsboard/bin/thingsboard.jar > /var/log/thingsboard/manual_start.log 2>&1 &"')

    info("*** Esperando ThingsBoard inicializar (60s)\n")
    time.sleep(60)

    CLI(net)
    net.stop()

if __name__ == '__main__':
    run_topo()
