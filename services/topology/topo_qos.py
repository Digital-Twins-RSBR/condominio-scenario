#!/usr/bin/env python3
import os
import time
import subprocess
import argparse
import sys
import shutil
from mininet.net import Containernet
from mininet.node import Controller
from mininet.link import TCLink
from mininet.cli import CLI
from mininet.log import setLogLevel, info

# CLI-controlled verbosity flags (module defaults)
QUIET = True
VERBOSE = False

# Remove containers e volumes antigos antes de iniciar
def cleanup_containers():
    info("[🧹] Removendo containers e volumes antigos tb/db\n")
    subprocess.run("docker rm -f mn.tb mn.db", shell=True)
    subprocess.run("docker volume rm tb_assets tb_logs", shell=True)


def wait_for_pg_tcp(container, timeout=60, hosts=("10.10.2.10", "10.0.0.10"), pg_user='postgres'):
    info("🔍 Verificando inicialização do PostgreSQL nos hosts alvo...\n")
    for i in range(1, timeout+1):
        accepted = False
        for h in hosts:
            result = container.cmd(f"pg_isready -h {h} -p 5432 -U {pg_user} || echo NOK").strip()
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

def tb_has_any_table(pg_container, retries=6, delay=2, min_tables=5, pg_user='postgres', pg_pass='postgres'):
    """Retorna True se existir pelo menos min_tables tabelas 'normais' (relkind='r') no schema public.
    Usa heredoc para evitar problemas de quoting no ambiente Containernet.
    Considera que uma instalação válida do ThingsBoard cria dezenas de tabelas; threshold >=5 evita falsos positivos.
    """
    sql = "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r';"
    for attempt in range(1, retries+1):
        cmd = ("bash -c \"PGPASSWORD=%s timeout 5s psql -U %s -d thingsboard -Atq <<'SQL' 2>&1 || echo FAIL\n" +
               sql + "\nSQL\n" +
               "\"")
        cmd = cmd % (pg_pass, pg_user)
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

def wait_for_thingsboard(host='10.0.0.11', port=8080, timeout=180, interval=3):
    """Wait until ThingsBoard HTTP endpoint responds (not necessarily 200).
    We consider TB ready when the HTTP endpoint returns any non-zero status code
    (curl returns '000' when it couldn't connect at all)."""
    url = f"http://{host}:{port}/api/auth/login"
    start = time.time()
    while time.time() - start < timeout:
        try:
            # use curl to avoid adding new runtime deps; capture the status code
            cmd = f"curl -s -o /dev/null -w '%{{http_code}}' --max-time 3 {url}"
            proc = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            code = proc.stdout.decode().strip()
            if code and code != '000':
                info(f"[tb][wait] ThingsBoard HTTP responded with {code} at {url}\n")
                return True
        except Exception:
            pass
        info(f"[tb][wait] Ainda sem resposta do ThingsBoard em {url} (aguarda {interval}s)...\n")
        time.sleep(interval)
    info(f"[tb][wait] Timeout aguardando ThingsBoard em {url}\n")
    return False

