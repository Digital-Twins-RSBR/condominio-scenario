# Conversation export — condominio-scenario

Date: 2025-10-06

This file is an export of the interactive session (commands, findings and changes) made while working on the `condominio-scenario` repository. Paste or open this file in another VS Code instance to get the same context and run the same commands locally.

## Short purpose

- Capture what was learned during the debugging and optimization of the topology + ODTE runs.
- Document code changes applied for faster, more robust topology startup and graceful ODTE shutdown.
- Provide reproduction steps, important env variables, changed files and next steps so you can continue the work on another machine.

## High-level summary

1. Goals of the session
   - Run reproducible ODTE experiments across three profiles: URLLC, eMBB and best_effort, always from a fresh topology.
   - Ensure graceful ODTE shutdown saves partial results on Ctrl+C.
   - Speed up and harden topology startup to avoid hot-swap artifacts and race conditions.
   - Implement TB-first startup option (start ThingsBoard earlier) and measure improvement in time-to-ready.

2. Key technologies
   - Containernet / Mininet topology (`services/topology/topo_qos.py`).
   - Docker containers for services (mn.tb, mn.db, mn.influxdb, mn.middts, mn.neo4j, mn.sim_XXX).
   - Postgres, InfluxDB v2, ThingsBoard, Neo4j, middleware (middts), IoT simulators.
   - Makefile-driven workflows and helper scripts under `scripts/`.

3. Major changes implemented in the session
   - Added graceful ODTE shutdown script and wired it to `Makefile` targets (saves partial results on CTRL+C).
   - Hardened device detection script (retries, SQL fallback, local cache) to avoid false negatives.
   - Parallelized simulator heartbeat updates in the hot-swap script.
   - Added `scripts/prepull_images.sh` to pre-pull Docker images in parallel and `Makefile` target `prepull-images`.
   - Made many waits and poll intervals in `services/topology/topo_qos.py` configurable via env vars.
   - Implemented `TOPO_TB_FIRST` mode (start ThingsBoard earlier) and added a safer TB wait policy.

4. Problems observed during runs
   - Race conditions between container creation and network namespace / veth setup (RTNETLINK / moveIntf warnings).
   - Private/local custom images cannot be pulled from public registries — `prepull_images.sh` shows expected pull access failures for local images; building/pushing these images in the target machine is required.
   - ThingsBoard HTTP sometimes times out while `thingsboard.jar` is still starting; starting middts too early can cause conflicts (DB migrations, ports). TB-first changes mitigate by waiting longer when appropriate.

## Files added / edited (delta)

- Added `scripts/prepull_images.sh` — helper to parallel docker pull a list of images.
- Edited `Makefile` — added `prepull-images` target and call from `dev` flow.
- Edited `services/topology/topo_qos.py` —
  - environment-driven timeouts and polling values introduced: `TOPO_WAIT_RUNNING_SECS`, `TOPO_INTER_CONTAINER_SLEEP`, `TOPO_WAIT_NET_READY_SECS`, `TOPO_NET_POLL_INTERVAL`.
  - `TOPO_TB_FIRST` (boolean) added; TB-first startup path implemented.
  - safer TB wait added: `TOPO_TB_WAIT_SECS`, `TOPO_TB_WAIT_INTERVAL`, and `TOPO_TB_EXTRA_WAIT_IF_PROCESS` to give TB more time if `thingsboard.jar` is present.
- Other earlier script changes: `scripts/graceful_odte.sh`, `scripts/apply_comprehensive_filter.sh`, `scripts/apply_profile_hotswap.sh` (parallelization and robustness improvements applied earlier in session).

## Important environment variables (used by topology runner)

- TOPO_TB_FIRST=1                # enable TB-first startup
- TOPO_TB_WAIT_SECS              # default 120 when TB-first, else 180
- TOPO_TB_WAIT_INTERVAL=3        # poll interval for TB HTTP
- TOPO_TB_EXTRA_WAIT_IF_PROCESS=60   # extra wait if thingsboard.jar is running but HTTP timed out
- TOPO_WAIT_RUNNING_SECS=20     # wait for containers to be Running after net.start()
- TOPO_INTER_CONTAINER_SLEEP=0.05
- TOPO_WAIT_NET_READY_SECS=25   # net namespace/veth poll
- TOPO_NET_POLL_INTERVAL=0.25

Note: `scripts/prepull_images.sh` can be used to reduce delays caused by pulling images. Custom images (e.g., `tb-node-custom`, `middts-custom`, `iot_simulator`) typically must be built locally or pulled from a private registry.

## Where logs are written

- Topology verbose logs (examples): `deploy/logs/topo_urllc_verbose.log`, `deploy/logs/topo_urllc_tbfirst_verbose.log`.
- Container startup logs are followed and appended to `deploy/logs/*.log` (e.g., `tb_start.log`, `middts_start.log`, `influx_start.log`, `sim_001_start.log`).

## Repro recipe — run the TB-first topology and capture timing

1. (Optional) Pre-pull images to avoid on-run downloads (some custom images will fail to pull from public registry):

```sh
./scripts/prepull_images.sh || true
```

