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
import json

# CLI-controlled verbosity flags (module defaults)
QUIET = True
VERBOSE = False

# Remove containers e volumes antigos antes de iniciar
def cleanup_containers():
    info("[🧹] Removendo containers e volumes antigos tb/db\n")
    subprocess.run("docker rm -f mn.tb mn.db", shell=True)
    # remove known named volumes (best-effort)
    subprocess.run("docker volume rm tb_assets tb_logs influx_logs neo4j_logs parser_logs || true", shell=True)


def wait_for_pg_tcp(container, timeout=60, hosts=("10.0.1.10", "10.0.0.10"), pg_user='postgres'):
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

def wait_for_thingsboard(host='10.0.0.2', port=8080, timeout=180, interval=3):
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
    info("[logs] Garantindo volumes de logs limpos e permissões corretas\n")
    # volumes list mirrors the named volumes we will mount into containers
    log_volumes = ['tb_logs', 'influx_logs', 'neo4j_logs', 'parser_logs']
    for v in log_volumes:
        try:
            subprocess.run(f"docker volume inspect {v} >/dev/null 2>&1 || docker volume create {v}", shell=True, check=False)
            # Clean and set permissões via a helper run
            subprocess.run(
                f"docker run --rm -v {v}:/mnt tb-node-custom bash -c 'rm -rf /mnt/* && chown -R 1000:1000 /mnt && chmod -R 777 /mnt'",
                shell=True,
                check=False
            )
        except Exception:
            # best-effort
            pass
    net = Containernet(controller=Controller)
    net.addController('c0')

    # Helper: link profile defaults (bandwidth Mbps, delay ms, loss %)
    # Profiles: urllc (low latency, lower bw), best_effort (balanced), eMBB (high bandwidth)
    # URLLC profile optimized based on test results for <200ms latency goal
    PROFILE_LINK_PRESETS = {
        'urllc': {'bw': 1000, 'delay': '0.05ms', 'loss': 0},
        'eMBB': {'bw': 300, 'delay': '25ms', 'loss': 0.2}, 
        'best_effort': {'bw': 200, 'delay': '50ms', 'loss': 0.5}
    }

    # Determine profile from env TOPO_PROFILE or default to 'best_effort'
    topo_profile = os.environ.get('TOPO_PROFILE') or os.environ.get('PROFILE') or 'urllc'
    topo_profile = topo_profile if topo_profile in PROFILE_LINK_PRESETS else topo_profile.lower()
    if topo_profile not in PROFILE_LINK_PRESETS:
        # try common case-insensitive names
        for k in PROFILE_LINK_PRESETS:
            if k.lower() == str(topo_profile).lower():
                topo_profile = k
                break
    profile_params = PROFILE_LINK_PRESETS.get(topo_profile, PROFILE_LINK_PRESETS['urllc'])

    def add_link(a, b, **kwargs):
        """Wrapper around net.addLink that applies TCLink with profile defaults unless overridden."""
        # Special-case: if caller requests no_profile, create an unshaped link
        no_profile = kwargs.pop('no_profile', False)
        if no_profile:
            try:
                return net.addLink(a, b)
            except Exception:
                # fallback to explicit addLink even if it errors
                return net.addLink(a, b)

        link_kwargs = dict(bw=profile_params['bw'], delay=profile_params['delay'], loss=profile_params['loss'])
        # allow caller overrides
        link_kwargs.update(kwargs)
        try:
            # Use TCLink to set bandwidth/delay/loss
            return net.addLink(a, b, cls=TCLink, **link_kwargs)
        except TypeError:
            # fallback: older Mininet might accept the args without cls
            return net.addLink(a, b, **link_kwargs)

    def safe_add(name, **kwargs):
        try:
            # If a container with this name already exists, remove only the
            # container (do not remove named volumes) so Containernet can
            # recreate it attached to the correct network namespace.
            cname = f"mn.{name}"
            try:
                # list any matching container id(s)
                p = subprocess.run(['docker', 'ps', '-a', '--filter', f'name={cname}', '-q'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                ids = p.stdout.decode().strip().split() if p.stdout else []
                if ids:
                    info(f"[SAFE_ADD] found existing container(s) {ids} for {cname}; removing container(s) to allow Containernet to recreate (volumes preserved)\n")
                    # remove all matching containers
                    for cid in ids:
                        try:
                            subprocess.run(['docker', 'rm', '-f', cid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                        except Exception:
                            pass
            except Exception:
                # best-effort: continue if docker not available or command fails
                pass

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
        # listener log for middts (listen_gateway)
        'middts_listen_gateway': os.path.join(deploy_logs_dir, 'middts_listen_gateway.log'),
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
    
    # Load Influx config from repo .env early so container creation can use it
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
    repo_env = os.path.join(repo_root, '.env')
    INFLUXDB_TOKEN = 'token'
    INFLUXDB_ORG = INFLUXDB_ORG if 'INFLUXDB_ORG' in globals() else 'org'
    INFLUXDB_BUCKET = INFLUXDB_BUCKET if 'INFLUXDB_BUCKET' in globals() else 'iot_data'
    try:
        if os.path.exists(repo_env):
            with open(repo_env, 'r') as ef:
                for line in ef:
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    if line.startswith('INFLUXDB_TOKEN='):
                        INFLUXDB_TOKEN = line.split('=', 1)[1]
                    if line.startswith('INFLUXDB_ORG=') or line.startswith('INFLUXDB_ORGANIZATION='):
                        INFLUXDB_ORG = line.split('=', 1)[1]
                    if line.startswith('INFLUXDB_BUCKET='):
                        INFLUXDB_BUCKET = line.split('=', 1)[1]
    except Exception:
        pass

    # Optional: read bootstrap password for Influx from repo .env or fallback to a safe default
    INFLUXDB_INIT_PASSWORD = 'middts_passw'
    try:
        if os.path.exists(repo_env):
            with open(repo_env, 'r') as ef:
                for line in ef:
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    # support both variable names used across the project
                    if line.startswith('DOCKER_INFLUXDB_INIT_PASSWORD=') or line.startswith('INFLUXDB_INIT_PASSWORD='):
                        INFLUXDB_INIT_PASSWORD = line.split('=', 1)[1]
                        break
    except Exception:
        pass
    # Ensure minimum length expected by InfluxDB (8 characters)
    if len(INFLUXDB_INIT_PASSWORD) < 8:
        INFLUXDB_INIT_PASSWORD = INFLUXDB_INIT_PASSWORD.ljust(8, '_')

    POSTGRES_HOST = '10.0.1.10'
    POSTGRES_PORT = '5432'
    POSTGRES_USER = 'postgres'
    # Default to previous behavior ('tb') to avoid mismatches with existing DB volumes
    # Operators can override via repository .env (POSTGRES_PASSWORD=...)
    POSTGRES_PASSWORD = 'tb'
    try:
        # Prefer explicit repo .env value when present (operator-provided credential)
        if os.path.exists(repo_env):
            with open(repo_env, 'r') as ef:
                for line in ef:
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    if line.startswith('POSTGRES_PASSWORD='):
                        POSTGRES_PASSWORD = line.split('=', 1)[1]
                        try:
                            info(f"[topo][INFO] Using POSTGRES_PASSWORD from repository .env (masked)")
                        except Exception:
                            pass
                        break
    except Exception:
        pass
    try:
        if os.path.exists(repo_env):
            with open(repo_env, 'r') as ef:
                for line in ef:
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    if line.startswith('POSTGRES_PASSWORD='):
                        POSTGRES_PASSWORD = line.split('=', 1)[1]
                        break
    except Exception:
        pass
    # Serviços centrais
    pg = safe_add_with_status('db',
        dimage='postgres:13-tools',
        ip='10.0.0.10',
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
        dimage=os.getenv('INFLUXDB_IMAGE','influxdb:2.7'),
        # use the daemon executable expected by official images
        dcmd='influxd',
        ip='10.0.1.20',
        ports=[8086],
        port_bindings={8086: 8086},
        environment={
            'DOCKER_INFLUXDB_INIT_MODE': 'setup',
            'DOCKER_INFLUXDB_INIT_USERNAME': 'middts',
            'DOCKER_INFLUXDB_INIT_PASSWORD': INFLUXDB_INIT_PASSWORD,
            'DOCKER_INFLUXDB_INIT_ORG': INFLUXDB_ORG,
            'DOCKER_INFLUXDB_INIT_BUCKET': INFLUXDB_BUCKET,
            'DOCKER_INFLUXDB_INIT_ADMIN_TOKEN': INFLUXDB_TOKEN
        },
        volumes=[
            # Persistent data dir used by InfluxDB v2
            'influx_data:/root/.influxdbv2',
            'influx_logs:/var/log/influxdb',
            f"{host_logs.get('influxdb')}:/var/log/influxdb_start.log",
        ],
        privileged=True
    )
    neo4j = safe_add_with_status('neo4j',
        dimage='neo4j-tools:latest',
        # Start Neo4j in foreground (console) so logs are streamable and
        # the process binds correctly to the container network. Ensure the
        # server listen address line is present but avoid duplicating it
        # when the data volume already contains neo4j.conf (idempotent).
        dcmd="/bin/bash -lc 'grep -qxF \"server.default_listen_address=0.0.0.0\" /var/lib/neo4j/conf/neo4j.conf || echo \"server.default_listen_address=0.0.0.0\" >> /var/lib/neo4j/conf/neo4j.conf || true; /var/lib/neo4j/bin/neo4j console'",
        ip='10.0.1.30',
        ports=[7474, 7687],
        port_bindings={7474: 7474, 7687: 7687},
        # Prefer middleware .env value for NEO4J_AUTH when available, otherwise use a safe default
        environment={
            'NEO4J_AUTH': os.environ.get('NEO4J_AUTH', 'neo4j/neo4j_pass'),
        },
        volumes=[
            # Persistent data dir for Neo4j
            'neo4j_data:/var/lib/neo4j',
            'neo4j_logs:/var/log/neo4j',
            f"{host_logs.get('neo4j')}:/var/log/neo4j_start.log",
        ],
        privileged=True
    )
    # The parser is intentionally NOT created inside the Containernet topology.
    # It depends on platform-specific components and should run as a regular
    # Docker container on the host (outside Mininet). Example:
    #   docker run -d --name parser -p 8082:8080 -p 8083:8081 parserwebapi-tools:latest
    # Topology will still attempt to follow logs for a container named 'parser'
    # (external) and will inject PARSER_HOST/PARSER_PORT into the middleware
    # .env so middts can reach it.
    parser = None
    # Start background followers that pipe container stdout/stderr (docker logs -f)
    # into the host-side files under deploy/logs/*. This ensures the
    # service startup logs are preserved even if the container writes to
    # stdout/stderr instead of the mapped file paths.
    LOG_FOLLOW_PROCS = []
    LOG_FOLLOW_NAMES = set()
    def follow_container_logs(name, host_path):
        """Follow docker logs for container 'mn.<name>' and append them to host_path."""
        try:
            if not host_path:
                return
            os.makedirs(os.path.dirname(host_path), exist_ok=True)
            # prefer Containernet-managed container name mn.<name>; if not present,
            # try a plain container name (useful for externally-run parser)
            docker_name = f"mn.{name}"
            try:
                pchk = subprocess.run(['docker', 'ps', '-q', '--filter', f'name=^{docker_name}$'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                if not pchk.stdout or not pchk.stdout.strip():
                    # try plain name
                    alt = name
                    pchk2 = subprocess.run(['docker', 'ps', '-q', '--filter', f'name=^{alt}$'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                    if pchk2.stdout and pchk2.stdout.strip():
                        docker_name = alt
            except Exception:
                # ignore detection errors and keep docker_name as mn.<name>
                pass

            # If container exists right now, stream its logs into the host file.
            # Avoid starting duplicate followers for the same logical name
            if name in LOG_FOLLOW_NAMES:
                if QUIET:
                    print(f"[LOG] follower for {name} already running; skipping duplicate")
                return
            try:
                pchk_final = subprocess.run(['docker', 'ps', '-q', '--filter', f'name=^{docker_name}$'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                if pchk_final.stdout and pchk_final.stdout.strip():
                    # container exists: use docker logs -f and redirect to the host file via shell
                    cmd = f"sh -c \"docker logs -f {docker_name} >> '{host_path}' 2>&1\""
                    p = subprocess.Popen(cmd, shell=True)
                    LOG_FOLLOW_PROCS.append((name, p, None))
                    LOG_FOLLOW_NAMES.add(name)
                    if QUIET:
                        print(f"[LOG] following docker logs for {docker_name} -> {host_path}")
                    return
            except Exception:
                # if docker check fails, fall through to watcher behavior
                pass

            # Container not present yet: start a lightweight watcher that will
            # wait for the container to appear and then stream its logs into the file.
            # This avoids using `tail -F` on the same file (which would append what it
            # reads back into the same file, causing runaway growth).
            # Build a safe shell command: outer Python string uses double-quotes,
            # the shell script passed to sh -c is single-quoted; host_path is
            # wrapped in double-quotes inside the shell to tolerate spaces.
            watcher_cmd = (
                "sh -c 'while true; do "
                f"if docker ps -q --filter name=^{docker_name}$ | grep -q .; then "
                f"docker logs -f {docker_name} >> \"{host_path}\" 2>&1; fi; sleep 2; done'"
            )
            try:
                p = subprocess.Popen(watcher_cmd, shell=True)
                LOG_FOLLOW_PROCS.append((name, p, None))
                LOG_FOLLOW_NAMES.add(name)
                if QUIET:
                    print(f"[LOG] waiting for {docker_name} -> will follow logs to {host_path} when container appears")
            except Exception as e:
                info(f"[logs][WARN] failed to start watcher for {name}: {e}\n")
        except Exception as e:
            info(f"[logs][WARN] falha ao seguir logs de {name}: {e}\n")

    # --- proxy supervisor helpers -------------------------------------------------
    # Keep track of proxy subprocesses and restart attempts
    PROXY_PROCS = {}  # svc_name -> subprocess.Popen
    PROXY_RESTARTS = {}  # svc_name -> int
    PROXY_MAX_RESTARTS = 5
    PROXY_RESTART_BACKOFF = 2.0  # seconds, multiplied per restart

    def _get_container_pid(name, timeout=15):
        """Return PID of docker container mn.<name> or None if not found within timeout."""
        cname = f"mn.{name}"
        for _ in range(timeout):
            try:
                p = subprocess.run(['docker', 'inspect', '--format', '{{.State.Pid}}', cname], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                if p.stdout:
                    pid = p.stdout.decode().strip()
                    if pid and pid.isdigit() and int(pid) > 0:
                        return int(pid)
            except Exception:
                pass
            time.sleep(1)
        return None

    def _start_host_socat_to_container_unix(pid, container_sock_path, host_port, logfile_path=None):
        """Start a host socat process forwarding TCP localhost:host_port -> /proc/<pid>/root/<container_sock_path>.
        Returns subprocess.Popen or raises Exception on failure.
        """
        # Build absolute path inside host procfs
        proc_sock = f"/proc/{pid}/root/{container_sock_path.lstrip('/')}"
        # Use reuseaddr,fork so multiple clients are handled and socat can be restarted safely
        cmd = ['socat', f'TCP-LISTEN:{host_port},reuseaddr,fork', f'UNIX-CONNECT:{proc_sock}']
        # Open logfile if provided
        stdout = subprocess.DEVNULL
        stderr = subprocess.DEVNULL
        lf = None
        if logfile_path:
            try:
                os.makedirs(os.path.dirname(logfile_path), exist_ok=True)
                lf = open(logfile_path, 'ab')
                stdout = lf
                stderr = lf
            except Exception:
                lf = None
        p = subprocess.Popen(cmd, stdout=stdout, stderr=stderr)
        # attach logfile to proc tuple so caller can close it later
        return (p, lf)

    def start_proxy_safe(container_name, svc_name, container_sock_path, host_port, host_logpath=None):
        """Ensure a host socat proxy exists forwarding to container's UNIX socket.
        This function is idempotent: if proxy already running for svc_name, it does nothing.
        """
        if svc_name in PROXY_PROCS and PROXY_PROCS[svc_name] and PROXY_PROCS[svc_name][0].poll() is None:
            # already running
            return PROXY_PROCS[svc_name][0]

        pid = _get_container_pid(container_name, timeout=15)
        if not pid:
            raise RuntimeError(f"container {container_name} PID not found or container not started yet")

        # Try starting host socat and supervise it
        try:
            p, lf = _start_host_socat_to_container_unix(pid, container_sock_path, host_port, logfile_path=host_logpath)
            PROXY_PROCS[svc_name] = (p, lf)
            PROXY_RESTARTS[svc_name] = 0
            if QUIET:
                print(f"[PROXY] started proxy {svc_name} -> pid={pid} host_port={host_port}")
            return p
        except Exception as e:
            raise

    def stop_all_proxies():
        """Terminate all running proxy processes and close logfiles."""
        for svc, tup in list(PROXY_PROCS.items()):
            try:
                p, lf = tup
                if p and p.poll() is None:
                    p.terminate()
                    try:
                        p.wait(timeout=3)
                    except Exception:
                        p.kill()
                if lf:
                    try:
                        lf.close()
                    except Exception:
                        pass
            except Exception:
                pass
            PROXY_PROCS.pop(svc, None)
            PROXY_RESTARTS.pop(svc, None)

    def _supervise_proxies_once():
        """Single-pass supervisor that restarts any stopped proxies with backoff and caps."""
        for svc, tup in list(PROXY_PROCS.items()):
            try:
                p, lf = tup
                if p.poll() is None:
                    continue
                # process terminated; consider restart
                restarts = PROXY_RESTARTS.get(svc, 0) + 1
                if restarts > PROXY_MAX_RESTARTS:
                    if QUIET:
                        print(f"[PROXY] {svc} exceeded max restarts ({PROXY_MAX_RESTARTS}), not restarting")
                    PROXY_PROCS.pop(svc, None)
                    PROXY_RESTARTS.pop(svc, None)
                    continue
                # exponential backoff
                backoff = PROXY_RESTART_BACKOFF * restarts
                if QUIET:
                    print(f"[PROXY] restarting {svc} (attempt {restarts}) after {backoff}s")
                time.sleep(backoff)
                # try to restart by re-obtaining container name mapping stored in svc name convention
                # svc name format expected: '<svc>' previously mapped to container mn.<container_name>
                # We assume the container name equals svc or 'mn.' prefix is used elsewhere.
                # Attempt a best-effort restart: try mn.<svc> then <svc>
                container_try = f"mn.{svc}"
                pid = _get_container_pid(svc, timeout=5) or _get_container_pid(container_try, timeout=5)
                if not pid:
                    PROXY_RESTARTS[svc] = restarts
                    continue
                # default UDS path placed under /tmp/<svc>.sock inside container
                container_sock_path = f"/tmp/{svc}.sock"
                host_port = None
                # attempt to infer host_port by scanning previous process command; fallback to well-known ports
                # For robustness, user should call start_proxy_safe with explicit host_port; here we fallback to common ports
                common_ports = {'influxdb': 8086, 'middts': 8000, 'tb': 8080, 'neo4j': 7474}
                host_port = common_ports.get(svc, None)
                try:
                    p2, lf2 = _start_host_socat_to_container_unix(pid, container_sock_path, host_port, logfile_path=None)
                    PROXY_PROCS[svc] = (p2, lf2)
                    PROXY_RESTARTS[svc] = restarts
                except Exception:
                    PROXY_RESTARTS[svc] = restarts
                    continue
            except Exception:
                continue


    # Start followers for the three services of interest if their host paths exist
    try:
        # Core services
        follow_container_logs('influxdb', host_logs.get('influxdb'))
        follow_container_logs('neo4j', host_logs.get('neo4j'))
        follow_container_logs('parser', host_logs.get('parser'))
        follow_container_logs('db', host_logs.get('db'))
        follow_container_logs('tb', host_logs.get('tb'))
        # middts: follow both the container logs and the listen_gateway log if present
        follow_container_logs('middts', host_logs.get('middts'))
        # Also attempt to follow the listen_gateway log file inside the middts host mount
        lg = os.path.join(os.path.dirname(__file__), '../../deploy/logs/middts_listen_gateway.log')
        try:
            # Ensure the file exists
            open(lg, 'a').close()
            subprocess.run(f"chmod 666 '{lg}'", shell=True, check=False)
            follow_container_logs('middts-listener', lg)
        except Exception:
            pass
        # simulators
        for i in range(1, num_sims + 1):
            follow_container_logs(f'sim_{i:03d}', host_logs.get(f'sim_{i:03d}'))
    except Exception:
        # Non-fatal: best-effort
        pass

    # Helper: check whether a named docker volume contains files (non-empty)
    def docker_volume_is_nonempty(volname, timeout=5):
        try:
            # Run a transient busybox container to list the mountpoint contents
            p = subprocess.run(['docker', 'run', '--rm', '-v', f'{volname}:/mnt:ro', 'busybox', 'sh', '-c', 'ls -A /mnt || true'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=timeout)
            out = p.stdout.decode().strip()
            return bool(out)
        except Exception:
            # If we cannot inspect, assume non-empty to be safe
            return True

    # Log whether Influx/Neo4j volumes look already-initialized (helps avoid accidental re-bootstrap)
    try:
        try:
            influx_init_present = docker_volume_is_nonempty('influx_data')
            if influx_init_present:
                info('[influx][INFO] detected existing influx_data volume -> bootstrap env vars will be ignored by Influx (preserving data)\n')
            else:
                info('[influx][INFO] influx_data appears empty -> initial bootstrap env vars will be applied by Influx on first start\n')
        except Exception:
            pass
        try:
            neo4j_init_present = docker_volume_is_nonempty('neo4j_data')
            if neo4j_init_present:
                info('[neo4j][INFO] detected existing neo4j_data volume -> bootstrap env vars (NEO4J_AUTH) will be ignored by Neo4j\n')
            else:
                info('[neo4j][INFO] neo4j_data appears empty -> initial bootstrap env vars will be applied by Neo4j on first start\n')
        except Exception:
            pass
        # Check postgres data volume as well: if pre-existing, postgres will ignore
        # POSTGRES_PASSWORD from env (bootstrap only applies on first init). Warn operator.
        try:
            db_init_present = docker_volume_is_nonempty('db_data')
            if db_init_present:
                info('[db][WARN] detected existing db_data volume -> Postgres bootstrap env vars (including POSTGRES_PASSWORD) will be ignored (existing DB retained)\n')
                info('[db][WARN] If you expect a fresh DB, remove the docker volume `db_data` or use the repository .env to match the existing password.\n')
            else:
                info('[db][INFO] db_data appears empty -> Postgres will apply provided POSTGRES_* env vars on first start\n')
        except Exception:
            pass
    except Exception:
        # non-fatal; continue
        pass

    # Switches para cada domínio (usar nomes numéricos: s1, s2, ...)
    s1 = net.addSwitch('s1')  # tb
    s2 = net.addSwitch('s2')  # middts
    # Um switch para cada simulador, começando de s3
    sim_switches = []
    for i in range(num_sims):
        sim_switches.append(net.addSwitch(f's{i+3}'))

    # Hosts principais
    tb = safe_add_with_status('tb', 
        dimage='tb-node-custom:latest',  # Usar latest ao invés de urllc
        environment={
            'SPRING_DATASOURCE_URL': 'jdbc:postgresql://10.0.0.10:5432/thingsboard',
            'SPRING_DATASOURCE_USERNAME': POSTGRES_USER,
            'SPRING_DATASOURCE_PASSWORD': POSTGRES_PASSWORD,
            'TB_QUEUE_TYPE': 'in-memory',
            'INSTALL_TB': 'true',
            'LOAD_DEMO': 'true',
            # Adicionar configurações JAVA_OPTS para URLLC
            'JAVA_OPTS': '-Xmx12g -Xms8g -XX:+UseG1GC -XX:MaxGCPauseMillis=20 -XX:+DisableExplicitGC -XX:+UseStringDeduplication -XX:G1HeapRegionSize=16m -XX:G1NewSizePercent=40 -XX:G1MaxNewSizePercent=50',
            'TB_QUEUE_RULE_ENGINE_THREAD_POOL_SIZE': '32',
            'TB_QUEUE_TRANSPORT_THREAD_POOL_SIZE': '32',
            'TB_QUEUE_JS_THREAD_POOL_SIZE': '16',
            'TB_QUEUE_TRANSPORT_POLL_INTERVAL': '1',
            'TB_QUEUE_RULE_ENGINE_POLL_INTERVAL': '1',
        },
        volumes=[
            'tb_assets:/data',
            'tb_logs:/var/log/thingsboard',
            f"{host_logs.get('tb')}:/var/log/thingsboard/manual_start.log",
            f"{repo_root}/config/thingsboard-urllc.yml:/usr/share/thingsboard/conf/thingsboard.yml",
        ],
        ports=[8080, 1883],
        port_bindings={8080: 8080, 1883: 1883},
        ip='10.0.0.2',
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
    NEO4J_URL = 'bolt://10.0.1.30:7687'
    INFLUXDB_HOST = '10.0.1.20'
    # Load INFLUXDB_TOKEN from repository .env if present so created containers
    # (middts and simulators) receive the same token the operator configured.
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
    repo_env = os.path.join(repo_root, '.env')
    INFLUXDB_TOKEN = 'token'  # fallback default
    def read_repo_env_value(key, default=None):
        try:
            if os.path.exists(repo_env):
                with open(repo_env, 'r') as ef:
                    for line in ef:
                        line = line.strip()
                        if not line or line.startswith('#'):
                            continue
                        if line.startswith(key + '='):
                            return line.split('=', 1)[1]
        except Exception:
            pass
        return default
    # initial load (may be reloaded later before container creation)
    INFLUXDB_TOKEN = read_repo_env_value('INFLUXDB_TOKEN', INFLUXDB_TOKEN)
    # Read USE_NEO4J from repo .env if present so middts inherits the operator choice
    USE_NEO4J = read_repo_env_value('USE_NEO4J', 'true')
    # Also read org and bucket from repo .env if present
    INFLUXDB_ORG = 'org'
    INFLUXDB_BUCKET = 'bucket'
    try:
        if os.path.exists(repo_env):
            with open(repo_env, 'r') as ef:
                for line in ef:
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    if line.startswith('INFLUXDB_ORG=') or line.startswith('INFLUXDB_ORGANIZATION='):
                        INFLUXDB_ORG = line.split('=', 1)[1]
                    if line.startswith('INFLUXDB_BUCKET='):
                        INFLUXDB_BUCKET = line.split('=', 1)[1]
    except Exception:
        pass
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
            elif line.startswith('USE_NEO4J='):
                new_env_local.append(f'USE_NEO4J={USE_NEO4J}\n'); seen.add('USE_NEO4J')
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
        if 'USE_NEO4J' not in seen:
            new_env_local.append(f'USE_NEO4J={USE_NEO4J}\n')
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

    # Discover NEO4J_AUTH from the middleware .env if present so we can
    # create the neo4j container using the same credential.
    NEO4J_AUTH = 'neo4j/neo4j_pass'
    try:
        md_env = os.path.join(md_base_dir, '.env')
        if os.path.exists(md_env):
            with open(md_env, 'r') as nef:
                for l in nef:
                    s = l.strip()
                    if not s or s.startswith('#'):
                        continue
                    if s.startswith('NEO4J_AUTH='):
                        NEO4J_AUTH = s.split('=', 1)[1]
                        break
    except Exception:
        pass

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
        'middts_listen_gateway': os.path.join(deploy_logs_dir, 'middts_listen_gateway.log'),
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

    # Helper: wait until the underlying Docker container for mn.<name> is Running
    def wait_for_docker_running(name, timeout=15):
        cname = f"mn.{name}"
        for i in range(timeout * 2):
            try:
                p = subprocess.run(["docker", "inspect", "-f", "{{.State.Running}}", cname], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                out = p.stdout.decode().strip()
                if out == 'true':
                    return True
            except Exception:
                pass
            time.sleep(0.5)
        print(f"[WARN] container {cname} not running after {timeout}s")
        return False

    # Agora sim, sobe o middts já com o .env correto
    middts = safe_add_with_status('middts',
        dimage=os.getenv('MIDDTS_IMAGE', 'middts-custom:latest'),
        dcmd="/entrypoint.sh",
        # dcmd="/bin/bash",
        ip='10.0.1.2',
        ports=[8000],
        port_bindings={8000: 8000},
        environment={
            'DJANGO_SETTINGS_MODULE': 'middleware_dt.settings',
            # ensure token is freshly read from repo .env at creation time
            'INFLUXDB_TOKEN': read_repo_env_value('INFLUXDB_TOKEN', INFLUXDB_TOKEN),
            'DEFER_START': '1'
        },
        volumes=[
            f'{env_path}:/middleware-dt/.env',
            # mount host entrypoint to override image entrypoint if present
            f'{host_entrypoint}:/entrypoint.sh',
            f"{host_logs.get('middts')}:/var/log/middts_start.log",
            # mount the listen_gateway log (inside container at /middleware-dt/logs/listen_gateway.log)
            f"{host_logs.get('middts_listen_gateway')}:/middleware-dt/logs/listen_gateway.log",
        ],
        privileged=True
    )

    # Abort early if any critical service failed to create. This avoids later
    # AttributeError when trying to add links to a None node and provides a
    # clearer error message to the operator.
    # parser is external; do not require it as a critical in-topology container
    critical = {'db': pg, 'influxdb': influxdb, 'neo4j': neo4j, 'tb': tb, 'middts': middts}
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
        # If a host-level .env for the simulator exists, mount it so containers
        # receive the same INFLUXDB_TOKEN/INFLUXDB_BUCKET values used by the repo.
        host_sim_env = os.path.join(sim_project_root, '.env')
        if os.path.exists(host_sim_env):
            vols.insert(0, f"{host_sim_env}:/iot_simulator/.env")
        # Read token at simulator creation time so it matches repo .env
        sim_token = read_repo_env_value('INFLUXDB_TOKEN', INFLUXDB_TOKEN)
        env = {
            'INFLUXDB_TOKEN': sim_token,
            'INFLUXDB_HOST': INFLUXDB_HOST,
            'INFLUXDB_ORG': INFLUXDB_ORG,
            'INFLUXDB_BUCKET': INFLUXDB_BUCKET,
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
        # If project-level entrypoint exists, mount it and ensure container runs it
        host_generic_entry = os.path.join(sim_project_root, 'entrypoint.sh')
        entrypoint_arg = None
        # Only mount the generic entrypoint if there's no per-simulator custom entrypoint
        if os.path.exists(host_generic_entry) and not os.path.exists(host_sim_entry):
            # mount the generic entrypoint into the container so it will be executed
            vols.insert(0, f"{host_generic_entry}:/entrypoint.sh")
            entrypoint_arg = '/entrypoint.sh'

        if i == 1 and os.path.exists(host_sim_entry):
            # special-case: sim_001 has a custom host entrypoint (runserver 8001)
            vols.insert(0, f"{host_sim_entry}:/entrypoint.sh")
            env['ALLOWED_HOSTS'] = '*'
            sim = safe_add_with_status(
                name,
                dimage=os.getenv('SIM_IMAGE','iot_simulator:latest'),
                environment=env,
                volumes=vols,
                ip=f'10.0.{10+i}.2',
                ports=[8001],
                port_bindings={8001: 8001},
                privileged=True,
                **({'entrypoint': entrypoint_arg} if entrypoint_arg else {})
            )
        else:
            sim = safe_add_with_status(
                name,
                dimage=os.getenv('SIM_IMAGE','iot_simulator:latest'),
                environment=env,
                volumes=vols,
                ip=f'10.0.{10+i}.2',
                privileged=True,
                **({'entrypoint': entrypoint_arg} if entrypoint_arg else {})
            )
        if sim:
            simuladores.append(sim)
            info(f"[sim] {sim.name} criado — restore_db será executado antes do entrypoint, se disponível.\n")

    # Ligações: cada host ao seu switch
    # Ensure the underlying Docker containers are up and running before
    # attempting to move veth interfaces into them. This reduces race
    # conditions where moveIntf fails with "RTNETLINK answers: No such process".
    try:
        info('[net] aguardando containers docker críticos estarem Running antes de adicionar links...\n')
        for svc in ('tb', 'middts', 'db', 'influxdb', 'neo4j'):
            try:
                wait_for_docker_running(svc, timeout=30)
                # small safety sleep to let the container runtime settle
                time.sleep(0.2)
            except Exception:
                info(f"[net][WARN] esperando por container {svc} falhou ou expirou\n")
    except Exception:
        # non-fatal: continue and let net.addLink attempts proceed
        pass

    add_link(tb, s1)
    add_link(middts, s2)
    add_link(s1, s2)
    for sim, s_sim in zip(simuladores, sim_switches):
        add_link(sim, s_sim)
        # Conecta o switch do simulador ao switch principal s1 para alcançar ThingsBoard
        try:
            add_link(s_sim, s1)
        except Exception:
            # ignore se já existir
            pass
    add_link(s_sim, tb)
    # Simulators should reach Influx without profile shaping
    add_link(s_sim, influxdb, no_profile=True)

    # Serviços centrais ligados aos switches necessários
    # PostgreSQL: apenas ThingsBoard (s1) e Middleware (s2) - simuladores usam SQLite
    add_link(pg, s1, no_profile=True)
    add_link(pg, s2, no_profile=True)
    # InfluxDB: todos os switches (middleware + simuladores precisam)
    add_link(influxdb, s1, no_profile=True)
    add_link(influxdb, s2, no_profile=True)
    for s_sim in sim_switches:
        add_link(influxdb, s_sim, no_profile=True)
    # Neo4j: apenas middleware (s2)
    add_link(neo4j, s2)

    # === IPs e rotas ===
    info("[net] Configurando IPs e rotas\n")
    # IPs para switches:
    # s1: 10.0.0.0/24 (tb)
    # s2: 10.0.1.0/24 (middts)
    # s3...: 10.0.(10+i).0/24 (simuladores)

    # tb
    tb.cmd("ip addr flush dev tb-eth0 scope global || true")
    tb.cmd("ip addr add 10.0.0.2/24 dev tb-eth0 || true")
    tb.cmd("ip link set tb-eth0 up")
    tb.cmd("ip route add default dev tb-eth0 || true")

    # middts
    middts.cmd("ip addr flush dev middts-eth0 scope global || true")
    middts.cmd("ip addr add 10.0.1.2/24 dev middts-eth0 || true")
    middts.cmd("ip link set middts-eth0 up")
    middts.cmd("ip route add default dev middts-eth0 || true")

    # simuladores
    for idx, sim in enumerate(simuladores, 1):
        sim_if = f"sim_{idx:03d}-eth0"
        sim_ip = f"10.0.{10+idx}.2/24"
        sim.cmd(f"ip addr flush dev {sim_if} scope global || true")
        sim.cmd(f"ip addr add {sim_ip} dev {sim_if} || true")
        sim.cmd(f"ip link set {sim_if} up")
        sim.cmd(f"ip route add default dev {sim_if} || true")

    # Serviços centrais: configuração de interfaces
    # PostgreSQL: apenas s1 (ThingsBoard) e s2 (Middleware) - simuladores usam SQLite
    pg_ifaces = ["db-eth0", "db-eth1"]
    pg_ips = ["10.0.0.10/24", "10.0.1.10/24"]
    for iface, ip in zip(pg_ifaces, pg_ips):
        pg.cmd(f"ip addr flush dev {iface} scope global || true")
        pg.cmd(f"ip addr add {ip} dev {iface} || true")
        pg.cmd(f"ip link set {iface} up")
        pg.cmd(f"ip route add 10.0.0.0/16 dev {iface} || true")

    # InfluxDB: s2 (middleware) + todos os switches de simuladores
    influx_ifaces = ["influxdb-eth0"] + [f"influxdb-eth{i+1}" for i in range(len(sim_switches))]
    influx_ips = ["10.0.1.20/24"] + [f"10.0.{10+i+1}.20/24" for i in range(len(sim_switches))]
    for iface, ip in zip(influx_ifaces, influx_ips):
        influxdb.cmd(f"ip addr flush dev {iface} scope global || true")
        influxdb.cmd(f"ip addr add {ip} dev {iface} || true")
        influxdb.cmd(f"ip link set {iface} up")
        influxdb.cmd(f"ip route add 10.0.0.0/16 dev {iface} || true")

    # Neo4j
    neo4j.cmd("ip addr flush dev neo4j-eth0 scope global || true")
    neo4j.cmd("ip addr add 10.0.1.30/24 dev neo4j-eth0 || true")
    neo4j.cmd("ip link set neo4j-eth0 up")
    neo4j.cmd("ip route add 10.0.0.0/16 dev neo4j-eth0 || true")

    # Parser runs outside the Containernet topology; no in-topology IPs configured.


    # Agora sim, inicia a rede
    net.start()

    # Restore Docker port forwarding rules that may be overridden by Mininet
    def restore_docker_port_forwarding():
        """Check external access and setup socat fallback if needed"""
        try:
            import subprocess
            import json
            import socket
            
            # Wait a bit for containers to be fully ready
            time.sleep(3)
            
            info("[net] Testing external access to services...\n")
            
            # Test external access function
            def test_external_access(port, timeout=5):
                """Test if a port is accessible from external interface"""
                try:
                    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    sock.settimeout(timeout)
                    # Test on all external interfaces
                    for test_ip in ['0.0.0.0', '10.22.10.102', '127.0.0.1']:
                        try:
                            result = sock.connect_ex((test_ip, port))
                            if result == 0:
                                sock.close()
                                return True
                        except:
                            continue
                    sock.close()
                    return False
                except:
                    return False
            
            # Get container IPs for socat fallback
            def get_container_ip(container_name):
                try:
                    result = subprocess.run(['docker', 'inspect', container_name], 
                                          capture_output=True, text=True)
                    if result.returncode == 0:
                        data = json.loads(result.stdout)[0]
                        return data['NetworkSettings']['IPAddress']
                except:
                    pass
                return None
            
            # Kill any existing socat processes
            subprocess.run(['pkill', '-f', 'socat.*900'], check=False)
            
            services_to_test = {
                'middleware': {'container': 'mn.middts', 'port': 8000, 'fallback_port': 9000},
                'simulator': {'container': 'mn.sim_001', 'port': 8001, 'fallback_port': 9001}, 
                'thingsboard': {'container': 'mn.tb', 'port': 8080, 'fallback_port': 9080}
            }
            
            fallback_needed = []
            
            # Test each service
            for service_name, config in services_to_test.items():
                port = config['port']
                if test_external_access(port):
                    info(f"[net] ✅ {service_name} port {port} - external access OK\n")
                else:
                    info(f"[net] ❌ {service_name} port {port} - external access FAILED, will setup socat fallback\n")
                    fallback_needed.append(config)
            
            # Setup socat fallback for failed services
            if fallback_needed:
                info(f"[net] Setting up socat fallback for {len(fallback_needed)} services...\n")
                
                for config in fallback_needed:
                    container_ip = get_container_ip(config['container'])
                    if container_ip:
                        fallback_port = config['fallback_port']
                        original_port = config['port']
                        
                        # Start socat proxy
                        cmd = ['socat', 
                               f'TCP-LISTEN:{fallback_port},bind=0.0.0.0,fork,reuseaddr', 
                               f'TCP:{container_ip}:{original_port}']
                        
                        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        info(f"[net] 🔄 Started socat proxy: external {fallback_port} -> {container_ip}:{original_port}\n")
                        
                        # Brief test of fallback
                        time.sleep(1)
                        if test_external_access(fallback_port, timeout=2):
                            info(f"[net] ✅ Fallback port {fallback_port} working!\n")
                        else:
                            info(f"[net] ⚠️  Fallback port {fallback_port} test failed\n")
                
                # Summary
                info(f"\n[net] 📋 ACCESS SUMMARY:\n")
                for service_name, config in services_to_test.items():
                    if config in fallback_needed:
                        info(f"[net]   {service_name}: ❌ port {config['port']} -> 🔄 fallback port {config['fallback_port']}\n")
                    else:
                        info(f"[net]   {service_name}: ✅ port {config['port']} (direct access)\n")
                        
            else:
                info("[net] ✅ All services have working external access - no fallback needed\n")
                        
        except Exception as e:
            info(f"[net][WARN] Port forwarding check failed: {e}\n")
            # Fallback: setup socat for all services anyway
            try:
                info("[net] Setting up socat as fallback due to check failure...\n")
                subprocess.run(['pkill', '-f', 'socat.*900'], check=False)
                
                services = [
                    ('mn.middts', 8000, 9000),
                    ('mn.sim_001', 8001, 9001),
                    ('mn.tb', 8080, 9080)
                ]
                
                for container, orig_port, fallback_port in services:
                    result = subprocess.run(['docker', 'inspect', container], 
                                          capture_output=True, text=True)
                    if result.returncode == 0:
                        data = json.loads(result.stdout)[0]
                        container_ip = data['NetworkSettings']['IPAddress']
                        if container_ip:
                            cmd = ['socat', 
                                   f'TCP-LISTEN:{fallback_port},bind=0.0.0.0,fork,reuseaddr', 
                                   f'TCP:{container_ip}:{orig_port}']
                            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            info(f"[net] Emergency socat: {fallback_port} -> {container_ip}:{orig_port}\n")
            except Exception as e2:
                info(f"[net][WARN] Emergency socat setup failed: {e2}\n")

    # Ensure the underlying Docker containers are Running before we
    # execute commands that expect the network interfaces to be present.
    # This is critical to avoid moveIntf "No such process" errors.
    try:
        info('[net] aguardando containers docker estarem Running após net.start()...\n')
        for svc in ('tb', 'middts', 'db', 'influxdb', 'neo4j'):
            ok = wait_for_docker_running(svc, timeout=30)
            if not ok:
                info(f"[net][ERROR] container mn.{svc} not running after wait; aborting topology start to avoid moveIntf failures\n")
                # stop network and exit early
                try:
                    net.stop()
                except Exception:
                    pass
                return
            # short safety pause
            time.sleep(0.1)
            
        # Restore Docker port forwarding after all containers are running
        restore_docker_port_forwarding()
        
    except Exception:
        # non-fatal: proceed and let later checks catch issues
        pass

    # Additional check: verify container network namespace exists and host-side veth peer is present.
    def wait_for_container_net_ready(name, iface_hint=None, timeout=20):
        cname = f"mn.{name}"
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                # get PID of container
                p = subprocess.run(['docker', 'inspect', '-f', '{{.State.Pid}}', cname], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                pid = p.stdout.decode().strip()
                if pid and pid != '0':
                    # check that /proc/<pid>/ns/net exists
                    ns_path = f'/proc/{pid}/ns/net'
                    if os.path.exists(ns_path):
                        # optionally check host-side interface presence if hint provided
                        if iface_hint:
                            # look for a host link whose name contains the service iface_hint
                            out = subprocess.run(['ip', '-o', 'link', 'show'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                            if iface_hint in out.stdout.decode():
                                return True
                        else:
                            return True
            except Exception:
                pass
            time.sleep(0.5)
        return False

    try:
        # For the services that previously failed with moveIntf, perform an extra readiness check
        for svc, hint in (('neo4j','neo4j-eth0'), ('influxdb','influxdb-eth0')):
            ok = wait_for_container_net_ready(svc, iface_hint=hint, timeout=25)
            if not ok:
                info(f"[net][WARN] container {svc} network namespace or host veth not detected after wait; moveIntf may fail\n")
    except Exception:
        pass

    # Further ensure network namespace and veth peer exist for critical containers
    def wait_for_container_netns_and_veth(svc, veth_suffix=None, timeout=20):
        """Wait until docker reports mn.<svc> running and the expected veth peer appears on host.
        veth_suffix: when provided, look for a host veth that contains this suffix (e.g., 'neo4j-eth0')
        """
        cname = f"mn.{svc}"
        end = time.time() + timeout
        while time.time() < end:
            try:
                p = subprocess.run(['docker', 'inspect', '-f', '{{.State.Running}}', cname], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                if p.returncode == 0 and p.stdout.decode().strip() == 'true':
                    # if veth_suffix provided, check host ip link for peer name
                    if veth_suffix:
                        # host veth names often include the container interface name as suffix; try to find it
                        out = subprocess.run(['ip', '-o', 'link', 'show'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                        links = out.stdout.decode()
                        if veth_suffix in links:
                            return True
                    else:
                        return True
            except Exception:
                pass
            time.sleep(0.25)
        return False

    try:
        # wait longer for influxdb and neo4j network peers specifically
        if not wait_for_container_netns_and_veth('influxdb', veth_suffix='influxdb-eth0', timeout=30):
            info('[net][WARN] influxdb veth/namespace not visible after wait; moveIntf may fail\n')
        if not wait_for_container_netns_and_veth('neo4j', veth_suffix='neo4j-eth0', timeout=30):
            info('[net][WARN] neo4j veth/namespace not visible after wait; moveIntf may fail\n')
    except Exception:
        pass

    # Ensure critical container interfaces are actually UP and have the expected IP
    # inside their network namespace. This avoids the need for manual nsenter
    # when moveIntf or net.start() leaves the container-side veth down or
    # missing the assigned IP (race observed in practice).
    def ensure_container_iface_up(name, iface, ip_cidr, route_cidr='10.0.0.0/16', retries=6, delay=0.5):
        """Idempotently ensure that container mn.<name> has `iface` UP and `ip_cidr` assigned.
        Uses nsenter against the container PID obtained via _get_container_pid.
        Returns True if successful or already configured, False otherwise.
        """
        try:
            pid = _get_container_pid(name, timeout=10)
            if not pid:
                info(f"[net][WARN] cannot ensure iface for {name}: container PID not found\n")
                return False
            for attempt in range(retries):
                try:
                    # Check if the IP is already present on the iface
                    p = subprocess.run(['nsenter', '-t', str(pid), '-n', 'ip', '-o', 'addr', 'show', 'dev', iface], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                    out = p.stdout.decode().strip()
                    if ip_cidr.split('/')[0] in out:
                        # ensure link up and route present
                        subprocess.run(['nsenter', '-t', str(pid), '-n', 'ip', 'link', 'set', iface, 'up'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        subprocess.run(['nsenter', '-t', str(pid), '-n', 'ip', 'route', 'add', route_cidr, 'dev', iface], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        return True
                    # attempt to bring link up and add ip/route
                    subprocess.run(['nsenter', '-t', str(pid), '-n', 'ip', 'link', 'set', iface, 'up'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    subprocess.run(['nsenter', '-t', str(pid), '-n', 'ip', 'addr', 'add', ip_cidr, 'dev', iface], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    subprocess.run(['nsenter', '-t', str(pid), '-n', 'ip', 'route', 'add', route_cidr, 'dev', iface], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                except Exception:
                    # ignore and retry
                    pass
                time.sleep(delay * (attempt + 1))
            info(f"[net][WARN] failed to ensure iface {iface} in container {name} after {retries} attempts\n")
            return False
        except Exception:
            return False

    try:
        # Try to ensure the Influx and Neo4j interfaces are configured inside their
        # container network namespaces. This fixes the common case where simulators
        # cannot reach Influx at 10.0.1.20 because the container-side veth was left
        # down or without the IP assigned.
        ensure_container_iface_up('influxdb', 'influxdb-eth0', '10.0.1.20/24')
        # Ensure the Influx container has an explicit route back to the simulator
        # fabric so replies (SYN-ACK) go out via influxdb-eth0 with the 10.0.1.20
        # source address. This prevents asymmetric routing where the kernel would
        # send replies out via the docker bridge (172.17.x) and the TCP handshake
        # would never complete.
        ensure_container_route('influxdb', '10.0.0.0/24', 'influxdb-eth0')
        ensure_container_iface_up('neo4j', 'neo4j-eth0', '10.0.1.30/24')
    except Exception:
        # non-fatal; continue
        pass

    # Ensure simulators have a route to the 10.0.0.0/16 fabric via their sim_xxx-eth0
    # interface so they can reach Influx (10.0.1.20) even if Docker's default route
    # points at the bridge (172.17.x.x). This is idempotent and will be applied
    # on each topology start.
    def ensure_container_route(name, dest_cidr, dev, src=None, retries=6, delay=0.5):
        try:
            pid = _get_container_pid(name, timeout=10)
            if not pid:
                info(f"[net][WARN] cannot ensure route for {name}: container PID not found\n")
                return False
            for attempt in range(retries):
                try:
                    # check if route already exists
                    p = subprocess.run(['nsenter', '-t', str(pid), '-n', 'ip', 'route', 'show', dest_cidr], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                    out = p.stdout.decode().strip()
                    if out:
                        return True
                    # If src not provided and dest is a single host, attempt to derive src from the device IP
                    add_cmd = ['nsenter', '-t', str(pid), '-n', 'ip', 'route', 'add', dest_cidr, 'dev', dev]
                    if not src and dest_cidr.endswith('/32'):
                        try:
                            p2 = subprocess.run(['nsenter', '-t', str(pid), '-n', 'ip', '-o', '-4', 'addr', 'show', 'dev', dev], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                            out2 = p2.stdout.decode().strip()
                            if out2:
                                # extract the first IPv4 address
                                ip4 = out2.split()[-1].split('/')[0]
                                if ip4:
                                    add_cmd += ['src', ip4]
                        except Exception:
                            pass
                    elif src:
                        add_cmd += ['src', src]
                    # add route via device (optionally with src)
                    subprocess.run(add_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                except Exception:
                    pass
                time.sleep(delay * (attempt + 1))
            info(f"[net][WARN] failed to add route {dest_cidr} via {dev} in container {name}\n")
            return False
        except Exception:
            return False

    try:
        for i in range(1, num_sims + 1):
            sim_name = f"sim_{i:03d}"
            sim_iface = f"{sim_name}-eth0"
            ensure_container_route(sim_name, '10.0.0.0/16', sim_iface)
            # Also add a specific host route for the Influx address so the kernel
            # selects the simulator's 10.0.x.x source when connecting to 10.0.1.20.
            ensure_container_route(sim_name, '10.0.1.20/32', sim_iface)
    except Exception:
        pass

    # After network start, discover container IPs and inject into .env files
    try:
        # helper to resolve Mininet/Containernet container objects to docker names/IPs
        def container_ip(container_obj):
            try:
                name = container_obj.name
                # docker inspect
                import subprocess, json
                out = subprocess.check_output(['docker', 'inspect', name])
                data = json.loads(out)
                # get first network IP
                ip = None
                if data and isinstance(data, list):
                    nets = data[0].get('NetworkSettings', {}).get('Networks', {})
                    for v in nets.values():
                        ip = v.get('IPAddress')
                        if ip:
                            break
                return ip
            except Exception:
                return None

        influx_ip = container_ip(influxdb) or os.getenv('INFLUXDB_HOST', '10.0.1.20')
        neo4j_ip = container_ip(neo4j) or os.getenv('NEO4J_HOST', '10.0.1.30')
    except Exception:
        influx_ip = os.getenv('INFLUXDB_HOST', '10.0.1.20')
        neo4j_ip = os.getenv('NEO4J_HOST', '10.0.1.30')

    # Write these IPs into middleware and simulator .env files (idempotent)
    try:
        md_env_path = os.path.join(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')), 'services', 'middleware-dt', '.env')
        sim_env_path = os.path.join(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')), 'services', 'iot_simulator', '.env')

        def upsert_env(path, key, value):
            lines = []
            if os.path.exists(path):
                with open(path, 'r') as f:
                    lines = f.read().splitlines()
            found = False
            for i, ln in enumerate(lines):
                if ln.startswith(key + '='):
                    lines[i] = f'{key}={value}'
                    found = True
                    break
            if not found:
                lines.append(f'{key}={value}')
            with open(path, 'w') as f:
                f.write('\n'.join(lines) + '\n')

        # Middleware .env updates
        try:
            upsert_env(md_env_path, 'INFLUXDB_HOST', influx_ip)
            upsert_env(md_env_path, 'INFLUXDB_PORT', str(INFLUXDB_PORT if 'INFLUXDB_PORT' in globals() else 8086))
            upsert_env(md_env_path, 'INFLUXDB_BUCKET', INFLUXDB_BUCKET)
            upsert_env(md_env_path, 'INFLUXDB_ORGANIZATION', INFLUXDB_ORG)
            upsert_env(md_env_path, 'INFLUXDB_TOKEN', INFLUXDB_TOKEN)
            upsert_env(md_env_path, 'NEO4J_URL', f'bolt://{neo4j_ip}:7687')
            # keep NEO4J_AUTH untouched
            # Injector for external parser: prefer a running docker container named 'parser'
            parser_host = None
            parser_port = None
            try:
                p = subprocess.run(['docker', 'ps', '--filter', 'name=^parser$', '--format', '{{.Names}} {{.Ports}}'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                out = p.stdout.decode().strip()
                if out:
                    # output like: "parser 0.0.0.0:8082->8080/tcp, 0.0.0.0:8083->8081/tcp"
                    parts = out.split(None, 1)
                    parser_host = '127.0.0.1'
                    if len(parts) > 1 and '->' in parts[1]:
                        # find first host port mapping
                        proto_parts = parts[1].split(',')
                        first = proto_parts[0].strip()
                        if ':' in first:
                            hp = first.split(':')[-1]
                            if '->' in hp:
                                hp = hp.split('->')[0]
                            parser_port = hp.split('-')[0]
                # fallback to repo .env or defaults
            except Exception:
                pass
            if not parser_host:
                # try read from repo .env (PARSER_HOST/PARSER_PORT) or fallback
                parser_host = read_repo_env_value('PARSER_HOST', '127.0.0.1')
                parser_port = read_repo_env_value('PARSER_PORT', '8082')
            upsert_env(md_env_path, 'PARSER_HOST', parser_host)
            upsert_env(md_env_path, 'PARSER_PORT', str(parser_port))
        except Exception:
            pass

        # Simulator .env updates
        try:
            upsert_env(sim_env_path, 'INFLUXDB_HOST', influx_ip)
            upsert_env(sim_env_path, 'INFLUXDB_PORT', str(INFLUXDB_PORT if 'INFLUXDB_PORT' in globals() else 8086))
            upsert_env(sim_env_path, 'INFLUXDB_BUCKET', INFLUXDB_BUCKET)
            upsert_env(sim_env_path, 'INFLUXDB_ORGANIZATION', INFLUXDB_ORG)
            upsert_env(sim_env_path, 'INFLUXDB_TOKEN', INFLUXDB_TOKEN)
            # Simulators don't call the parser directly, but keep PARSER_* vars in sync
            try:
                upsert_env(sim_env_path, 'PARSER_HOST', read_repo_env_value('PARSER_HOST', '127.0.0.1'))
                upsert_env(sim_env_path, 'PARSER_PORT', read_repo_env_value('PARSER_PORT', '8082'))
            except Exception:
                pass
        except Exception:
            pass
    except Exception:
        info('[env][WARN] failed to inject container IPs into .env files\n')
    if QUIET:
        print(f"[NET] network started; hosts: {len(simuladores)+6} (including core services)")

    # Apply URLLC optimizations automatically after network start
    def apply_urllc_optimizations():
        """Apply network and system optimizations for URLLC performance"""
        try:
            script_path = os.path.join(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')), 'scripts', 'apply_urllc_minimal.sh')
            if os.path.exists(script_path):
                info('[URLLC] Applying optimizations...\n')
                result = subprocess.run(['bash', script_path], capture_output=True, text=True)
                if result.returncode == 0:
                    info('[URLLC] Optimizations applied successfully\n')
                    # Aguardar um pouco para as otimizações serem aplicadas
                    import time
                    time.sleep(3)
                else:
                    info(f'[URLLC][WARN] Optimization script failed: {result.stderr}\n')
            else:
                info('[URLLC][WARN] Optimization script not found\n')
        except Exception as e:
            info(f'[URLLC][ERROR] Failed to apply optimizations: {e}\n')

    # Apply optimizations after network is fully started
    apply_urllc_optimizations()

    # Ensure Influx bucket exists and token is valid. This runs after network start
    # so container is reachable via docker-proxy on localhost.
    def ensure_influx_bucket(token, org, bucket):
        import time
        # Prefer requests if available, otherwise fallback to curl via subprocess
        try:
            import requests
            use_requests = True
        except Exception:
            use_requests = False
        url_base = 'http://127.0.0.1:8086'
        headers = {'Authorization': f'Token {token}'}
        # wait until /health is OK
        for _ in range(20):
            try:
                if use_requests:
                    r = requests.get(f'{url_base}/health', headers=headers, timeout=2)
                    ok = (r.status_code == 200)
                else:
                    import subprocess
                    rc = subprocess.run(['curl','-sS','-H',f'Authorization: Token {token}', f'{url_base}/health'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=3)
                    ok = (rc.returncode == 0 and rc.stdout)
                if ok:
                    break
            except Exception:
                pass
            time.sleep(1)
        # verify token by listing orgs
        try:
            if use_requests:
                r = requests.get(f'{url_base}/api/v2/orgs?org={org}', headers=headers, timeout=3)
                if r.status_code != 200:
                    info(f"[influx][WARN] token check failed status={r.status_code} body={r.text}\n")
                    return False
                orgs = r.json().get('orgs', [])
            else:
                import subprocess, json as _json
                rc = subprocess.run(['curl','-sS','-H',f'Authorization: Token {token}', f'{url_base}/api/v2/orgs?org={org}'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=3)
                if rc.returncode != 0:
                    info('[influx][WARN] curl failed when listing orgs\n')
                    return False
                try:
                    orgs = _json.loads(rc.stdout.decode()).get('orgs', [])
                except Exception:
                    info('[influx][WARN] failed to parse orgs json\n')
                    return False
            if not orgs:
                info(f"[influx][WARN] org {org} not found\n")
                return False
            org_id = orgs[0]['id']
            # check buckets
            if use_requests:
                rb = requests.get(f'{url_base}/api/v2/buckets?orgID={org_id}', headers=headers, timeout=3)
                if rb.status_code != 200:
                    info(f"[influx][WARN] buckets list failed {rb.status_code}\n")
                    return False
                buckets = rb.json().get('buckets', [])
            else:
                rc = subprocess.run(['curl','-sS','-H',f'Authorization: Token {token}', f'{url_base}/api/v2/buckets?orgID={org_id}'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=3)
                try:
                    import json as _json
                    buckets = _json.loads(rc.stdout.decode()).get('buckets', [])
                except Exception:
                    info('[influx][WARN] failed to parse buckets json\n')
                    return False
            names = [b['name'] for b in buckets]
            if bucket in names:
                info(f"[influx] bucket '{bucket}' already exists\n")
                return True
            # create bucket
            payload = { 'orgID': org_id, 'name': bucket, 'retentionRules': [] }
            if use_requests:
                rc = requests.post(f'{url_base}/api/v2/buckets', headers={**headers, 'Content-Type':'application/json'}, json=payload, timeout=5)
                if rc.status_code in (200,201):
                    info(f"[influx] bucket '{bucket}' created\n")
                    return True
                else:
                    info(f"[influx][ERROR] failed to create bucket {rc.status_code} body={rc.text}\n")
                    return False
            else:
                import subprocess, json as _json
                rc = subprocess.run(['curl','-sS','-X','POST','-H',f'Authorization: Token {token}','-H','Content-Type: application/json','-d',_json.dumps(payload), f'{url_base}/api/v2/buckets'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=5)
                if rc.returncode == 0 and rc.stdout:
                    info(f"[influx] bucket '{bucket}' created (curl)\n")
                    return True
                info('[influx][ERROR] curl failed to create bucket\n')
                return False
        except Exception as e:
            info(f"[influx][ERROR] exception during ensure_influx_bucket: {e}\n")
            return False

    # read token/org/bucket from repo .env and try to ensure bucket
    try:
        repo_env = os.path.join(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')), '.env')
        token = None; org = None; bucket = None
        if os.path.exists(repo_env):
            with open(repo_env) as ef:
                for line in ef:
                    if line.startswith('INFLUXDB_TOKEN='):
                        token = line.strip().split('=',1)[1]
                    if line.startswith('INFLUXDB_ORG=') or line.startswith('INFLUXDB_ORGANIZATION='):
                        org = line.strip().split('=',1)[1]
                    if line.startswith('INFLUXDB_BUCKET='):
                        bucket = line.strip().split('=',1)[1]
        if token and org and bucket:
            try:
                # try to import requests; if missing, fallback to curl call via subprocess
                ensure_ok = ensure_influx_bucket(token, org, bucket)
                if not ensure_ok:
                    info('[influx][WARN] ensure_influx_bucket failed; you may need to re-bootstrap or check token\n')
            except Exception:
                info('[influx][WARN] python requests unavailable or ensure failed; skipping automatic bucket ensure\n')
    except Exception:
        pass

    # SEÇÃO REMOVIDA: Pós-configuração estava sobrescrevendo IPs corretos 10.0.x.x
    # As configurações corretas já foram aplicadas anteriormente na seção "=== IPs e rotas ==="
    info("[net] IPs já configurados corretamente na seção anterior\n")
    
    # Manter apenas configurações essenciais do InfluxDB
    try:
        # ensure influx iface + route back to simulator fabric  
        ensure_container_iface_up('influxdb', 'influxdb-eth0', '10.0.1.20/24')
        ensure_container_route('influxdb', '10.0.0.0/16', 'influxdb-eth0')
    except Exception:
        pass
    try:
        for idx in range(1, num_sims + 1):
            sim_name = f"sim_{idx:03d}"
            sim_iface = f"{sim_name}-eth0"
            # ensure simulators have specific host route to Influx
            try:
                ensure_container_route(sim_name, '10.0.0.0/16', sim_iface)
                ensure_container_route(sim_name, '10.0.1.20/32', sim_iface)
            except Exception:
                # best-effort per-simulator
                pass
    except Exception:
        pass

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
    tb_ready = wait_for_thingsboard(host='10.0.0.2', port=8080, timeout=180, interval=3)
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

    # --- Smoke-test: check Influx /health and a small POST from sim_001 and log results ---
    def _smoke_test_influx(sim_name='sim_001'):
        try:
            # locate repo .env and host log path
            repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
            repo_env = os.path.join(repo_root, '.env')
            token = None; org = None; bucket = None
            if os.path.exists(repo_env):
                try:
                    with open(repo_env) as ef:
                        for line in ef:
                            if line.startswith('INFLUXDB_TOKEN='):
                                token = line.strip().split('=',1)[1]
                            if line.startswith('INFLUXDB_ORG=') or line.startswith('INFLUXDB_ORGANIZATION='):
                                org = line.strip().split('=',1)[1]
                            if line.startswith('INFLUXDB_BUCKET='):
                                bucket = line.strip().split('=',1)[1]
                except Exception:
                    pass
            log_path = host_logs.get('influxdb')
            if not log_path:
                return False
            # build commands
            health_cmd = (
                f"docker run --rm --network container:mn.{sim_name} curlimages/curl:8.3.0 -sS -o /dev/stderr -w 'HTTP%{{http_code}}\\n' --max-time 3 http://10.10.2.20:8086/health"
            )
            post_cmd = (
                f"docker run --rm --network container:mn.{sim_name} curlimages/curl:8.3.0 -sS -o /dev/stderr -w 'HTTP%{{http_code}}\\n' -XPOST 'http://10.10.2.20:8086/api/v2/write?org={org or ''}&bucket={bucket or ''}&precision=ms' -d 'm,host=smoke value=1' --max-time 5"
            )
            if token:
                post_cmd = post_cmd.replace("-XPOST", f"-H 'Authorization: Token {token}' -XPOST")
            ts = time.strftime('%Y-%m-%d %H:%M:%S')
            try:
                with open(log_path, 'a') as lf:
                    lf.write(f"[{ts}] [SMOKE] HEALTH_CMD: {health_cmd}\n")
                    try:
                        p = subprocess.run(health_cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                        lf.write(f"[{ts}] [SMOKE][HEALTH] {p.stdout.decode(errors='ignore')}\n")
                    except Exception as e:
                        lf.write(f"[{ts}] [SMOKE][HEALTH][ERR] {e}\n")
                    lf.write(f"[{ts}] [SMOKE] POST_CMD: {post_cmd}\n")
                    try:
                        p2 = subprocess.run(post_cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                        lf.write(f"[{ts}] [SMOKE][POST] {p2.stdout.decode(errors='ignore')}\n")
                    except Exception as e:
                        lf.write(f"[{ts}] [SMOKE][POST][ERR] {e}\n")
            except Exception:
                pass
            return True
        except Exception:
            return False

    try:
        _smoke_test_influx('sim_001')
    except Exception:
        pass

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
    parser.add_argument('--profile', type=str, default=None, help='Link profile to use: urllc | best_effort | eMBB')
    args = parser.parse_args()
    # Configure module-level flags
    QUIET = args.quiet or not args.verbose
    VERBOSE = args.verbose
    # Propagate profile into environment so run_topo() can pick it up early
    if args.profile:
        os.environ['TOPO_PROFILE'] = args.profile
    # If verbose, restore info to original by setting mininet log level higher
    if VERBOSE:
        # restore info printing by setting loglevel and not overriding
        setLogLevel('info')
    run_topo(num_sims=args.sims)
