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


def wait_for_pg_tcp(container, timeout=60, hosts=("10.10.2.10", "10.0.0.10")):
    info("🔍 Verificando inicialização do PostgreSQL nos hosts alvo...\n")
    for i in range(1, timeout+1):
        accepted = False
        for h in hosts:
            result = container.cmd(f"pg_isready -h {h} -p 5432 -U tb || echo NOK").strip()
            info(f"[{i}s] {h} -> {result}\n")
            if "accepting connections" in result:
                accepted = True
        if accepted:
            info(f"✅ PostgreSQL aceitando conexões após {i}s\n")
            return True
        time.sleep(1)
    info("❌ Timeout: PostgreSQL não aceitou conexões TCP em nenhum host.\n")
    info(container.cmd("cat /var/log/postgresql/postgresql*.log || echo '[WARN] Sem log PostgreSQL.'\n"))
    return False

def tb_has_any_table(pg_container, retries=6, delay=2, min_tables=5):
    """Retorna True se existir pelo menos min_tables tabelas 'normais' (relkind='r') no schema public.
    Usa heredoc para evitar problemas de quoting no ambiente Containernet.
    Considera que uma instalação válida do ThingsBoard cria dezenas de tabelas; threshold >=5 evita falsos positivos.
    """
    sql = "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r';"
    for attempt in range(1, retries+1):
        cmd = ("bash -c \"PGPASSWORD=tb timeout 5s psql -U tb -d thingsboard -Atq <<'SQL' 2>&1 || echo FAIL\n" +
               sql + "\nSQL\n" +
               "\"")
        raw = pg_container.cmd(cmd)
        out = raw.strip().splitlines()
        # Filtra linhas que são apenas número
        nums = [l.strip() for l in out if l.strip().isdigit()]
        val = int(nums[-1]) if nums else -1
        info(f"[tb][CHECK] Tentativa {attempt} tabelas_public={val} raw='{raw.strip()[:120]}'\n")
        if val >= min_tables:
            return True
        if val == 0:
            return False  # banco claramente vazio
        time.sleep(delay)
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
    md_base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '../middleware-dt'))
    env_example_path = os.path.join(md_base_dir, '.env.example')
    env_path = os.path.join(md_base_dir, '.env')
    # IPs das dependências
    # Usar IP da interface compartilhada com middts (db-eth1)
    POSTGRES_HOST = '10.10.2.10'
    POSTGRES_PORT = '5432'
    POSTGRES_USER = 'tb'
    POSTGRES_PASSWORD = 'tb'
    # Banco separado para o middleware (não reutilizar o DB do ThingsBoard)
    POSTGRES_DB = 'middts'
    NEO4J_URL = 'bolt://10.10.2.30:7687'
    INFLUXDB_HOST = '10.10.2.20'
    INFLUXDB_TOKEN = 'token'  # deve casar com DOCKER_INFLUXDB_INIT_ADMIN_TOKEN do container Influx
    # Gera/atualiza .env de forma robusta
    def render_env(lines):
        new_env_local = []
        seen = set()
        for line in lines:
            if line.startswith('POSTGRES_HOST='):
                new_env_local.append(f'POSTGRES_HOST={POSTGRES_HOST}\n'); seen.add('POSTGRES_HOST')
            elif line.startswith('POSTGRES_PORT='):
                new_env_local.append(f'POSTGRES_PORT={POSTGRES_PORT}\n'); seen.add('POSTGRES_PORT')
            elif line.startswith('POSTGRES_USER='):
                new_env_local.append(f'POSTGRES_USER={POSTGRES_USER}\n'); seen.add('POSTGRES_USER')
            elif line.startswith('POSTGRES_PASSWORD='):
                new_env_local.append(f'POSTGRES_PASSWORD={POSTGRES_PASSWORD}\n'); seen.add('POSTGRES_PASSWORD')
            elif line.startswith('POSTGRES_DB='):
                new_env_local.append(f'POSTGRES_DB={POSTGRES_DB}\n'); seen.add('POSTGRES_DB')
            elif line.startswith('NEO4J_URL='):
                new_env_local.append(f'NEO4J_URL={NEO4J_URL}\n'); seen.add('NEO4J_URL')
            elif line.startswith('INFLUXDB_HOST='):
                new_env_local.append(f'INFLUXDB_HOST={INFLUXDB_HOST}\n'); seen.add('INFLUXDB_HOST')
            elif line.startswith('INFLUXDB_TOKEN='):
                new_env_local.append(f'INFLUXDB_TOKEN={INFLUXDB_TOKEN}\n'); seen.add('INFLUXDB_TOKEN')
            else:
                new_env_local.append(line)
        # Garante que chaves existam
        if 'POSTGRES_HOST' not in seen:
            new_env_local.append(f'POSTGRES_HOST={POSTGRES_HOST}\n')
        if 'POSTGRES_PORT' not in seen:
            new_env_local.append(f'POSTGRES_PORT={POSTGRES_PORT}\n')
        if 'POSTGRES_USER' not in seen:
            new_env_local.append(f'POSTGRES_USER={POSTGRES_USER}\n')
        if 'POSTGRES_PASSWORD' not in seen:
            new_env_local.append(f'POSTGRES_PASSWORD={POSTGRES_PASSWORD}\n')
        if 'POSTGRES_DB' not in seen:
            new_env_local.append(f'POSTGRES_DB={POSTGRES_DB}\n')
        if 'NEO4J_URL' not in seen:
            new_env_local.append(f'NEO4J_URL={NEO4J_URL}\n')
        if 'INFLUXDB_HOST' not in seen:
            new_env_local.append(f'INFLUXDB_HOST={INFLUXDB_HOST}\n')
        if 'INFLUXDB_TOKEN' not in seen:
            new_env_local.append(f'INFLUXDB_TOKEN={INFLUXDB_TOKEN}\n')
        # Atualiza/gera DATABASE_URL coerente
        has_database_url = any(l.startswith('DATABASE_URL=') for l in new_env_local)
        db_url = f'DATABASE_URL=postgresql://{POSTGRES_USER}:{POSTGRES_PASSWORD}@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}\n'
        if has_database_url:
            new_env_local = [db_url if l.startswith('DATABASE_URL=') else l for l in new_env_local]
        else:
            new_env_local.append(db_url)
        return new_env_local

    if os.path.exists(env_path):
        with open(env_path) as f:
            env_lines = f.readlines()
        new_env = render_env(env_lines)
    elif os.path.exists(env_example_path):
        with open(env_example_path) as f:
            env_lines = f.readlines()
        new_env = render_env(env_lines)
    else:
        # Fallback mínimo
        new_env = [
            f'POSTGRES_HOST={POSTGRES_HOST}\n',
            f'POSTGRES_PORT={POSTGRES_PORT}\n',
            f'POSTGRES_USER={POSTGRES_USER}\n',
            f'POSTGRES_PASSWORD={POSTGRES_PASSWORD}\n',
            f'POSTGRES_DB={POSTGRES_DB}\n',
            f'NEO4J_URL={NEO4J_URL}\n',
            f'INFLUXDB_HOST={INFLUXDB_HOST}\n',
            f'DATABASE_URL=postgresql://{POSTGRES_USER}:{POSTGRES_PASSWORD}@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}\n'
        ]
    with open(env_path, 'w') as f:
        f.writelines(new_env)

    # Helper: cria banco para o middts se ainda não existir (usa usuário 'tb')
    def ensure_database(pg_container, dbname, owner='tb', connect_db='postgres'):
        info(f"[pg] ensure_database: alvo='{dbname}' owner='{owner}' connect_db='{connect_db}'\n")
        # Usa dollar-quoting para evitar problemas de escape
        select_sql = f"SELECT 1 FROM pg_database WHERE datname=$${dbname}$$;"
        check_cmd = (
            f"bash -c \"PGPASSWORD=tb timeout 5s psql -U tb -d {connect_db} -tAc \"{select_sql}\" 2>/dev/null || echo FAIL\""
        )
        info(f"[pg][debug] check_cmd: {check_cmd}\n")
        raw_check = pg_container.cmd(check_cmd)
        info(f"[pg][debug] check_raw: {raw_check.strip()[:200]}\n")
        tokens = [t.strip() for t in raw_check.strip().split() if t.strip().isdigit() or t.strip() == 'FAIL']
        if '1' in tokens:
            info(f"[pg] Database '{dbname}' já existe.\n")
            return True
        if 'FAIL' in tokens:
            info("[pg][warn] Verificação retornou FAIL (timeout/erro); tentativa de criação continuará.\n")
        create_sql = f"CREATE DATABASE {dbname} OWNER {owner};"
        create_cmd = (
            f"bash -c \"PGPASSWORD=tb timeout 10s psql -U tb -d {connect_db} -v ON_ERROR_STOP=1 -c '{create_sql}' 2>&1 || echo CREATE_FAIL\""
        )
        info(f"[pg][debug] create_cmd: {create_cmd}\n")
        raw_create = pg_container.cmd(create_cmd)
        info(f"[pg] CREATE raw (200c): {raw_create[:200]}\n")
        # Se já existia, tratar como sucesso
        if 'already exists' in raw_create:
            info(f"[pg] Mensagem indica que database '{dbname}' já existia; prosseguindo.\n")
            return True
        time.sleep(1)
        raw_check2 = pg_container.cmd(check_cmd)
        info(f"[pg][debug] recheck_raw: {raw_check2.strip()[:200]}\n")
        tokens2 = [t.strip() for t in raw_check2.strip().split() if t.strip().isdigit() or t.strip() == 'FAIL']
        if '1' in tokens2:
            info(f"[pg] Database '{dbname}' criado/verificado com sucesso.\n")
            return True
        # Fallback alternativo: listar bancos e procurar nome
        list_cmd = "bash -c \"PGPASSWORD=tb timeout 5s psql -U tb -lqt 2>/dev/null | cut -d '|' -f1 | awk '{print $1}' | grep -Fx '" + dbname + "' && echo FOUND || echo NOTFOUND\""
        list_out = pg_container.cmd(list_cmd).strip()
        info(f"[pg][debug] list_out: {list_out}\n")
        if 'FOUND' in list_out:
            info(f"[pg] Database '{dbname}' detectado via listagem. Prosseguindo.\n")
            return True
        info(f"[pg][ERRO] Falha ao garantir database '{dbname}'. tokens2={tokens2}\n")
        return False

    # Agora sim, sobe o middts já com o .env correto
    middts = safe_add('middts',
        dimage=os.getenv('MIDDTS_IMAGE', 'middts-custom:latest'),
        dcmd="/entrypoint.sh",
        # dcmd="/bin/bash",
        ports=[8000],
        port_bindings={8000: 8000},
        environment={
            'DJANGO_SETTINGS_MODULE': 'middleware_dt.settings',
            'INFLUXDB_TOKEN': INFLUXDB_TOKEN,
            'DEFER_START': '1'
        },
        volumes=[f'{env_path}:/middleware-dt/.env'],
        privileged=True
    )

    # Simuladores
    simuladores = []
    for i in range(1, num_sims + 1):
        name = f'sim_{i:03d}'
        sim = safe_add(
            name,
            dimage=os.getenv('SIM_IMAGE','iot_simulator:latest'),
            dcmd="/bin/bash",
            environment={
                'INFLUXDB_TOKEN': INFLUXDB_TOKEN,
                'INFLUXDB_HOST': INFLUXDB_HOST,
                'INFLUXDB_ORG': 'org',
                'INFLUXDB_BUCKET': 'bucket'
            },
            privileged=True
        )
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
    # Garante IP para rede middts no segundo interface (db-eth1) -> 10.10.2.10
    pg.cmd("ip addr add 10.10.2.10/24 dev db-eth1 || true")
    pg.cmd("ip link set db-eth1 up || true")

    tb.cmd("ip addr flush dev tb-eth0 scope global || true")
    tb.cmd("ip addr add 10.0.0.11/24 dev tb-eth0 || true")
    tb.cmd("ip link set tb-eth0 up")
    tb.cmd("ip route add 10.0.0.0/24 dev tb-eth0 || true")

    middts.cmd("ip addr flush dev middts-eth0 scope global || true")
    middts.cmd("ip addr add 10.0.0.12/24 dev middts-eth0 || true")
    middts.cmd("ip link set middts-eth0 up")
    middts.cmd("ip route add 10.0.0.0/24 dev middts-eth0 || true")
    # Adiciona também endereço na subrede funcional middts (10.10.2.0/24) esperado pelo .env
    middts.cmd("ip addr add 10.10.2.2/24 dev middts-eth0 || true")

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

    # Garante que o banco do middts exista antes de iniciar o middleware
    if not ensure_database(pg, POSTGRES_DB):
        info("[ERRO] Não foi possível criar/verificar o database do middts. Abortando.\n")
        net.stop()
        return

    # Agora que o Postgres está acessível e o DB do middts existe, inicia o middleware
    if middts:
        info("[middts] Iniciando entrypoint do middleware agora que o Postgres respondeu e DB existe...\n")
        middts.cmd('DEFER_START=0 /entrypoint.sh > /var/log/middts_start.log 2>&1 &')
        info("[middts] EntryPoint lançado em background (log em /var/log/middts_start.log dentro do container).\n")


    # Inicialização simplificada do ThingsBoard
    info("[tb] Verificando se já existem tabelas ThingsBoard no PostgreSQL...\n")
    has_tables = tb_has_any_table(pg)
    info(f"[tb] Resultado verificação tabelas: has_tables={has_tables}\n")
    if not has_tables:
        info("[tb] Nenhuma (ou poucas) tabelas detectadas -> executando install.sh...\n")
        tb.cmd('rm -f /data/.tb_initialized')
        install_output = tb.cmd('/usr/share/thingsboard/bin/install/install.sh --loadDemo 2>&1 | tee /tmp/install.log')
        info("[tb] Saída do install.sh:\n" + install_output + "\n")
        if ('already present in database' in install_output or 'User with email' in install_output):
            info("[tb] Instalação pré-existente detectada durante install.sh, marcando como inicializado.\n")
        tb.cmd('touch /data/.tb_initialized')
    else:
        info("[tb] Tabelas já existem -> pulando install.sh.\n")
        tb.cmd('touch /data/.tb_initialized')
    info("[tb] Iniciando thingsboard.jar em background\n")
    tb.cmd('java -jar /usr/share/thingsboard/bin/thingsboard.jar > /var/log/thingsboard/manual_start.log 2>&1 &')

    info("*** Esperando ThingsBoard inicializar (60s)\n")
    time.sleep(60)

    CLI(net)
    net.stop()

if __name__ == '__main__':
    run_topo()