2. Run topology in TB-first mode with verbose logging and reduced waits (example):

```sh
VERBOSE=1 PRESERVE_STATE=0 TOPO_TB_FIRST=1 \
TOPO_WAIT_RUNNING_SECS=12 TOPO_WAIT_NET_READY_SECS=12 \
TOPO_NET_POLL_INTERVAL=0.12 TOPO_TB_WAIT_SECS=120 TOPO_TB_EXTRA_WAIT_IF_PROCESS=120 \
make topo PROFILE=urllc 2>&1 | tee deploy/logs/topo_urllc_tbfirst_verbose.log
```

3. Compare to baseline (no TB-first):

```sh
VERBOSE=1 PRESERVE_STATE=0 make topo PROFILE=urllc 2>&1 | tee deploy/logs/topo_urllc_verbose.log
```

4. Extract timestamps manually from the saved logs for these markers:
   - PostgreSQL finished accepting connections
   - `thingsboard.jar` launched (line where we call `java -jar`)
   - ThingsBoard HTTP responded (first non-000 status in `wait_for_thingsboard`)
   - middts entrypoint started
   - Simulators entrypoints started

5. Compute deltas (time-to-TB-http, time-to-all-sims-start) to quantify improvement.

## Quick troubleshooting notes (common issues and fixes)

- If `scripts/prepull_images.sh` shows "pull access denied" for custom images (e.g., `tb-node-custom`): build those images locally on the target machine or load them from an archive.
- If you see lots of RTNETLINK / moveIntf warnings: Mininet/Containernet is racing with Docker; try increasing `TOPO_WAIT_RUNNING_SECS` and `TOPO_WAIT_NET_READY_SECS`, or re-run until the host kernel settles. The topology runner already includes retries and nsenter-based fixes.
- If ThingsBoard HTTP never responds but `thingsboard.jar` is running: check container logs `docker logs --tail 200 mn.tb` or `deploy/logs/tb_start.log` for migration errors, out-of-memory, or port conflicts. The new logic will wait an extra `TOPO_TB_EXTRA_WAIT_IF_PROCESS` seconds if the jar is present.

## What to copy to another machine to keep the same experience

1. Clone this repository.
2. Ensure Docker is installed and you can run containers.
3. Build or load the custom images used by the project (if you use the same machine frequently you probably have them built locally):

```sh
# from project root (example targets)
make build-middts    # if there is a Makefile rule to build custom images
make build-tb
make build-sim
```

4. Optionally copy over Docker volumes used for persistent caches/logs if you want the exact same DB/state.
   - `docker save`/`docker load` and `docker volume` export/import aren't automated in this repo — copying the repository plus building local images is the reliable route.

5. Use the same commands above to run the topology; logs and follow scripts will be created under `deploy/logs/`.

## Changes applied during the session (concrete edits)

- `services/topology/topo_qos.py`:
  - Added env-driven TB-first behavior and safer waits.
  - Added `TOPO_TB_EXTRA_WAIT_IF_PROCESS` check and logic to re-run `wait_for_thingsboard` if `thingsboard.jar` is present.
  - Added and used several env vars to tune wait/poll intervals.

- `scripts/prepull_images.sh` (added) — runs docker pulls in parallel and logs results.

- `Makefile` (edited) — `prepull-images` target added; `dev` flow now calls it.

If you want an explicit side-by-side diff of the edits, run:

```sh
git --no-pager diff -- services/topology/topo_qos.py
```

## Next recommended improvements (optional)

- Implement a `TOPO_CORE_FIRST` mode that creates DB + TB + Influx first and waits for HTTP, then concurrently creates middts and simulators (safer, but needs careful ordering).
- Parallelize tc qdisc application for simulators (current code applies sequentially; parallelizing can shorten startup but must avoid contended nsenter operations).
- Add more explicit detection for TB migration progress (parse `mn.tb` logs for known migration completion markers) before starting middts.

## Session raw notes (condensed)

See the `docs/` folder for other documents produced during work (emails, analysis, plots). Key log files are under `deploy/logs/` (topology verbose logs and per-container start logs). The run that motivated TB-first changes produced repeated RTNETLINK warnings and TB HTTP timeouts while `thingsboard.jar` was launching — the change adds an extra wait when that occurs to avoid race-starting middts.

---

If you want, I can also:

- add this file to the repository index (committed) and push a branch with the changes I made during this session (current edits are present in the working tree), or
- create a small `README-portability.md` with a checklist + scripts to copy Docker images/volumes to another host.

Tell me which of these you'd like next and I'll produce it.

## Será tão preciso em outro computador? (portabilidade e caveats)

Curto: provavelmente sim, desde que você reproduza o conjunto de pré-requisitos e imagens; porém há fatores que afetam precisão e determinismo.

- O que garante boa reprodução:
   - Mesmo repositório no mesmo commit.
   - Mesmas imagens Docker (versões/etiquetas) — imagens custom (`tb-node-custom`, `middts-custom`, `iot_simulator`) devem ser construídas ou importadas no novo host.
   - Mesmas variáveis em `.env` (tokens, senhas, organização/bucket do Influx, etc.).
   - Executar como root (ou usar sudo) — Containernet/Mininet precisa de privilégios de rede.

