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
    info("[🧹] Removendo containers e volumes antigos tb/db\n")
    subprocess.run("docker rm -f mn.tb mn.db", shell=True)
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
    # Garante que o volume tb_logs existe e está limpo, com permissões corretas
    info("[tb_logs] Garantindo volume tb_logs limpo e permissões corretas\n")
    subprocess.run("docker volume inspect tb_logs >/dev/null 2>&1 || docker volume create tb_logs", shell=True)
    # Monta o volume temporariamente em um container para limpar e ajustar permissões
    subprocess.run(
        "docker run --rm -v tb_logs:/mnt tb-node-custom bash -c 'rm -rf /mnt/* && chown -R 1000:1000 /mnt && chmod -R 777 /mnt'",
        shell=True
    )
    net = Containernet(controller=Controller)
    net.addController('c0')

    def safe_add(name, **kwargs):
        try:
            info(f"➕ Criando {name} — {kwargs}\n")
            return net.addDocker(name=name, **kwargs)
        except Exception as e:
            info(f"[WARN] erro criando {name}: {e}\n")
            return None

    info("*** Serviços principais: PostgreSQL, InfluxDB, Neo4j, Parser\n")
    # Serviços centrais
    pg = safe_add('db',
        dimage='postgres:13-tools',
        environment={
            'POSTGRES_DB': 'thingsboard',
            'POSTGRES_USER': 'tb',
            'POSTGRES_PASSWORD': 'tb',
        },
        volumes=['db_data:/var/lib/postgresql/data'],
        ports=[5432],
        port_bindings={5432: 5432},
        dcmd="docker-entrypoint.sh postgres",
        privileged=True
    )
    influxdb = safe_add('influxdb',
        dimage='influxdb-tools:latest',
        dcmd='influxd',
        ports=[8086],
        port_bindings={8086: 8086},
        environment={
            'DOCKER_INFLUXDB_INIT_MODE': 'setup',
            'DOCKER_INFLUXDB_INIT_USERNAME': 'admin',
            'DOCKER_INFLUXDB_INIT_PASSWORD': 'admin123',
            'DOCKER_INFLUXDB_INIT_ORG': 'org',
            'DOCKER_INFLUXDB_INIT_BUCKET': 'bucket',
            'DOCKER_INFLUXDB_INIT_ADMIN_TOKEN': 'token'
        },
        privileged=True
    )
    neo4j = safe_add('neo4j',
        dimage='neo4j-tools:latest',
        dcmd="/bin/bash",
        ports=[7474, 7687],
        port_bindings={7474: 7474, 7687: 7687},
        environment={
            'NEO4J_AUTH': 'neo4j/test123'
        },
        privileged=True
    )
    parser = safe_add('parser',
        dimage='parserwebapi-tools:latest',
        dcmd="/bin/bash",
        ports=[8080, 8081],
        port_bindings={8080: 8082, 8081: 8083},
        privileged=True
    )

    # Switches para cada domínio (usar nomes numéricos: s1, s2, ...)
    s1 = net.addSwitch('s1')  # tb
    s2 = net.addSwitch('s2')  # middts
    # Um switch para cada simulador, começando de s3
    sim_switches = []
    for i in range(num_sims):
        sim_switches.append(net.addSwitch(f's{i+3}'))

    # Hosts principais
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
        dcmd='/bin/bash',
        privileged=True
    )
    # === Prepara .env do middts com os IPs reais das dependências ===
    env_example_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../middts/middts/.env.example'))
    env_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../middts/middts/.env'))
    # IPs das dependências
    POSTGRES_HOST = '10.10.2.10'  # IP do postgres na rede do middts
    NEO4J_URL = 'bolt://10.10.2.30:7687'
    INFLUXDB_HOST = '10.10.2.20'
    # Lê o env.example, substitui os hosts e grava o .env
    with open(env_example_path) as f:
        env_lines = f.readlines()
    new_env = []
    for line in env_lines:
        if line.startswith('POSTGRES_HOST='):
            new_env.append(f'POSTGRES_HOST={POSTGRES_HOST}\n')
        elif line.startswith('NEO4J_URL='):
            new_env.append(f'NEO4J_URL={NEO4J_URL}\n')
        elif line.startswith('INFLUXDB_HOST='):
            new_env.append(f'INFLUXDB_HOST={INFLUXDB_HOST}\n')
        else:
            new_env.append(line)
    with open(env_path, 'w') as f:
        f.writelines(new_env)

    # Agora sim, sobe o middts já com o .env correto
    middts = safe_add('middts',
        dimage=os.getenv('MIDDTS_IMAGE', 'middts-custom:latest'),
        # dcmd="/entrypoint.sh",
        dcmd="/bin/bash",
        ports=[8000],
        port_bindings={8000: 8000},
        environment={
            'DJANGO_SETTINGS_MODULE': 'middleware_dt.settings'
        },
        volumes=[f'{os.path.abspath(os.path.join(os.path.dirname(__file__), '../../middts/middts/.env'))}:/middleware-dt/.env'],
        privileged=True
    )

    # Simuladores
    simuladores = []
    for i in range(1, num_sims + 1):
        name = f'sim_{i:03d}'
        sim = safe_add(name, dimage=os.getenv('SIM_IMAGE','iot_simulator:latest'), dcmd="/bin/bash", privileged=True)
        if sim:
            simuladores.append(sim)

    # Ligações: cada host ao seu switch
    net.addLink(tb, s1)
    net.addLink(middts, s2)
    for sim, s_sim in zip(simuladores, sim_switches):
        net.addLink(sim, s_sim)

    # Serviços centrais ligados a todos os switches necessários
    # Postgres: todos precisam acessar
    net.addLink(pg, s1)
    net.addLink(pg, s2)
    for s_sim in sim_switches:
        net.addLink(pg, s_sim)
    # Influx: middts e simuladores
    net.addLink(influxdb, s2)
    for s_sim in sim_switches:
        net.addLink(influxdb, s_sim)
    # Neo4j e parser: só middts
    net.addLink(neo4j, s2)
    net.addLink(parser, s2)

    # === IPs e rotas ===
    info("[net] Configurando IPs e rotas\n")
    # IPs para switches:
    # s1: 10.10.1.0/24 (tb)
    # s2: 10.10.2.0/24 (middts)
    # s3...: 10.10.(10+i).0/24 (simuladores)

    # tb
    tb.cmd("ip addr flush dev tb-eth0 scope global || true")
    tb.cmd("ip addr add 10.10.1.2/24 dev tb-eth0 || true")
    tb.cmd("ip link set tb-eth0 up")
    tb.cmd("ip route add default dev tb-eth0 || true")

    # middts
    middts.cmd("ip addr flush dev middts-eth0 scope global || true")
    middts.cmd("ip addr add 10.10.2.2/24 dev middts-eth0 || true")
    middts.cmd("ip link set middts-eth0 up")
    middts.cmd("ip route add default dev middts-eth0 || true")

    # simuladores
    for idx, sim in enumerate(simuladores, 1):
        sim_if = f"sim_{idx:03d}-eth0"
        sim_ip = f"10.10.{10+idx}.2/24"
        sim.cmd(f"ip addr flush dev {sim_if} scope global || true")
        sim.cmd(f"ip addr add {sim_ip} dev {sim_if} || true")
        sim.cmd(f"ip link set {sim_if} up")
        sim.cmd(f"ip route add default dev {sim_if} || true")

    # Serviços centrais: cada interface em cada switch recebe IP na sub-rede correspondente
    # Postgres
    pg_ifaces = ["db-eth0", "db-eth1"] + [f"db-eth{2+i}" for i in range(len(sim_switches))]
    pg_ips = ["10.10.1.10/24", "10.10.2.10/24"] + [f"10.10.{10+i+1}.10/24" for i in range(len(sim_switches))]
    for iface, ip in zip(pg_ifaces, pg_ips):
        pg.cmd(f"ip addr flush dev {iface} scope global || true")
        pg.cmd(f"ip addr add {ip} dev {iface} || true")
        pg.cmd(f"ip link set {iface} up")
        pg.cmd(f"ip route add 10.10.0.0/16 dev {iface} || true")

    # InfluxDB
    influx_ifaces = ["influxdb-eth0"] + [f"influxdb-eth{i+1}" for i in range(len(sim_switches))]
    influx_ips = ["10.10.2.20/24"] + [f"10.10.{10+i+1}.20/24" for i in range(len(sim_switches))]
    for iface, ip in zip(influx_ifaces, influx_ips):
        influxdb.cmd(f"ip addr flush dev {iface} scope global || true")
        influxdb.cmd(f"ip addr add {ip} dev {iface} || true")
        influxdb.cmd(f"ip link set {iface} up")
        influxdb.cmd(f"ip route add 10.10.0.0/16 dev {iface} || true")

    # Neo4j
    neo4j.cmd("ip addr flush dev neo4j-eth0 scope global || true")
    neo4j.cmd("ip addr add 10.10.2.30/24 dev neo4j-eth0 || true")
    neo4j.cmd("ip link set neo4j-eth0 up")
    neo4j.cmd("ip route add 10.10.0.0/16 dev neo4j-eth0 || true")

    # Parser
    parser.cmd("ip addr flush dev parser-eth0 scope global || true")
    parser.cmd("ip addr add 10.10.2.40/24 dev parser-eth0 || true")
    parser.cmd("ip link set parser-eth0 up")
    parser.cmd("ip route add 10.10.0.0/16 dev parser-eth0 || true")


    # Agora sim, inicia a rede
    net.start()

    # Pós-configuração de IPs nas interfaces (garante IP correto)
    info("[net] Configurando IPs nas interfaces dos containers\n")
    pg.cmd("ip addr flush dev db-eth0 scope global || true")
    pg.cmd("ip addr add 10.0.0.10/24 dev db-eth0 || true")
    pg.cmd("ip link set db-eth0 up")
    pg.cmd("ip route add 10.0.0.0/24 dev db-eth0 || true")

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
    info("[tb] Interfaces:\n" + tb.cmd("ip addr") + "\n")
    info("[tb] Rotas:\n" + tb.cmd("ip route") + "\n")
    info("[db] Interfaces:\n" + pg.cmd("ip addr") + "\n")
    info("[db] Rotas:\n" + pg.cmd("ip route") + "\n")
    info("[middts] Interfaces: " + str(middts.intfList()) + "\n")
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


    # Só roda install.sh se não estiver instalado
    info("[tb] Checando se ThingsBoard já está instalado...\n")
    install_check = tb.cmd('test -f /data/.tb_initialized && echo INSTALLED || echo NOT_INSTALLED').strip()
    if install_check == 'NOT_INSTALLED':
        info("[tb] Iniciando ThingsBoard manualmente (primeira instalação, pode demorar ~1 min.)\n")
        install_output = tb.cmd('/usr/share/thingsboard/bin/install/install.sh --loadDemo')
        info("[tb] Saída do install.sh:\n" + install_output + "\n")
        tb.cmd('touch /data/.tb_initialized')
    else:
        info("[tb] ThingsBoard já instalado, pulando install.sh\n")
    tb.cmd('java -jar /usr/share/thingsboard/bin/thingsboard.jar > /var/log/thingsboard/manual_start.log 2>&1 &')

    info("*** Esperando ThingsBoard inicializar (60s)\n")
    time.sleep(60)

    CLI(net)
    net.stop()

if __name__ == '__main__':
    run_topo()