def run_topo(num_sims=5):
    setLogLevel('info')
    # When running, honor QUIET/VERBOSE globals set at module import
    # If QUIET is True, suppress low-level info messages (they will be replaced by concise prints)
    global QUIET, VERBOSE
    try:
        QUIET = QUIET
        VERBOSE = VERBOSE
    except NameError:
        QUIET = True
        VERBOSE = False
    # monkeypatch mininet info to noop in quiet mode to reduce noise
    if QUIET:
        _orig_info = info
        def _noop_info(msg, *a, **kw):
            # keep absolutely critical markers through stdout print when needed
            return
        # replace info globally in this module
        globals()['info'] = _noop_info
    cleanup_containers()
    # Summary: CLEANUP
    if QUIET:
        print("[CLEANUP] removed old containers/volumes (best-effort)")
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

    # Wrap safe_add to produce concise output when QUIET
    def safe_add_with_status(name, **kwargs):
        c = safe_add(name, **kwargs)
        if QUIET:
            if c:
                print(f"[CREATE] {name}: OK")
            else:
                print(f"[CREATE] {name}: FAILED")
        return c

    info("*** Serviços principais: PostgreSQL, InfluxDB, Neo4j, Parser\n")
    # Diretório central de logs (visível no host) para todos os hosts da topologia
    deploy_logs_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../deploy/logs'))
    try:
        os.makedirs(deploy_logs_dir, exist_ok=True)
    except Exception as e:
        info(f"[logs][WARN] falha ao criar dir de logs {deploy_logs_dir}: {e}\n")
    # Map de logs por service/name -> path no host
    host_logs = {
        'tb': os.path.join(deploy_logs_dir, 'tb_start.log'),
        'middts': os.path.join(deploy_logs_dir, 'middts_start.log'),
        'db': os.path.join(deploy_logs_dir, 'db_start.log'),
        'influxdb': os.path.join(deploy_logs_dir, 'influx_start.log'),
        'neo4j': os.path.join(deploy_logs_dir, 'neo4j_start.log'),
        'parser': os.path.join(deploy_logs_dir, 'parser_start.log'),
    }
    for i in range(1, num_sims + 1):
        host_logs[f'sim_{i:03d}'] = os.path.join(deploy_logs_dir, f'sim_{i:03d}_start.log')
    # Pre-cria arquivos e ajusta permissões
    for name, path in host_logs.items():
        try:
            open(path, 'a').close()
            subprocess.run(f"chmod 666 '{path}'", shell=True, check=True)
        except Exception as e:
            info(f"[logs][WARN] falha ao criar/ajustar log host {path}: {e}\n")
    
    POSTGRES_HOST = '10.10.2.10'
    POSTGRES_PORT = '5432'
    POSTGRES_USER = 'postgres'
    POSTGRES_PASSWORD = 'tb'
    # Serviços centrais
    pg = safe_add_with_status('db',
        dimage='postgres:13-tools',
        environment={
            'POSTGRES_DB': 'thingsboard',
            'POSTGRES_USER': POSTGRES_USER,
            'POSTGRES_PASSWORD': POSTGRES_PASSWORD,
        },
        volumes=[
            'db_data:/var/lib/postgresql/data',
            f"{host_logs.get('db')}:/var/log/postgresql/postgresql_start.log",
        ],
        ports=[POSTGRES_PORT],
        port_bindings={POSTGRES_PORT: POSTGRES_PORT},
        dcmd="docker-entrypoint.sh postgres",
        privileged=True
    )
    influxdb = safe_add_with_status('influxdb',
        dimage='influxdb-tools:latest',
        # use the daemon executable expected by official images
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
        volumes=[f"{host_logs.get('influxdb')}:/var/log/influxdb_start.log"],
        privileged=True
    )
    neo4j = safe_add_with_status('neo4j',
        dimage='neo4j-tools:latest',
        # dcmd="/bin/bash",
        ports=[7474, 7687],
        port_bindings={7474: 7474, 7687: 7687},
        environment={
            'NEO4J_AUTH': 'neo4j/test123'
        },
        volumes=[f"{host_logs.get('neo4j')}:/var/log/neo4j_start.log"],
        privileged=True
    )
    parser = safe_add_with_status('parser',
        dimage='parserwebapi-tools:latest',
        dcmd="/bin/bash",
        ports=[8080, 8081],
        port_bindings={8080: 8082, 8081: 8083},
        volumes=[f"{host_logs.get('parser')}:/var/log/parser_start.log"],
        privileged=True
    )
    # ...existing code...

    # Switches para cada domínio (usar nomes numéricos: s1, s2, ...)
    s1 = net.addSwitch('s1')  # tb
    s2 = net.addSwitch('s2')  # middts
    # Um switch para cada simulador, começando de s3
    sim_switches = []
    for i in range(num_sims):
        sim_switches.append(net.addSwitch(f's{i+3}'))

    # Hosts principais
    tb = safe_add_with_status('tb', 
        dimage='tb-node-custom',
        environment={
            'SPRING_DATASOURCE_URL': 'jdbc:postgresql://10.0.0.10:5432/thingsboard',
            'SPRING_DATASOURCE_USERNAME': POSTGRES_USER,
            'SPRING_DATASOURCE_PASSWORD': POSTGRES_PASSWORD,
            'TB_QUEUE_TYPE': 'in-memory',
            'INSTALL_TB': 'true',
            'LOAD_DEMO': 'true'
        },
        volumes=[
            'tb_assets:/data',
            'tb_logs:/var/log/thingsboard',
            f"{host_logs.get('tb')}:/var/log/thingsboard/manual_start.log",
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
    # Host entrypoint path (so we can mount the updated entrypoint into the container)
    host_entrypoint = os.path.join(md_base_dir, 'entrypoint.sh')
    # Ensure entrypoint is executable on host so container will be able to execute it when mounted
    try:
        if os.path.exists(host_entrypoint):
            subprocess.run(f"chmod 755 '{host_entrypoint}'", shell=True, check=False)
    except Exception:
        pass
    # IPs das dependências
    # Usar IP da interface compartilhada com middts (db-eth1)
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

    # Diretório central de logs (visível no host) para todos os hosts da topologia
    deploy_logs_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../deploy/logs'))
    try:
        os.makedirs(deploy_logs_dir, exist_ok=True)
    except Exception as e:
        info(f"[logs][WARN] falha ao criar dir de logs {deploy_logs_dir}: {e}\n")
    # Map de logs por service/name -> path no host
    host_logs = {
        'tb': os.path.join(deploy_logs_dir, 'tb_start.log'),
        'middts': os.path.join(deploy_logs_dir, 'middts_start.log'),
        'db': os.path.join(deploy_logs_dir, 'db_start.log'),
        'influxdb': os.path.join(deploy_logs_dir, 'influx_start.log'),
        'neo4j': os.path.join(deploy_logs_dir, 'neo4j_start.log'),
        'parser': os.path.join(deploy_logs_dir, 'parser_start.log'),
    }
    # simuladores adicionados dinamicamente abaixo
    for i in range(1, num_sims + 1):
        host_logs[f'sim_{i:03d}'] = os.path.join(deploy_logs_dir, f'sim_{i:03d}_start.log')
    # Pre-cria arquivos e ajusta permissões
    for name, path in host_logs.items():
        try:
            open(path, 'a').close()
            subprocess.run(f"chmod 666 '{path}'", shell=True, check=True)
        except Exception as e:
            info(f"[logs][WARN] falha ao criar/ajustar log host {path}: {e}\n")

    # Helper: cria banco para o middts se ainda não existir (usa usuário 'postgres')
    def ensure_database(pg_container, dbname, owner='postgres', connect_db='template1'):
        info(f"[pg] ensure_database: alvo='{dbname}' owner='{owner}' connect_db='{connect_db}'\n")
        # Usa as credenciais configuradas no topo
        select_sql = f"SELECT 1 FROM pg_database WHERE datname=$${dbname}$$;"
        check_cmd = (
            f"bash -c \"PGPASSWORD={POSTGRES_PASSWORD} timeout 5s psql -h 127.0.0.1 -U {POSTGRES_USER} -d {connect_db} -tAc \"{select_sql}\" 2>/dev/null || echo FAIL\""
        )
        info(f"[pg][debug] check_cmd: {check_cmd}\n")
        raw_check = pg_container.cmd(check_cmd)
        info(f"[pg][debug] check_raw: {raw_check.strip()[:200]}\n")
        tokens = [t.strip() for t in raw_check.strip().split() if t.strip().isdigit() or t.strip() == 'FAIL']
        if '1' in tokens:
            info(f"[pg] Database '{dbname}' já existe.\n")
            return True, False
        if 'FAIL' in tokens:
            info("[pg][warn] Verificação retornou FAIL (timeout/erro); tentativa de criação continuará.\n")
        create_sql = f"CREATE DATABASE {dbname} OWNER {owner};"
        create_cmd = (
            f"bash -c \"PGPASSWORD={POSTGRES_PASSWORD} timeout 10s psql -h 127.0.0.1 -U {POSTGRES_USER} -d {connect_db} -v ON_ERROR_STOP=1 -c '{create_sql}' 2>&1 || echo CREATE_FAIL\""
        )
        info(f"[pg][debug] create_cmd: {create_cmd}\n")
        raw_create = pg_container.cmd(create_cmd)
        info(f"[pg] CREATE raw (200c): {raw_create[:200]}\n")
        # Se já existia, tratar como sucesso
        if 'already exists' in raw_create:
            info(f"[pg] Mensagem indica que database '{dbname}' já existia; prosseguindo.\n")
            return True, False
        time.sleep(1)
        raw_check2 = pg_container.cmd(check_cmd)
        info(f"[pg][debug] recheck_raw: {raw_check2.strip()[:200]}\n")
        tokens2 = [t.strip() for t in raw_check2.strip().split() if t.strip().isdigit() or t.strip() == 'FAIL']
        if '1' in tokens2:
            info(f"[pg] Database '{dbname}' criado/verificado com sucesso.\n")
            # if we reached here after create attempt, return created=True
            return True, True
        # Fallback alternativo: listar bancos e procurar nome
        list_cmd = f"bash -c \"PGPASSWORD={POSTGRES_PASSWORD} timeout 5s psql -h 127.0.0.1 -U {POSTGRES_USER} -lqt 2>/dev/null | cut -d '|' -f1 | awk '{'{print $1}'}' | grep -Fx '{dbname}' && echo FOUND || echo NOTFOUND\""
        list_out = pg_container.cmd(list_cmd).strip()
        info(f"[pg][debug] list_out: {list_out}\n")
        if 'FOUND' in list_out:
            info(f"[pg] Database '{dbname}' detectado via listagem. Prosseguindo.\n")
            return True, False
        info(f"[pg][ERRO] Falha ao garantir database '{dbname}'. tokens2={tokens2}\n")
        return False, False

    # Agora sim, sobe o middts já com o .env correto
    middts = safe_add_with_status('middts',
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
        volumes=[
            f'{env_path}:/middleware-dt/.env',
            # mount host entrypoint to override image entrypoint if present
            f'{host_entrypoint}:/entrypoint.sh',
            f"{host_logs.get('middts')}:/var/log/middts_start.log",
        ],
        privileged=True
    )

    # Abort early if any critical service failed to create. This avoids later
    # AttributeError when trying to add links to a None node and provides a
    # clearer error message to the operator.
    critical = {'db': pg, 'influxdb': influxdb, 'neo4j': neo4j, 'parser': parser, 'tb': tb, 'middts': middts}
    missing = [name for name, node in critical.items() if node is None]
    if missing:
        print(f"[ERROR] Falha ao criar containers criticos: {missing}; abortando topologia.")
        return

    # Simuladores
    simuladores = []
    # Garantir DB sqlite base para os simuladores.
    # If the host sqlite file is missing or accidentally a directory, copy the
    # scenario template `initial_data/db_scenario.sqlite3` (preferred) into
    # services/iot_simulator/db.sqlite3 so containers can mount a real file.
    # This keeps the behavior deterministic and avoids mounting a directory
    # onto a file inside the container.
    sim_project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '../iot_simulator'))
    host_sim_db = os.path.join(sim_project_root, 'db.sqlite3')
    initial_db = os.path.join(sim_project_root, 'initial_data', 'db_scenario.sqlite3')
    alt_initial_db = os.path.join(sim_project_root, 'iot_simulator', 'initial_data', 'db.sqlite3')

    # If host_sim_db is a directory (user mistake), try to preserve it by
    # renaming. If renaming fails (permissions or lock), attempt to remove it
    # so we can create a proper sqlite file at that path. This prevents Docker
    # from refusing to mount a directory onto a file inside the container.
    if os.path.isdir(host_sim_db):
        info(f"[sim][WARN] host_sim_db path {host_sim_db} is a directory; moving aside or removing to create a sqlite file instead.\n")
        bak = host_sim_db + '.bak'
        try:
            os.rename(host_sim_db, bak)
            info(f"[sim] diretório {host_sim_db} movido para {bak}\n")
        except Exception as e:
            info(f"[sim][WARN] falha ao mover diretório {host_sim_db}: {e}; tentando remover recursivamente...\n")
            try:
                shutil.rmtree(host_sim_db)
                info(f"[sim] diretório {host_sim_db} removido com sucesso\n")
            except Exception as e2:
                info(f"[sim][ERROR] nao foi possivel mover nem remover {host_sim_db}: {e2}\n")

    # If file doesn't exist (or we removed the mistaken dir), try copying from
    # scenario template(s). Prefer the canonical 'initial_data/db_scenario.sqlite3'
    # first, then fall back to the package template. If none available, create
    # an empty placeholder file (no automatic DB restore).
    if not os.path.exists(host_sim_db):
        copied = False
        for tpl in (initial_db, alt_initial_db):
            try:
                if os.path.exists(tpl) and os.path.isfile(tpl):
                    shutil.copy2(tpl, host_sim_db)
                    os.chmod(host_sim_db, 0o666)
                    info(f"[sim] copiado template sqlite {tpl} -> {host_sim_db} (perms 666)\n")
                    copied = True
                    break
            except Exception as e:
                info(f"[sim][WARN] falha ao copiar {tpl} para {host_sim_db}: {e}\n")
        if not copied:
            try:
                # create an empty file so Docker can mount it
                open(host_sim_db, 'a').close()
                subprocess.run(f"chmod 666 '{host_sim_db}'", shell=True, check=True)
                info(f"[sim] criado host db placeholder em {host_sim_db} com permissões 666 (NO automatic restore)\n")
            except Exception as e:
                info(f"[sim][WARN] não foi possível criar/ajustar {host_sim_db}: {e}\n")
    # Diretório de logs do host para que possamos montar os logs dos simuladores e tail-los do host
    sim_logs_dir = os.path.join(sim_project_root, 'logs')
    if not os.path.exists(sim_logs_dir):
        try:
            os.makedirs(sim_logs_dir, exist_ok=True)
        except Exception as e:
            info(f"[sim][WARN] falha ao criar dir de logs {sim_logs_dir}: {e}\n")
    # Do not automatically copy initial_data/db.sqlite3 into the host file here.
    # This avoids unexpected restores during topology runs. Use 'make restore-simulators' to
    # perform a controlled restore when desired.
    # If host file is missing, create an empty placeholder with permissive permissions
    # so the container mount will succeed. This deliberately does NOT populate the DB.
    if not os.path.exists(host_sim_db):
        try:
            open(host_sim_db, 'a').close()
            subprocess.run(f"chmod 666 '{host_sim_db}'", shell=True, check=True)
            info(f"[sim] criado host db placeholder em {host_sim_db} com permissões 666 (NO automatic restore)\n")
        except Exception as e:
            info(f"[sim][WARN] não foi possível criar/ajustar {host_sim_db}: {e}\n")
    # Pre-cria os arquivos de log por simulador no host e garante permissões
    for i in range(1, num_sims + 1):
        host_log = os.path.join(sim_logs_dir, f"sim_{i:03d}_start.log")
        try:
            open(host_log, 'a').close()
            subprocess.run(f"chmod 666 '{host_log}'", shell=True, check=True)
        except Exception as e:
            info(f"[sim][WARN] falha ao criar/ajustar log host {host_log}: {e}\n")
    # special host entrypoint for sim_001 (serve Django on 8001)
    host_sim_entry = os.path.join(sim_project_root, 'entrypoint_sim_001.sh')
    try:
        if os.path.exists(host_sim_entry):
            subprocess.run(f"chmod 755 '{host_sim_entry}'", shell=True, check=False)
    except Exception:
        pass

    for i in range(1, num_sims + 1):
        name = f'sim_{i:03d}'
        vols = [
            f"{host_logs.get(f'sim_{i:03d}')}:/iot_simulator/sim_{i:03d}_start.log",
        ]
        env = {
            'INFLUXDB_TOKEN': INFLUXDB_TOKEN,
            'INFLUXDB_HOST': INFLUXDB_HOST,
            'INFLUXDB_ORG': 'org',
            'INFLUXDB_BUCKET': 'bucket',
            'SIMULATOR_NUMBER': str(i)
        }
        project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
        reset_marker = os.path.join(project_root, 'deploy', '.reset_sim_db')
        try:
            if os.path.exists(reset_marker):
                env['RESET_SIM_DB'] = '1'
                info(f"[sim][INFO] Found reset marker {reset_marker} -> simulator will force restore on startup\n")
        except Exception:
            pass
        if i == 1 and os.path.exists(host_sim_entry):
            vols.insert(0, f"{host_sim_entry}:/entrypoint.sh")
            env['ALLOWED_HOSTS'] = '*'
            sim = safe_add_with_status(
                name,
                dimage=os.getenv('SIM_IMAGE','iot_simulator:latest'),
                dcmd="/bin/bash",
                environment=env,
                volumes=vols,
                ports=[8001],
                port_bindings={8001:8001},
                privileged=True
            )
        else:
            sim = safe_add_with_status(
                name,
                dimage=os.getenv('SIM_IMAGE','iot_simulator:latest'),
                dcmd="/bin/bash",
                environment=env,
                volumes=vols,
                privileged=True
            )
        if sim:
            simuladores.append(sim)
            info(f"[sim] {sim.name} criado — restore_db será executado antes do entrypoint, se disponível.\n")

    # Ligações: cada host ao seu switch
    net.addLink(tb, s1)
    net.addLink(middts, s2)
    net.addLink(s1, s2)
    for sim, s_sim in zip(simuladores, sim_switches):
        net.addLink(sim, s_sim)
        # Conecta o switch do simulador ao switch principal s1 para alcançar ThingsBoard
        try:
            net.addLink(s_sim, s1)
        except Exception:
            # ignore se já existir
            pass
        net.addLink(s_sim, tb)

    # Serviços centrais ligados a todos os switches necessários
    # Postgres: todos precisam menos os simuladores que usam sqlite3
    net.addLink(pg, s1)
    net.addLink(pg, s2)
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
    if QUIET:
        print(f"[NET] network started; hosts: {len(simuladores)+6} (including core services)")

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

    # Depois que a rede subiu e IPs atribuídos, chame o entrypoint dos simuladores para inicializar app
    info("[sim] Iniciando entrypoints dos simuladores (em background)...\n")
    for idx, sim in enumerate(simuladores, 1):
        try:
            # Use um log dentro do projeto do simulador (garantido existir via mount)
            logf = f"/iot_simulator/sim_{idx:03d}_start.log"
            info(f"[sim] Lançando /entrypoint.sh em {sim.name} (log {logf})\n")
            # Cria o arquivo de log dentro do container e garante permissões antes de iniciar
            sim.cmd(f"mkdir -p /iot_simulator || true && touch {logf} && chmod 666 {logf} || true")
            # Run the optional restore helper inside the container before
            # starting the main entrypoint. If restore_db is not present or
            # fails, continue anyway but log the restore output to a separate
            # file for debugging.
            try:
                sim.cmd(f"/bin/bash -lc './restore_db > {logf}.restore 2>&1 || true'")
            except Exception:
                # ignore restore failures
                pass
            # Prepare log file and run optional restore helper. Entrypoint will be launched
            # later after ThingsBoard is up to avoid create/search races on startup.
            try:
                sim.cmd(f"mkdir -p /iot_simulator || true && touch {logf} && chmod 666 {logf} || true")
            except Exception:
                pass
        except Exception as e:
            info(f"[sim][WARN] falha ao iniciar entrypoint em {sim.name}: {e}\n")

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
    if not wait_for_pg_tcp(pg, timeout=60, pg_user=POSTGRES_USER):
        info("[ERRO] PostgreSQL não aceitou conexões TCP. Abortando.\n")
        net.stop()
        return

    # Garante que o banco do middts exista antes de iniciar o middleware
    ok_db = False
    created_db = False
    try:
        ok_db, created_db = ensure_database(pg, POSTGRES_DB)
    except Exception as e:
        info(f"[pg][ERROR] ensure_database threw: {e}\n")
    if not ok_db:
        info("[ERRO] Não foi possível criar/verificar o database do middts. Abortando.\n")
        net.stop()
        return

    # Note: automatic SQL import was intentionally removed.
    # The topology will create the database if missing (created_db==True),
    # but SQL restoration is disabled here to avoid unexpected heavy/slow restores
    # during automated topology runs and to give the operator explicit control.
    # Use the Makefile target `make restore-scenario` to restore middts.sql on-demand.
    md_sql = os.path.join(md_base_dir, 'middts.sql')
    if created_db:
        info(f"[DB] Database '{POSTGRES_DB}' was created by topology; automatic SQL import is disabled.\n")
        if QUIET:
            print(f"[DB] created {POSTGRES_DB} (automatic import disabled). Run 'make restore-scenario' to import {md_sql}.")
        middts_log = host_logs.get('middts')
        try:
            ts = time.strftime('%Y-%m-%d %H:%M:%S')
            if middts_log:
                with open(middts_log, 'a') as lf:
                    lf.write(f"[{ts}] [DB] Database {POSTGRES_DB} created by topology; automatic SQL import disabled.\n")
        except Exception:
            pass

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

    info("*** Aguarde ThingsBoard inicializar (+-30s)\n")

    # Wait for ThingsBoard HTTP to start answering before launching simulators' entrypoints
    tb_ready = wait_for_thingsboard(host='10.0.0.11', port=8080, timeout=180, interval=3)
    if not tb_ready:
        info("[tb] ThingsBoard não respondeu no tempo esperado; simuladores serão iniciados mesmo assim (risco de conflitos).\n")

    # Launch simulator entrypoints now that TB is responding (or timeout reached)
    info("[sim] Lançando entrypoints dos simuladores agora que ThingsBoard parece pronto...\n")
    for idx, sim in enumerate(simuladores, 1):
        try:
            logf = f"/iot_simulator/sim_{idx:03d}_start.log"
            sim.cmd(f"/entrypoint.sh > {logf} 2>&1 &")
        except Exception as e:
            info(f"[sim][WARN] falha ao iniciar entrypoint em {sim.name}: {e}\n")

    CLI(net)
    net.stop()
    # Attempt to remove the reset marker so subsequent topo runs don't force simulator DB restore.
    try:
        repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
        reset_marker = os.path.join(repo_root, 'deploy', '.reset_sim_db')
        if os.path.exists(reset_marker):
            os.remove(reset_marker)
            info(f"[topo] Removed reset marker {reset_marker} so simulators won't be auto-restored on next run.\n")
    except Exception:
        pass

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Containernet topology runner for condominio-scenario')
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--quiet', action='store_true', help='Run with minimal, concise output (default)')
    group.add_argument('--verbose', action='store_true', help='Run with verbose debug output')
    parser.add_argument('--sims', type=int, default=1, help='Number of simulator nodes to create')
    args = parser.parse_args()
    # Configure module-level flags
    QUIET = args.quiet or not args.verbose
    VERBOSE = args.verbose
    # If verbose, restore info to original by setting mininet log level higher
    if VERBOSE:
        # restore info printing by setting loglevel and not overriding
        setLogLevel('info')
    run_topo(num_sims=args.sims)