- O que pode quebrar ou alterar medições:
   - Diferenças de kernel (versões / parâmetros de rede), que afetam comportamento de tc/htb/netem e timings de moveIntf.
   - Diferenças de CPU, I/O e carga de máquina que impactam latência (CPU share, turbo, throttling). Experimentos de latência devem ser feitos em máquinas semelhantes para comparar números.
   - Imagens não idênticas (build flags, dependências nativas) — se você não tiver as imagens custom, exporte e importe com `docker save`/`docker load`.
   - Volumes Docker com dados existentes (Postgres/Inﬂux) — um volume pré-populado muda o tempo de bootstrap.

- Recomendações práticas para máxima precisão:
   1. Copie ou construa as imagens custom localmente (`docker build` or `docker load`).
   2. Use as mesmas `.env` e arquivos de configuração (`config/thingsboard-urllc.yml`).
   3. Execute as runs em ambiente com baixa carga e com CPU afins (se possível, a mesma máquina que você já usa).
   4. Use `./scripts/prepull_images.sh` antes de rodar para evitar pulls inesperados que atrapalhem o tempo de startup.

## Principais comandos (rápido, copy/paste)

- Subir topologia (padrão URLLC aqui):

```sh
make topo PROFILE=urllc
```

- Subir topologia em modo TB-first (ThingsBoard antes do middts) e log verbose:

```sh
VERBOSE=1 PRESERVE_STATE=0 TOPO_TB_FIRST=1 \
TOPO_WAIT_RUNNING_SECS=12 TOPO_WAIT_NET_READY_SECS=12 \
TOPO_NET_POLL_INTERVAL=0.12 TOPO_TB_WAIT_SECS=120 \
TOPO_TB_EXTRA_WAIT_IF_PROCESS=120 \
make topo PROFILE=urllc 2>&1 | tee deploy/logs/topo_urllc_tbfirst_verbose.log
```

- Pré-puxar imagens (reduz pulls no run):

```sh
./scripts/prepull_images.sh || true
```

- Rodar ODTE (fluxo experimental completo) com handler para Ctrl+C que salva resultados:

```sh
make odte-full   # já chama o script de graceful shutdown
# ou explicitamente
./scripts/graceful_odte.sh --profile urllc
```

- Ver logs dos containers relevantes:

```sh
docker ps --filter 'name=mn.' --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.RunningFor}}'
docker logs --tail 200 mn.tb
docker logs --tail 200 mn.middts
tail -n 200 deploy/logs/topo_urllc_verbose.log
```

- Exportar imagens custom para mover para outro host:

```sh
# no host A (origem)
docker save -o tb-node-custom.tar tb-node-custom:latest
docker save -o middts-custom.tar middts-custom:latest
docker save -o iot_simulator.tar iot_simulator:latest

# no host B (destino)
docker load -i tb-node-custom.tar
docker load -i middts-custom.tar
docker load -i iot_simulator.tar
```

- Exportar/Importar volumes (dados persistentes) — exemplo com busybox tar:

```sh
# export volume -> tar
docker run --rm -v db_data:/data -v $(pwd):/backup busybox sh -c "cd /data && tar -czf /backup/db_data.tgz ."

# importar no host destino
docker run --rm -v db_data:/data -v $(pwd):/backup busybox sh -c "cd /data && tar -xzf /backup/db_data.tgz --strip-components=0"
```

## Glossário rápido (nomenclatura usada)

- ODTE: o conjunto de experimentos/runner usado para medir latência, deadlines e exportar métricas (este repositório contém scripts e pipelines chamados de "ODTE" para executar e coletar resultados). Pode incluir variações unidirecionais e bidirecionais.
- ODTE bidirecional (ou "Bidirecional ODTE"): teste que gera tráfego em ambas as direções (por exemplo, uplink e downlink) entre simuladores e o middleware/ThingsBoard para avaliar comportamento simétrico e latência em ambas as direções.
- URLLC / eMBB / best_effort: perfis de rede usados para configurar TCLink (delay, bw, loss). URLLC = ultra reliable low latency (baixa latência), eMBB = enhanced mobile broadband (alto débito), best_effort = perfil intermédiario.
- Hot-swap: aplicar um perfil (qdisc / heartbeat / políticas) em tempo de execução sem reiniciar toda topologia; usado para testes comparativos que tentam evitar reinicialização completa.
- TB-first: modo de startup em que ThingsBoard é iniciado e aguardado (HTTP) antes de iniciar o middleware `middts`. Ajuda a evitar races durante migrações/init do TB.
- middts: o middleware que consome telemetria dos simuladores e exporta para Influx/ThingsBoard; no projeto aparece como container `mn.middts`.

Se alguma nomenclatura que eu usei estiver ambígua para você (por exemplo "bidirecional ODTE" se você tiver um significado diferente), diga como você costuma chamar e eu adapto o README/integração para usar a mesma palavra.

---

Se quiser, eu comito esse arquivo e crio um branch `doc/portability` com ele, mais um `README-portability.md` com scripts de export/import de imagens e volumes — quer que eu faça isso agora? 

