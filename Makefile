# Makefile reorganizado para melhor legibilidade e manutenção
# ==========================================================

# === VARIÁVEIS DE IMAGEM E CAMINHO ===
MIDDTS_IMAGE = middts:latest
MIDDTS_CUSTOM_IMAGE = middts-custom:latest
IOT_SIM_IMAGE = iot_simulator:latest
TB_IMAGE = tb-node-custom
PG_IMAGE = postgres
NEO4J_IMAGE = neo4j-tools:latest
PARSER_IMAGE = parserwebapi-tools:latest
INFLUX_IMAGE = influxdb-tools:latest

DOCKER_PATH = dockerfiles
# === SETUP E LIMPEZA ===
.PHONY: setup clean clean-containers clean-controllers reset-db reset-db-tb reset-db-middts reset-db-influx reset-db-neo4j reset-db-sims reset-tb

setup:
	@echo "[Setup] Executar ./scripts/setup.sh"
	./scripts/setup.sh

clean:
	@echo "[🧼] Limpando ambiente Mininet/Containernet e containers órfãos"
	@echo "[🛑] Parando controladores OpenFlow em execução..."
	-sudo pkill -f "controller.*6653" || echo "[INFO] Nenhum controlador na porta 6653 encontrado"
	-sudo fuser -k 6653/tcp || echo "[INFO] Nenhum processo usando porta 6653"
	-sudo mn -c || echo "[WARN] mn -c falhou"
	-docker ps -a --filter "name=mn." -q | xargs -r docker rm -f
	-docker network ls --filter "name=mn." -q | xargs -r docker network rm
	-docker volume ls --filter "name=mn." -q | xargs -r docker volume rm
	@echo "[🧯] Limpando interfaces de rede restantes"
	-ip -o link show | awk -F': ' '{print $$2}' | grep -E '^(mn-|sim_|s[0-9]+-eth[0-9]+)' | xargs -r -n1 sudo ip link delete
	@echo "[🧯] Limpando interfaces veth Mininet/Containernet"
	@ip -o link show | awk -F': ' '{print $$2}' | cut -d'@' -f1 | grep -E '^(mn-|sim_|s[0-9]+-eth[0-9]+)' | sort | uniq | xargs -r -n1 sudo ip link delete || true

clean-containers:
	docker ps -a --filter "name=mn." -q | xargs -r docker rm -f

clean-controllers:
	@echo "[🛑] Parando controladores OpenFlow na porta 6653"
	-sudo pkill -f "controller.*6653" || echo "[INFO] Nenhum controlador encontrado"
	-sudo fuser -k 6653/tcp || echo "[INFO] Porta 6653 já estava livre"
	@echo "[✅] Limpeza de controladores concluída"

## High level reset: calls focused reset targets so operator can compose actions
reset-db: reset-db-tb reset-db-middts reset-db-influx reset-db-neo4j reset-db-sims
	@echo "[reset-db] Reset completo executado (best-effort)."

# Reset ThingsBoard volumes (db + assets + logs)
reset-db-tb:
	@echo "[reset-db-tb] Removendo volumes do ThingsBoard (db_data, tb_assets, tb_logs)..."
	-@docker volume rm db_data tb_assets tb_logs || true
	@echo "[reset-db-tb] Volumes do ThingsBoard removidos (se existiam)."

# Reset MidDiTS related volumes
reset-db-middts:
	@echo "[reset-db-middts] Removendo volumes relacionados ao MidDiTS"
	-@docker volume ls --format '{{.Name}}' | grep -E 'middts|middleware' | xargs -r -n1 docker volume rm || true
	@echo "[reset-db-middts] Concluído (best-effort)."

# Reset InfluxDB volumes
reset-db-influx:
	@echo "[reset-db-influx] Removendo volumes relacionados ao InfluxDB"
	-@docker volume rm influx_data influx_logs || true
	-@docker volume ls --format '{{.Name}}' | grep -E 'influx|influxdb' | xargs -r -n1 docker volume rm || true
	@echo "[reset-db-influx] Concluído (best-effort)."

# Reset Neo4j volumes
reset-db-neo4j:
	@echo "[reset-db-neo4j] Removendo volumes relacionados ao Neo4j"
	-@docker volume rm neo4j_data neo4j_logs || true
	-@docker volume ls --format '{{.Name}}' | grep -E 'neo4j' | xargs -r -n1 docker volume rm || true
	@echo "[reset-db-neo4j] Concluído (best-effort)."

# Reset simulator host files and simulator volumes
reset-db-sims:
	@echo "[reset-db-sims] Removendo volumes e dados locais dos simuladores"
	-@docker volume ls --format '{{.Name}}' | grep -E 'parser|sim_|simulator' | xargs -r -n1 docker volume rm || true
	-@find services/iot_simulator -maxdepth 1 -type f -name 'db.sqlite3' -exec rm -f {} \; || true
	@mkdir -p deploy || true
	@touch deploy/.reset_sim_db
	@echo "[reset-db-sims] Simulators: host DB removido; deploy/.reset_sim_db criado."

reset-tb:
	@echo "Removendo volumes do ThingsBoard (db_data, tb_assets, tb_logs)..."
	-docker volume rm db_data tb_assets tb_logs
	@echo "Volumes removidos. O banco e dados do TB serão recriados limpos no próximo start."

# === PRUNE VOLUMES POR SERVIÇO ===
.PHONY: prune-vol-influx prune-vol-neo4j prune-vol-middts prune-vol-tb prune-vol-simulators prune-vol-all

prune-vol-influx:
	@echo "[🗑️] Removendo volumes relacionados ao InfluxDB (nomes contendo 'influx' ou 'influxdb')"
	-@docker volume ls --format '{{.Name}}' | grep -E 'influx|influxdb' | xargs -r -n1 docker volume rm || true
	@echo "Prune InfluxDB: concluído"

prune-vol-neo4j:
	@echo "[🗑️] Removendo volumes relacionados ao Neo4j (nomes contendo 'neo4j')"
	-@docker volume ls --format '{{.Name}}' | grep -E 'neo4j' | xargs -r -n1 docker volume rm || true
	@echo "Prune Neo4j: concluído"

prune-vol-middts:
	@echo "[🗑️] Removendo volumes relacionados ao MidDiTS (nomes contendo 'middts' ou 'middleware')"
	-@docker volume ls --format '{{.Name}}' | grep -E 'middts|middleware' | xargs -r -n1 docker volume rm || true
	@echo "Prune MidDiTS: concluído"

prune-vol-tb:
	@echo "[🗑️] Removendo volumes do ThingsBoard (db_data, tb_assets, tb_logs)"
	-@docker volume rm db_data tb_assets tb_logs || true
	@echo "Prune ThingsBoard: concluído"

prune-vol-simulators:
	@echo "[🗑️] Removendo volumes relacionados aos simuladores (nomes contendo 'sim_' ou 'simulator')"
	-@docker volume ls --format '{{.Name}}' | grep -E 'sim_|simulator' | xargs -r -n1 docker volume rm || true
	@echo "Prune Simulators: concluído"

prune-vol-all: prune-vol-influx prune-vol-neo4j prune-vol-middts prune-vol-tb prune-vol-simulators
	@echo "[🗑️] Pruning concluído para todos os serviços conhecidos"

# === LOG ROTATION HELPERS ===
.PHONY: install-logrotate run-logrotate truncate-logs

install-logrotate:
	@echo "[info] Use the maintenance scripts in scripts/maintenance to manage host logrotate"
	@sh scripts/maintenance/install-logrotate.sh

run-logrotate:
	@echo "[info] Use the maintenance scripts in scripts/maintenance to run logrotate"
	@sh scripts/maintenance/run-logrotate.sh

truncate-logs:
	@echo "[info] Use the maintenance scripts in scripts/maintenance to truncate logs"
	@sh scripts/maintenance/truncate-logs.sh

# === BUILD DE IMAGENS ===
.PHONY: build-images rebuild-images

build-images:
	@echo "[🐳] Construindo imagens Docker personalizadas"
	docker build -t $(MIDDTS_CUSTOM_IMAGE) -f $(DOCKER_PATH)/Dockerfile.middts services/
	docker build -t $(IOT_SIM_IMAGE) -f $(DOCKER_PATH)/Dockerfile.iot_simulator services/
	docker build -t $(TB_IMAGE) -f $(DOCKER_PATH)/Dockerfile.tb services/
	docker build -t $(PG_IMAGE) -f $(DOCKER_PATH)/Dockerfile.pg13 services/
	docker build -t $(NEO4J_IMAGE) -f $(DOCKER_PATH)/Dockerfile.neo4j services/
	docker build -t $(PARSER_IMAGE) -f $(DOCKER_PATH)/Dockerfile.parser services/
	docker build -t $(INFLUX_IMAGE) -f $(DOCKER_PATH)/Dockerfile.influx services/
	

rebuild-images:
	@echo "[🐳] Rebuilding ALL images from scratch (pulling base images, no cache)"
	# Use --pull to get latest base layers and --no-cache to force full rebuild
	docker build --pull --no-cache -t $(MIDDTS_CUSTOM_IMAGE) -f $(DOCKER_PATH)/Dockerfile.middts services/
	docker build --pull --no-cache -t $(IOT_SIM_IMAGE) -f $(DOCKER_PATH)/Dockerfile.iot_simulator services/
	docker build --pull --no-cache -t $(TB_IMAGE) -f $(DOCKER_PATH)/Dockerfile.tb services/
	docker build --pull --no-cache -t $(PG_IMAGE) -f $(DOCKER_PATH)/Dockerfile.pg13 services/
	docker build --pull --no-cache -t $(NEO4J_IMAGE) -f $(DOCKER_PATH)/Dockerfile.neo4j services/
	docker build --pull --no-cache -t $(PARSER_IMAGE) -f $(DOCKER_PATH)/Dockerfile.parser services/
	docker build --pull --no-cache -t $(INFLUX_IMAGE) -f $(DOCKER_PATH)/Dockerfile.influx services/
	@echo "[🐳] Rebuild completo finalizado. Certifique-se de recriar os containers para usar as novas imagens."

# === USABILITY ALIASES E WORKFLOWS ===
# Comandos mais intuitivos para o dia-a-dia: imagens, containers e um fluxo dev rápido
.PHONY: help images-build containers-recreate dev ps logs-sim

help:
	@echo "Uso: make <target>"
	@echo "Grupos principais:"
	@echo "  images-build        -> Reconstruir imagens (igual a make build-images)"
	@echo "  containers-recreate -> Remove um container mn.<SERVICE> (use SERVICE=tb)"
	@echo "  dev                 -> Fluxo rápido (remove containers, build images, executa topo)"
	@echo "  topo                -> Inicia a topologia (containernet) com perfil test05_best_performance por padrão"
	@echo "  quick-start         -> Inicia topologia com perfil Test #5 (melhor performance)"
	@echo "  odte                -> Executa experimento ODTE e gera relatórios (PROFILE=urllc DURATION=1800)"
	@echo "  odte-full           -> Workflow completo com graceful shutdown (Ctrl+C salva dados)"
	@echo "  analyze-latest      -> Análise inteligente do teste URLLC mais recente"
	@echo "  intelligent-analysis -> Análise inteligente de teste específico (TEST_DIR=<path>)"
	@echo "  compare-urllc       -> Comparação evolutiva de todos os testes URLLC"
	@echo "  compare-profiles    -> Comparação URLLC vs eMBB vs best_effort"
	@echo "  dashboard           -> Dashboard executivo do status URLLC atual"
	@echo ""
	@echo "=== PERFIS DE CONFIGURAÇÃO ==="
	@echo "  test05-best         -> Topologia URLLC + perfil Test #5 (melhor performance)"
	@echo "  rpc-ultra           -> Topologia URLLC + perfil RPC ultra-agressivo"
	@echo "  network-opt         -> Topologia URLLC + perfil otimizado para conectividade"
	@echo "  baseline            -> Topologia URLLC + perfil padrão (baseline)"
	@echo "  apply-profile       -> Aplica perfil via hot-swap: CONFIG_PROFILE=reduced_load"
	@echo "  apply-profile-restart -> Aplica perfil com restart seguro do ThingsBoard"
	@echo "  quick-restore       -> Restaura perfil Test #5 rapidamente"
	@echo ""
	@echo "=== USO AVANÇADO ==="
	@echo "  make topo CONFIG_PROFILE=extreme_performance  -> Topologia com perfil específico"
	@echo "  make apply-profile CONFIG_PROFILE=ultra_aggressive  -> Aplicar perfil sem restart"
	@echo ""
	@echo "=== PERFIS DISPONÍVEIS ==="
	@echo "  • test05_best_performance (padrão) - Test #5: melhor S2M/M2S, ODTE 0.88"
	@echo "  • rpc_ultra_aggressive            - RPC 300ms, HTTP ultra-otimizado"
	@echo "  • network_optimized               - Foco em conectividade e estabilidade"
	@echo "  • baseline_default                - Configuração padrão ThingsBoard"
	@echo ""
	@echo "Outros comandos:"
	@echo "  check-urllc         -> Verifica status das otimizações URLLC"
	@echo "  check-topology      -> Status geral da topologia"
	@echo "  check-tc            -> Configurações de Traffic Control"
	@echo "  summary             -> Resumo das otimizações aplicadas"
	@echo "  apply-urllc         -> Aplica otimizações URLLC manualmente"
	@echo "  apply-urllc-yaml    -> Aplica configurações URLLC via YAML (rebuild TB)"
	@echo "  organize-reports    -> Organiza relatórios por timestamp"
	@echo "  optimize-latency    -> Aplica otimizações para baixa latência (<200ms)"
	@echo "  analyze             -> Análise de texto dos relatórios ODTE (REPORTS_DIR=outputs/results/generated_reports)"
	@echo "  plots               -> Gera gráficos dos relatórios ODTE (REPORTS_DIR=outputs/results/generated_reports)"
	@echo "  clean               -> Limpeza completa (rede/veth/containers)"
	@echo "  clean-controllers   -> Para controladores OpenFlow na porta 6653"
	@echo "  check               -> Health checks dos containers (use make check)"

# Aliases que delegam para os targets já existentes para manter compatibilidade
images-build:
	@$(MAKE) build-images


containers-recreate:
	@if [ -z "$(SERVICE)" ]; then echo "[USO] make containers-recreate SERVICE=tb"; exit 1; fi
	@$(MAKE) recreate-container SERVICE=$(SERVICE)

# Fluxo diário usado por você: remove apenas containers, rebuild de imagens e sobe a topologia
dev:
	@echo "[DEV] Fluxo: clean-containers -> build-images -> topo"
	@$(MAKE) clean-containers
	@$(MAKE) build-images
	@$(MAKE) topo

# Conveniência: listar containers filtrados pelo prefixo mn.
ps:
	@docker ps --filter "name=mn." --format 'table {{.Names}}	{{.Status}}	{{.Image}}'

# Tail rápido dos logs de um simulador: make logs-sim SIM=sim_001
logs-sim:
	@tail -n 200 -f services/iot_simulator/logs/mn.$(SIM)_start.log || tail -n 200 -f deploy/logs/$(SIM)_start.log || true

# Convenience targets to run the parser as an external Docker container
.PHONY: run-parser stop-parser

run-parser:
	@echo "[run-parser] Starting external parser container (detached) using image $(PARSER_IMAGE)"
	-@docker run -d --name parser -p 8082:8080 -p 8083:8081 --restart unless-stopped $(PARSER_IMAGE) || echo "[WARN] parser already running or failed to start"
	@echo "[run-parser] If you need a different host port, override ports or start the container manually."

stop-parser:
	@echo "[stop-parser] Stopping and removing external parser container 'parser'"
	-@docker rm -f parser || true
	@echo "[stop-parser] Done."
# === TOPOLOGIA E VISUALIZAÇÃO ===
.PHONY: topo topo-screen draw topo-rpc-ultra topo-rpc-extreme topo-rpc-reduced_loads

topo:
	@echo "[📡] Executando topologia com Containernet"
	@echo "[🔍] Verificando controladores em execução na porta 6653..."
	@if sudo -n netstat -tlnp 2>/dev/null | grep -q ":6653 "; then \
		echo "[⚠️] Controlador detectado na porta 6653. Parando..."; \
		sudo -n pkill -f "controller.*6653" || true; \
		sudo -n fuser -k 6653/tcp || true; \
		sleep 2; \
	else \
		echo "[✅] Porta 6653 livre"; \
	fi
	# Use the helper script to centralize environment handling and defaults.
	# Default behavior preserves state (PRESERVE_STATE=1) unless overridden by caller.
	# Pass PROFILE (if provided) into the topology runner as TOPO_PROFILE env var
	@echo "[topo] PROFILE=$(PROFILE) CONFIG_PROFILE=$(CONFIG_PROFILE)"
	@# Apply CONFIG_PROFILE with default to reduced_load
	@config_profile="$${CONFIG_PROFILE:-reduced_load}"; \
	echo "[🎯] Aplicando perfil de configuração: $$config_profile"; \
	if ./scripts/filters/apply_profile_hotswap.sh "$$config_profile"; then \
		echo "✅ Perfil aplicado via hot-swap"; \
	else \
		echo "⚠️ Hot-swap falhou, aplicando via método tradicional..."; \
		./scripts/apply_profile.sh "$$config_profile"; \
	fi
	@# Default PROFILE to 'urllc' when not provided. If the operator passed
	@# PROFILE on the make command line (e.g. `make topo PROFILE=eMBB`), do not
	@# let a repository `.env` file override that value. Source .env only when
	@# PROFILE is empty.
	# If the make variable PROFILE was passed on the command line, expand it
	# into the shell so the recipe sees it. Otherwise try sourcing .env and
	# fallback to the hardcoded default 'urllc'.
	@if [ -n "$(PROFILE)" ]; then \
		profile="$(PROFILE)"; \
	else \
		if [ -f $(CURDIR)/.env ]; then . $(CURDIR)/.env; fi; \
		profile="${PROFILE:-urllc}"; \
	fi; \
	if [ -n "$(DURATION)" ]; then \
		duration="$(DURATION)"; \
	else \
		duration=""; \
	fi; \
	echo "[topo] PROFILE=$$profile DURATION=$$duration"; \
	sh scripts/run_topo.sh "$$profile" "$$duration"

topo-rpc-ultra:
	@$(MAKE) topo PROFILE=urllc CONFIG_PROFILE=ultra_aggressive

topo-rpc-extreme:
	@$(MAKE) topo PROFILE=urllc CONFIG_PROFILE=extreme_performance

topo-rpc-reduced_loads:
	@$(MAKE) topo PROFILE=urllc CONFIG_PROFILE=reduced_loads

.PHONY: urllc best_effort eMBB test05-best rpc-ultra reduced-load network-opt baseline apply-profile apply-profile-restart

# Convenience targets: run topo with a predefined profile
urllc:
	@$(MAKE) topo PROFILE=urllc

best_effort:
	@$(MAKE) topo PROFILE=best_effort

eMBB:
	@$(MAKE) topo PROFILE=eMBB

# === CONFIG PROFILE TARGETS ===
# Convenience targets: run topo with predefined configuration profiles
test05-best:
	@$(MAKE) topo PROFILE=urllc CONFIG_PROFILE=test05_best_performance

rpc-ultra:
	@$(MAKE) topo PROFILE=urllc CONFIG_PROFILE=rpc_ultra_aggressive

reduced-load:
	@$(MAKE) topo PROFILE=urllc CONFIG_PROFILE=reduced_load

network-opt:
	@$(MAKE) topo PROFILE=urllc CONFIG_PROFILE=network_optimized

baseline:
	@$(MAKE) topo PROFILE=urllc CONFIG_PROFILE=baseline_default

# Apply configuration profile via hot-swap (no restart)
apply-profile:
	@if [ -z "$(CONFIG_PROFILE)" ]; then \
		echo "❌ Erro: Use 'make apply-profile CONFIG_PROFILE=<profile_name>'"; \
		echo "📁 Perfis disponíveis: test05_best_performance, rpc_ultra_aggressive, network_optimized, baseline_default"; \
		exit 1; \
	fi
	@./scripts/filters/apply_profile_hotswap.sh "$(CONFIG_PROFILE)"

# Apply configuration profile WITH safe ThingsBoard restart
apply-profile-restart:
	@if [ -z "$(CONFIG_PROFILE)" ]; then \
		echo "❌ Erro: Use 'make apply-profile-restart CONFIG_PROFILE=<profile_name>'"; \
		echo "📁 Perfis disponíveis: test05_best_performance, rpc_ultra_aggressive, network_optimized, baseline_default"; \
		exit 1; \
	fi
	@./scripts/filters/apply_profile_safe_restart.sh "$(CONFIG_PROFILE)"

# Quick start with best performance profile (default)
quick-start:
	@echo "🚀 Iniciando topologia com perfil Test #5 (melhor performance)..."
	@$(MAKE) topo CONFIG_PROFILE=test05_best_performance

# Quick restart with Test #5 (best known configuration)
quick-restore:
	@echo "🚀 Aplicando Test #5 (melhor configuração conhecida)..."
	@./scripts/filters/apply_profile_hotswap.sh test05_best_performance

.PHONY: cenario_test

# Usage:
#  make cenario_test PROFILE=urllc DURATION=1800
#  PROFILE defaults to best_effort, DURATION defaults to 1800 (30m)
cenario_test:
	@echo "[make] running scenario test (PROFILE=${PROFILE}, DURATION=${DURATION})"
	@if [ -f .env ]; then . .env; fi; \
	profile="${PROFILE:-best_effort}"; \
	duration="${DURATION:-1800}"; \
	script="./scripts/cenario_test.sh"; \
	if [ ! -x "$$script" ]; then chmod +x "$$script"; fi; \
	"$$script" "$$profile" "$$duration"

.PHONY: odte
# Run topology, execute the scenario and collect ODTE-related reports
# Usage: make odte PROFILE=urllc DURATION=1800
odte:
	@profile="$${PROFILE:-urllc}"; duration="$${DURATION:-1800}"; \
	echo "[📡] Executando topologia e cenário ODTE..."; \
	echo "[⏱️] Duração: $${duration}s | Perfil: $$profile"; \
	SCHEDULE_FILE=/dev/null bash scripts/slice/apply_slice.sh "$$profile" --execute-scenario "$$duration" 2>/dev/null || echo "[⚠️] Possíveis warnings durante execução (normal)"


# Stop topology helper: best-effort terminate process and cleanup netns
.PHONY: stop-topo
stop-topo:
	@echo "[🛑] Stopping topology (best-effort) and cleaning up network artifacts..."; \
	-sudo pkill -f "topo_qos.py" || echo "[INFO] topo process not found"; \
	-sudo pkill -f "containernet" || true; \
	# run mn -c cleanup (if mininet/containernet left state)
	-sudo mn -c || true; \
	# remove docker containers/networks with mn. prefix
	-docker ps -a --filter "name=mn." -q | xargs -r docker rm -f || true; \
	-docker network ls --filter "name=mn." -q | xargs -r docker network rm || true; \
	@echo "[🧹] Topology stop attempted. If processes remain, inspect with 'ps aux | grep topo' or 'docker ps'."


.PHONY: plots
# Generate comprehensive visualization plots from the latest generated reports
# Usage: make plots [REPORTS_DIR=results/generated_reports]
plots:
	@echo "[docs] Gerando seção de artigo (results/article/sections/evaluation.tex) a partir dos relatórios mais recentes"
	@python3 scripts/reports/render_article.py || (echo "[WARN] render failed; ensure requirements in local.txt are installed"; exit 1)

	@reports_dir="$${REPORTS_DIR:-outputs/results/generated_reports}"; \
	if [ ! -x scripts/reports/run_plots_for_reports.sh ]; then chmod +x scripts/reports/run_plots_for_reports.sh; fi; \
	scripts/reports/run_plots_for_reports.sh "$$reports_dir"

.PHONY: analyze
# Perform comprehensive text-based analysis of ODTE reports without visualization dependencies
# Usage: make analyze [REPORTS_DIR=results/generated_reports]
analyze:
	@reports_dir="$${REPORTS_DIR:-outputs/results/generated_reports}"; \
	echo "[🔍] Analisando relatórios em $$reports_dir..."; \
	if [ ! -d "$$reports_dir" ]; then \
		echo "❌ Diretório não encontrado: $$reports_dir"; \
		exit 1; \
	fi; \
	python3 scripts/reports/report_generators/quick_analysis.py "$$reports_dir" 2>/dev/null && \
	echo "✅ Análise concluída" || echo "❌ Erro na análise"

.PHONY: odte-monitored
# ODTE with real-time bottleneck monitoring during test execution
# Usage: make odte-monitored [PROFILE=urllc] [DURATION=120]
odte-monitored:
	@profile="$${PROFILE:-urllc}"; duration="$${DURATION:-120}"; \
	echo "[🔍] Executando ODTE com monitoramento de gargalos..."; \
	echo "[⏱️] Duração: $${duration}s | Perfil: $$profile"; \
	PROFILE=$$profile bash scripts/show_current_config.sh; \
	echo "[1/3] Iniciando monitoramento em background..."; \
	bash scripts/monitor/monitor_during_test.sh "$$duration" & \
	MONITOR_PID=$$!; \
	echo "[2/3] Executando teste ODTE..."; \
	$(MAKE) odte PROFILE=$$profile DURATION=$$duration; \
	echo "[3/3] Aguardando conclusão do monitoramento..."; \
	wait $$MONITOR_PID; \
	echo "✅ Teste ODTE com monitoramento concluído!"

# phony: only keep odte-full
.PHONY: odte-full
# Complete ODTE workflow: run experiment, generate analysis and plots with graceful shutdown
# Usage: make odte-full [PROFILE=auto|urllc|embb|best_effort] [DURATION=1800] [REPORTS_DIR=auto]
odte-full:
	@echo "[🚀] Starting complete ODTE workflow with graceful shutdown..."; \
	profile="$${PROFILE:-auto}"; duration="$${DURATION:-1800}"; \
	chmod +x scripts/graceful_odte.sh; \
	./scripts/graceful_odte.sh "$$profile" "$$duration"; \
	# After the ODTE run, invoke post-processing script to find latest test and generate reports
	if [ ! -x scripts/reports/postprocess_latest_test.sh ]; then chmod +x scripts/reports/postprocess_latest_test.sh; fi; \
	scripts/reports/postprocess_latest_test.sh

# === SCRIPTS URLLC E OTIMIZAÇÃO ===
.PHONY: check-urllc check-topology check-tc summary organize-reports apply-urllc
# Check URLLC optimizations status
check-urllc:
	@echo "[🔍] Verificando status das otimizações URLLC..."
	@bash scripts/check_urllc_status.sh

# Check topology general status  
check-topology:
	@echo "[🏗️] Verificando status geral da topologia..."
	@bash scripts/check_topology.sh

# Check Traffic Control configurations
check-tc:
	@echo "[🌐] Verificando configurações de Traffic Control..."
	@bash scripts/check_tc.sh

# Generate optimization summary report
summary:
	@echo "[📋] Gerando resumo das otimizações..."
	@bash scripts/OPTIMIZATION_SUMMARY.sh

# Organize test reports by timestamp
organize-reports:
	@echo "[📁] Organizando relatórios de teste..."
	@bash scripts/reports/organize_reports.sh

# Apply URLLC optimizations manually (usually done automatically)
apply-urllc:
	@echo "[⚡] Aplicando otimizações URLLC manualmente..."
	@bash scripts/apply_urllc_minimal.sh

# Apply URLLC optimizations via YAML configuration
apply-urllc-yaml:
	@echo "[🎯] Aplicando configurações URLLC via YAML..."
	@bash scripts/apply_urllc_yaml.sh

.PHONY: optimize-latency
# Apply balanced optimizations for low latency communication (<200ms target)
optimize-latency:
	@echo "[🚀] Applying balanced low latency optimizations..."; \
	bash scripts/optimize_balanced_latency.sh || { \
		echo "❌ Optimization script failed"; exit 1; \
	}; \
	echo "✅ Balanced low latency optimizations applied successfully!"

.PHONY: check-link
# Quick diagnostic to inspect tc qdisc and IPs for containernet containers
check-link:
	@echo "[check-link] running scripts/check_tc.sh (requires docker)";
	@sh scripts/check_tc.sh


topo-screen:
	@echo "[📡] Executando topologia com Containernet em screen"
	# Start the topology inside a detached screen session. Honor PRESERVE_STATE if provided,
	# default to 1 inside the screen command. Forward PROFILE (make var) to the run_topo.sh script.
	@screen -S containernet -dm sh -c 'if [ -z "$$PRESERVE_STATE" ]; then PRESERVE_STATE=1; fi; export PRESERVE_STATE; sh scripts/run_topo.sh "$(PROFILE)"'
	@echo "Use: screen -r containernet  para acessar o CLI do Containernet"


# === PREPARE / CLEAN BOOT FOR TOPOLOGY ===
.PHONY: ensure-clean-boot
ensure-clean-boot:
	@echo "[🔁] ensure-clean-boot: verificação de volumes InfluxDB/Neo4j (remover se existirem)"
	@SIM_ENV="$$(pwd)/.env"; \
	if [ ! -f "$$SIM_ENV" ]; then SIM_ENV="$$(pwd)/services/middleware-dt/.env"; fi; \
	if [ -f "$$SIM_ENV" ]; then . "$$SIM_ENV"; fi; \
	# Allow operator to preserve state by passing PRESERVE_STATE=1 to make
	if [ "$$PRESERVE_STATE" = "1" ]; then \
		echo "[ℹ️] PRESERVE_STATE=1 set, skipping automatic volume removal."; \
		exit 0; \
	fi; \
	# Note: ensure-clean-boot no longer auto-deletes InfluxDB/Neo4j data volumes.
	# Use `make reset-db-influx` or `make reset-db-neo4j` to explicitly remove volumes.
	if docker volume ls --format '{{.Name}}' | grep -E 'influx|influxdb' >/dev/null 2>&1; then \
		echo "[⚠️] Influx volumes detected. Run 'make reset-db-influx' to remove them if you really want a fresh bootstrap."; \
	else \
		echo "[🔎] No Influx volumes found."; \
	fi; \
	if docker volume ls --format '{{.Name}}' | grep -E 'neo4j' >/dev/null 2>&1; then \
		echo "[⚠️] Neo4j volumes detected. Run 'make reset-db-neo4j' to remove them if you really want a fresh bootstrap."; \
	else \
		echo "[🔎] No Neo4j volumes found."; \
	fi; \
	echo "[🔁] ensure-clean-boot: concluído. No volumes were removed."

draw:
	@echo "[🖼️ ] Gerando visualização da topologia"
	bash -c 'python3 services/topology/draw_topology.py'

# === VERIFICAÇÕES DE STATUS E REDE ===
.PHONY: check check-tb check-middts check-db check-influxdb check-neo4j check-parser check-simulator check-simulators check-network check-tb-internal

check:
	@echo "[🔎] Verificação rápida dos serviços (resumo em tabela)"
	@printf "%-12s | %-15s | %-20s | %-7s | %-40s | %s\n" "serviço" "ip" "porta exposta" "rodando" "log inicializacao" "outras"
	@printf "%.0s-" {1..120}; echo
	@services="tb middts db influxdb neo4j parser"; \
	for s in $$services; do \
		c=mn.$$s; \
		ip=$$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $$c 2>/dev/null || echo '-'); \
		ports=$$(docker port $$c 2>/dev/null || echo '-'); \
		running=$$(docker ps --filter "name=$$c" --filter "status=running" -q | wc -l | tr -d ' '); \
		if [ "$$running" -gt 0 ]; then r="yes"; else r="no"; fi; \
		case $$s in \
			tb) log="deploy/logs/tb_start.log" ;; \
			middts) log="deploy/logs/middts_start.log" ;; \
			db) log="deploy/logs/db_start.log" ;; \
			influxdb) log="deploy/logs/influx_start.log" ;; \
			neo4j) log="deploy/logs/neo4j_start.log" ;; \
			parser) log="deploy/logs/parser_start.log" ;; \
		esac; \
		printf "%-12s | %-15s | %-20s | %-7s | %-40s | %s\n" $$s $$ip "$$ports" $$r $$log ""; \
	done
	@# simuladores
	@for i in 1 2 3 4 5; do \
		name=`printf 'sim_%03d' $$i`; \
		c=mn.$$name; \
		ip=$$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $$c 2>/dev/null || echo '-'); \
		ports=$$(docker port $$c 2>/dev/null || echo '-'); \
		running=$$(docker ps --filter "name=$$c" --filter "status=running" -q | wc -l | tr -d ' '); \
		if [ "$$running" -gt 0 ]; then r="yes"; else r="no"; fi; \
		log="services/iot_simulator/logs/$$name_start.log"; \
		printf "%-12s | %-15s | %-20s | %-7s | %-40s | %s\n" $$name $$ip "$$ports" $$r $$log ""; \
	done
	@echo "\nPara detalhes em tempo real use: tail -f deploy/logs/<servico>_start.log ou VERBOSE=1 make topo"

# Serviços principais
check-tb:
	@echo "[🔎] Verificando container tb"
	docker ps --format '{{.Names}}' | grep -q '^mn.tb$$' && echo "✅ Container mn.tb está rodando" || echo "❌ Container mn.tb não está rodando"
	@echo "[🔎] Verificando serviço ThingsBoard (porta 8080)"
	docker exec -it mn.tb bash -c 'nc -z -w 2 127.0.0.1 8080' && echo "✅ ThingsBoard ouvindo na porta 8080" || echo "❌ ThingsBoard não está ouvindo na porta 8080"
	@echo "[🔎] Testando comunicação com o banco (db)"
	docker exec -it mn.tb ping -c 2 10.0.0.10 || echo "[ERRO] tb não pinga db (10.0.0.10)"
	docker exec -it mn.tb bash -c 'nc -vz -w 2 10.0.0.10 5432' || echo "[ERRO] tb não conecta TCP 5432 em db (10.0.0.10)"

check-middts:
	@echo "[🔎] Verificando container middts"
	docker ps --format '{{.Names}}' | grep -q '^mn.middts$$' && echo "✅ Container mn.middts está rodando" || echo "❌ Container mn.middts não está rodando"
	@echo "[🔎] Verificando serviço MidDiTS (porta 8000)"
	docker exec -it mn.middts bash -c 'nc -z -w 2 127.0.0.1 8000' && echo "✅ MidDiTS ouvindo na porta 8000" || echo "❌ MidDiTS não está ouvindo na porta 8000"
	@echo "[🔎] Testando comunicação com o banco (db)"
	docker exec -it mn.middts ping -c 2 10.0.1.10 || echo "[ERRO] middts não pinga db"
	docker exec -it mn.middts bash -c 'nc -vz -w 2 10.0.1.10 5432' || echo "[ERRO] middts não conecta TCP 5432 em db"
	@echo "[🔎] Testando comunicação com InfluxDB"
	docker exec -it mn.middts ping -c 2 10.0.1.20 || echo "[ERRO] middts não pinga influxdb"
	docker exec -it mn.middts bash -c 'nc -vz -w 2 10.0.1.20 8086' || echo "[ERRO] middts não conecta TCP 8086 em influxdb"
	@echo "[🔎] Testando comunicação com Neo4j"
	docker exec -it mn.middts ping -c 2 10.0.1.30 || echo "[ERRO] middts não pinga neo4j"
	docker exec -it mn.middts bash -c 'nc -vz -w 2 10.0.1.30 7474' || echo "[ERRO] middts não conecta TCP 7474 em neo4j"

check-db:
	@echo "[🔎] Verificando container db"
	docker ps --format '{{.Names}}' | grep -q '^mn.db$$' && echo "✅ Container mn.db está rodando" || echo "❌ Container mn.db não está rodando"
	@echo "[🔎] Verificando serviço PostgreSQL (porta 5432)"
	docker exec -it mn.db bash -c 'nc -z -w 2 127.0.0.1 5432' && echo "✅ PostgreSQL ouvindo na porta 5432" || echo "❌ PostgreSQL não está ouvindo na porta 5432"
	@echo "[🔎] Testando comunicação com tb (rede local 10.0.0.2 — interface relevante para ThingsBoard)"
	docker exec -it mn.db ping -c 2 10.0.0.2 || echo "[ERRO] db não pinga tb (10.0.0.2)"
	docker exec -it mn.db bash -c 'nc -vz -w 2 10.0.0.2 8080' || echo "[ERRO] db não conecta TCP 8080 em tb (10.0.0.2)"
	@echo "[🔎] Testando comunicação com tb (gerenciamento 10.0.0.2 — interface correta segundo a topologia)"
	docker exec -it mn.db ping -c 2 10.0.0.2 || echo "[ERRO] db não pinga tb (10.0.0.2 — deveria funcionar)"
	docker exec -it mn.db bash -c 'nc -vz -w 2 10.0.0.2 8080' || echo "[ERRO] db não conecta TCP 8080 em tb (10.0.0.2 — deveria funcionar)"

check-influxdb:
	@echo "[🔎] Verificando container influxdb"
	docker ps --format '{{.Names}}' | grep -q '^mn.influxdb$$' && echo "✅ Container mn.influxdb está rodando" || echo "❌ Container mn.influxdb não está rodando"
	@echo "[🔎] Verificando serviço InfluxDB (porta 8086 — esperado em 127.0.0.1 e 10.10.2.20, conforme topologia)"
	docker exec -it mn.influxdb bash -c 'nc -z -w 2 127.0.0.1 8086' && echo "✅ InfluxDB ouvindo na porta 8086 (localhost)" || echo "❌ InfluxDB não está ouvindo na porta 8086 (localhost)"
	docker exec -it mn.influxdb bash -c 'nc -z -w 2 10.10.2.20 8086' && echo "✅ InfluxDB ouvindo na porta 8086 (10.10.2.20)" || echo "❌ InfluxDB não está ouvindo na porta 8086 (10.10.2.20)"
	@echo "[🔎] Testando comunicação com middts (10.0.1.2 — interface relevante para MidDiTS)"
	docker exec -it mn.influxdb ping -c 2 10.0.1.2 || echo "[ERRO] influxdb não pinga middts (10.0.1.2 — deveria funcionar)"
	docker exec -it mn.influxdb bash -c 'nc -vz -w 2 10.0.1.2 8000' || echo "[ERRO] influxdb não conecta TCP 8000 em middts (10.0.1.2 — deveria funcionar)"
	@echo "[DEBUG] Interfaces e rotas do influxdb para diagnóstico:"
	docker exec -it mn.influxdb ip addr
	docker exec -it mn.influxdb ip route

check-neo4j:
	@echo "[🔎] Verificando container neo4j"
	docker ps --format '{{.Names}}' | grep -q '^mn.neo4j$$' && echo "✅ Container mn.neo4j está rodando" || echo "❌ Container mn.neo4j não está rodando"
	@echo "[🔎] Verificando serviço Neo4j (porta 7474)"
	docker exec -it mn.neo4j bash -c 'nc -z -w 2 127.0.0.1 7474' && echo "✅ Neo4j ouvindo na porta 7474" || echo "❌ Neo4j não está ouvindo na porta 7474"
	@echo "[🔎] Testando comunicação com middts"
	docker exec -it mn.neo4j ping -c 2 10.0.1.2 || echo "[ERRO] neo4j não pinga middts"
	docker exec -it mn.neo4j bash -c 'nc -vz -w 2 10.0.1.2 8000' || echo "[ERRO] neo4j não conecta TCP 8000 em middts"

check-parser:
	@echo "[🔎] Verificando container parser"
	@# Support either an in-topology mn.parser or an external container named 'parser'
	@if docker ps --format '{{.Names}}' | grep -q '^mn.parser$$'; then \
		echo "✅ Container mn.parser está rodando"; \
		echo "[🔎] Verificando serviço Parser (porta 8080) dentro da topologia"; \
		docker exec -it mn.parser bash -c 'nc -z -w 2 127.0.0.1 8080' && echo "✅ Parser (mn.parser) ouvindo na porta 8080" || echo "❌ Parser (mn.parser) não está ouvindo na porta 8080"; \
		echo "[🔎] Testando comunicação com middts (rede interna)"; \
		docker exec -it mn.parser ping -c 2 10.0.1.2 || echo "[ERRO] parser não pinga middts"; \
		docker exec -it mn.parser bash -c 'nc -vz -w 2 10.0.1.2 8000' || echo "[ERRO] parser não conecta TCP 8000 em middts"; \
	elif docker ps --format '{{.Names}}' | grep -q '^parser$$'; then \
		echo "ℹ️ Container externo 'parser' está rodando (fora da topologia)"; \
		echo "Ports:"; docker port parser || true; \
		echo "Nota: parser é externo — verificações de rede internas (ping entre mn.*) serão ignoradas."; \
		echo "Você pode testar acessibilidade via host com: nc -z -v -w 2 127.0.0.1 8082"; \
	else \
		echo "❌ Nenhum container 'parser' encontrado (nem mn.parser nem parser)"; \
		echo "Inicie o parser externamente: make run-parser"; \
	fi

# Simuladores
check-simulators:
	@echo "[🔎] Verificando todos os simuladores (sim_*)"
	for c in $$(docker ps --format '{{.Names}}' | grep '^mn.sim_'); do \
		echo "[Simulador] $$c"; \
		make check-simulator SIM=$$c; \
	done

check-simulator:
	@if [ -z "$(SIM)" ]; then echo "[ERRO] Use: make check-simulator SIM=mn.sim_001"; exit 1; fi
	@echo "[🔎] Verificando container $(SIM)"
	docker ps --format '{{.Names}}' | grep -q '^$(SIM)$$' && echo "✅ Container $(SIM) está rodando" || echo "❌ Container $(SIM) não está rodando"
	@echo "[🔎] Verificando serviço do simulador (porta 5000)"
	docker exec -it $(SIM) bash -c 'nc -z -w 2 127.0.0.1 5000' && echo "✅ Simulador ouvindo na porta 5000" || echo "❌ Simulador não está ouvindo na porta 5000"
	@echo "[🔎] Testando comunicação com tb"
	docker exec -it $(SIM) ping -c 2 10.10.1.2 || echo "[ERRO] $(SIM) não pinga tb"
	docker exec -it $(SIM) bash -c 'nc -vz -w 2 10.10.1.2 8080' || echo "[ERRO] $(SIM) não conecta TCP 8080 em tb"

# Topology health check: runs the comprehensive check script created in scripts/check_topology.sh
.PHONY: topo-check
topo-check:
	@echo "[🔁] Running topology health checks (scripts/check_topology.sh)"
	@chmod +x scripts/check_topology.sh || true
	@./scripts/check_topology.sh

# === Process management helpers (simulators & middts) ===

.PHONY: sims_status sims_call sims_stop sims_kill middts_status middts_call middts_stop middts_kill

# -- Simulator helpers (operate on mn.sim_* by default, or specify SIM=mn.sim_001)
sims_status:
	@echo "[sims_status] Listing manage.py-related processes in simulators"
	@for c in $$(docker ps --format '{{.Names}}' | grep '^mn.sim_' || true); do \
		echo "== $$c =="; \
		docker exec $$c sh -c "ps -eo pid,cmd | grep -E 'manage.py|send_telemetry|runserver' | grep -v grep || echo '  <no manage.py processes>'" || true; \
	done

sims_call:
	@if [ -z "$(ARGS)" ]; then echo "[USO] make sims_call ARGS='--randomize --memory' [SIM=mn.sim_001]"; exit 1; fi
	@for c in $$(if [ -n "$(SIM)" ]; then echo $(SIM); else docker ps --format '{{.Names}}' | grep '^mn.sim_' || true; fi); do \
		echo "[sims_call] Starting send_telemetry in $$c with args: $(ARGS)"; \
		docker exec $$c sh -c "cd /iot_simulator && nohup python manage.py send_telemetry $(ARGS) > /iot_simulator/send_telemetry.out 2>&1 & echo \$$! >/tmp/send_telemetry.pid" || echo "[WARN] failed to exec in $$c"; \
	done

sims_stop:
	@for c in $$(if [ -n "$(SIM)" ]; then echo $(SIM); else docker ps --format '{{.Names}}' | grep '^mn.sim_' || true; fi); do \
		echo "[sims_stop] Stopping send_telemetry in $$c"; \
		docker exec $$c sh -c "pkill -f 'manage.py send_telemetry' || true; rm -f /tmp/send_telemetry.pid || true" || true; \
	done

sims_kill:
	@for c in $$(if [ -n "$(SIM)" ]; then echo $(SIM); else docker ps --format '{{.Names}}' | grep '^mn.sim_' || true; fi); do \
		echo "[sims_kill] Killing send_telemetry in $$c"; \
		docker exec $$c sh -c "pkill -9 -f 'manage.py send_telemetry' || true; rm -f /tmp/send_telemetry.pid || true" || true; \
	done

# -- MiddTS helpers (operate on mn.middts by default)
middts_status:
	@echo "[middts_status] Listing processes related to middts (gunicorn/manage.py)"
	@for c in $$(if [ -n "$(SIM)" ]; then echo $(SIM); else echo mn.middts; fi); do \
		echo "== $$c =="; \
		docker exec $$c sh -c "ps -eo pid,cmd | grep -E 'gunicorn|manage.py|runserver|middts' | grep -v grep || echo '  <no middts processes>'" || true; \
	done

middts_call:
	@# Allow ARGS to be provided as environment or as extra goal: `make middts_call update_causal_property`
	@ARGS_FROM_GOALS := $(filter-out $@,$(MAKECMDGOALS))
	@ARGS_SHELL="$(if $(ARGS),$(ARGS),$(ARGS_FROM_GOALS))"; \
	if [ -z "$$ARGS_SHELL" ]; then echo "[USO] make middts_call ARGS='--some-args' [SIM=mn.middts]"; exit 1; fi; \
	for c in $$(if [ -n "$(SIM)" ]; then echo $(SIM); else echo mn.middts; fi); do \
		echo "[middts_call] Running command in $$c: python manage.py $$ARGS_SHELL"; \
		docker exec $$c sh -c "cd /middleware-dt && nohup python manage.py $$ARGS_SHELL > /middleware-dt/call.out 2>&1 & echo \$$! >/tmp/middts_call.pid" || echo "[WARN] failed to exec in $$c"; \
	done

middts_stop:
	@for c in $$(if [ -n "$(SIM)" ]; then echo $(SIM); else echo mn.middts; fi); do \
		echo "[middts_stop] Stopping manage.py-related processes in $$c"; \
		docker exec $$c sh -c "pkill -f 'manage.py' || true; rm -f /tmp/middts_call.pid || true" || true; \
	done

middts_kill:
	@for c in $$(if [ -n "$(SIM)" ]; then echo $(SIM); else echo mn.middts; fi); do \
		echo "[middts_kill] Killing manage.py-related processes in $$c"; \
		docker exec $$c sh -c "pkill -9 -f 'manage.py' || true; rm -f /tmp/middts_call.pid || true" || true; \
	done

# Recreate a single container by removing it; does not attempt to recreate automatically.
# Usage: make recreate-container SERVICE=tb
.PHONY: recreate-container
recreate-container:
	@if [ -z "$(SERVICE)" ]; then echo "[USO] make recreate-container SERVICE=tb (removerá mn.<service>)"; exit 1; fi
	@echo "[🔁] Recriando container mn.$(SERVICE) -> removendo container atual (se existir)"
	-docker rm -f mn.$(SERVICE) || true
	@echo "[🔁] mn.$(SERVICE) removido. Para recriar o serviço, execute o comando de topologia (ex: make topo) ou o pipeline de deploy apropriado."

# === RESTORE ON-DEMAND (middts + simulators) ===
.PHONY: restore-scenario restore-middts restore-simulators restore-sim

# === DIGITAL TWINS MANAGEMENT ===
.PHONY: reset-digital-twins reset-digital-twins-dry reset-digital-twins-force

# Reset and recreate Digital Twins from devices with available DTDL modeling
# Usage: make reset-digital-twins [SYSTEM_ID=1] [DRY_RUN=true] [FORCE=true]
reset-digital-twins:
	@echo "[🎯] Resetting and recreating Digital Twins from devices..."
	@DJANGO_CMD="reset_digital_twins"; \
	if [ "$(DRY_RUN)" = "true" ]; then DJANGO_CMD="$$DJANGO_CMD --dry-run"; fi; \
	if [ "$(FORCE)" = "true" ]; then DJANGO_CMD="$$DJANGO_CMD --force"; fi; \
	if [ -n "$(SYSTEM_ID)" ]; then DJANGO_CMD="$$DJANGO_CMD --system-id=$(SYSTEM_ID)"; fi; \
	docker exec mn.middts bash -c "cd /middleware-dt && python manage.py $$DJANGO_CMD" || echo "[ERROR] Failed to reset Digital Twins"

# Dry run version - shows what would be done without making changes
reset-digital-twins-dry:
	@$(MAKE) reset-digital-twins DRY_RUN=true

# Force version - no confirmation prompts
reset-digital-twins-force:
	@$(MAKE) reset-digital-twins FORCE=true

# Reset Digital Twins using standalone script (alternative method)
reset-digital-twins-script:
	@echo "[🎯] Running standalone Digital Twin reset script..."
	@docker exec mn.middts python /var/condominio-scenario/scripts/reset_digital_twins.py || echo "[ERROR] Script execution failed"

# High-level: restore everything needed for the scenario (middts DB + all simulator sqlite files)
restore-scenario: restore-middts restore-simulators

# Restore middts DB: drop/create middts and import services/middleware-dt/middts.sql
# Requires that the Postgres container be running as 'mn.db' and docker CLI available.
restore-middts:
	@echo "[RESTORE] Delegating middts restore to scripts/restore_middts.sh"; \
	@chmod +x scripts/restore_middts.sh; scripts/restore_middts.sh

# Restore all simulator sqlite files by copying the initial template into the host file mounted into each simulator.
# This assumes simulators mount the host file services/iot_simulator/db.sqlite3 into /iot_simulator/db.sqlite3
restore-simulators:
	@echo "[RESTORE] Restoring simulator sqlite DBs (host file services/iot_simulator/db.sqlite3 will be replaced)"
	@if [ ! -f services/iot_simulator/initial_data/db_scenario.sqlite3 ]; then echo "[ERRO] services/iot_simulator/initial_data/db_scenario.sqlite3 not found"; exit 1; fi
	@cp services/iot_simulator/initial_data/db_scenario.sqlite3 services/iot_simulator/db.sqlite3 || (echo "[ERRO] copy failed"; exit 1); \
	chmod 666 services/iot_simulator/db.sqlite3 || true; \
	echo "[RESTORE] host simulator DB replaced. Restart simulators/entrypoints if necessary."

# Restore single simulator (useful for per-sim debugging). Usage: make restore-sim SIM=mn.sim_001
restore-sim:
	@if [ -z "$(SIM)" ]; then echo "[USO] make restore-sim SIM=mn.sim_001"; exit 1; fi
	@echo "[RESTORE] Restoring simulator $(SIM) sqlite DB from services/iot_simulator/initial_data/db_scenario.sqlite3"
	@if [ ! -f services/iot_simulator/initial_data/db_scenario.sqlite3 ]; then echo "[ERRO] services/iot_simulator/initial_data/db_scenario.sqlite3 not found"; exit 1; fi
	@cp services/iot_simulator/initial_data/db_scenario.sqlite3 services/iot_simulator/db.sqlite3 || (echo "[ERRO] copy failed"; exit 1); \
	chmod 666 services/iot_simulator/db.sqlite3 || true; \
	echo "[RESTORE] host simulator DB replaced. If $(SIM) is running, restart its entrypoint inside the container: make exec-sim SIM=$(SIM) CMD='kill 1 && /entrypoint.sh &'"

# Teste de rede geral
check-network:
	@echo "[🔎] Testando conectividade de rede entre todos os containers principais"
	@echo "[tb] IPs e interfaces:"
	docker exec -it mn.tb ip addr || echo "[ERRO] Falha ao obter IP do tb"
	@echo "[middts] IPs e interfaces:"
	docker exec -it mn.middts ip addr || echo "[ERRO] Falha ao obter IP do middts"
	@echo "[db] IPs e interfaces:"
	docker exec -it mn.db ip addr || echo "[ERRO] Falha ao obter IP do db"
	@echo "[influxdb] IPs e interfaces:"
	docker exec -it mn.influxdb ip addr || echo "[ERRO] Falha ao obter IP do influxdb"
	@echo "[neo4j] IPs e interfaces:"
	docker exec -it mn.neo4j ip addr || echo "[ERRO] Falha ao obter IP do neo4j"
	@echo "[parser] IPs e interfaces:"
		@if docker ps --format '{{.Names}}' | grep -q '^mn.parser$$'; then \
			docker exec -it mn.parser ip addr || echo "[ERRO] Falha ao obter IP do parser"; \
		elif docker ps --format '{{.Names}}' | grep -q '^parser$$'; then \
			echo "[ℹ️] Parser está rodando como container externo 'parser'"; docker port parser || true; \
			echo "[ℹ️] Parser é externo — não é possível exibir interfaces internas da topologia."; \
		else \
			echo "[WARN] Nenhum container parser detectado (mn.parser ou parser)"; \
		fi
	@echo "[tb <-> middts] ping e TCP"
	docker exec -it mn.tb ping -c 2 10.10.2.2 || echo "[ERRO] tb não pinga middts"
	docker exec -it mn.middts ping -c 2 10.10.1.2 || echo "[ERRO] middts não pinga tb"
	docker exec -it mn.tb bash -c 'nc -vz -w 2 10.10.2.2 8000' || echo "[ERRO] tb não conecta TCP 8000 em middts"
	docker exec -it mn.middts bash -c 'nc -vz -w 2 10.10.1.2 8080' || echo "[ERRO] middts não conecta TCP 8080 em tb"
	@echo "[tb <-> db] ping e TCP"
	docker exec -it mn.tb ping -c 2 10.0.0.10 || echo "[ERRO] tb não pinga db"
	docker exec -it mn.db ping -c 2 10.10.1.2 || echo "[ERRO] db não pinga tb"
	docker exec -it mn.tb bash -c 'nc -vz -w 2 10.0.0.10 5432' || echo "[ERRO] tb não conecta TCP 5432 em db"
	docker exec -it mn.db bash -c 'nc -vz -w 2 10.10.1.2 8080' || echo "[ERRO] db não conecta TCP 8080 em tb"
	@echo "[middts <-> db] ping e TCP"
	docker exec -it mn.middts ping -c 2 10.10.2.10 || echo "[ERRO] middts não pinga db"
	docker exec -it mn.db ping -c 2 10.10.2.2 || echo "[ERRO] db não pinga middts"
	docker exec -it mn.middts bash -c 'nc -vz -w 2 10.10.2.10 5432' || echo "[ERRO] middts não conecta TCP 5432 em db"
	docker exec -it mn.db bash -c 'nc -vz -w 2 10.10.2.2 8000' || echo "[ERRO] db não conecta TCP 8000 em middts"
	@echo "[middts <-> influxdb] ping e TCP"
	docker exec -it mn.middts ping -c 2 10.0.1.20 || echo "[ERRO] middts não pinga influxdb"
	docker exec -it mn.influxdb ping -c 2 10.0.1.2 || echo "[ERRO] influxdb não pinga middts"
	docker exec -it mn.middts bash -c 'nc -vz -w 2 10.0.1.20 8086' || echo "[ERRO] middts não conecta TCP 8086 em influxdb"
	docker exec -it mn.influxdb bash -c 'nc -vz -w 2 10.0.1.2 8000' || echo "[ERRO] influxdb não conecta TCP 8000 em middts"
	@echo "[middts <-> neo4j] ping e TCP"
	docker exec -it mn.middts ping -c 2 10.10.2.30 || echo "[ERRO] middts não pinga neo4j"
	docker exec -it mn.neo4j ping -c 2 10.0.1.2 || echo "[ERRO] neo4j não pinga middts"
	docker exec -it mn.middts bash -c 'nc -vz -w 2 10.10.2.30 7474' || echo "[ERRO] middts não conecta TCP 7474 em neo4j"
	@echo "[middts <-> parser] ping e TCP"
	@if docker ps --format '{{.Names}}' | grep -q '^mn.parser$$'; then \
		docker exec -it mn.middts ping -c 2 10.10.2.40 || echo "[ERRO] middts não pinga parser"; \
		docker exec -it mn.parser ping -c 2 10.10.2.2 || echo "[ERRO] parser não pinga middts"; \
		docker exec -it mn.middts bash -c 'nc -vz -w 2 10.10.2.40 8080' || echo "[ERRO] middts não conecta TCP 8080 em parser"; \
	elif docker ps --format '{{.Names}}' | grep -q '^parser$$'; then \
		echo "[ℹ️] Parser rodando externamente — teste de conectividade via host:"; \
		echo "nc -z -v -w 2 127.0.0.1 8082"; \
	else \
		echo "[WARN] Nenhum parser detectado para testar (mn.parser ou parser)"; \
	fi
	@echo "[Simuladores <-> tb] ping e TCP"
	for i in 1 2 3 4 5; do \
	  sim_ip="10.10.$$((10+i)).2"; \
	  tb_ip="10.10.1.2"; \
	  docker exec -it mn.tb ping -c 2 $$sim_ip || echo "[ERRO] tb não pinga sim_$$i"; \
	  docker exec -it mn.sim_`printf '%03d' $$i` ping -c 2 $$tb_ip || echo "[ERRO] sim_$$i não pinga tb"; \
	  docker exec -it mn.tb bash -c "nc -vz -w 2 $$sim_ip 5000" || echo "[ERRO] tb não conecta TCP 5000 em sim_$$i"; \
	  docker exec -it mn.sim_`printf '%03d' $$i` bash -c "nc -vz -w 2 $$tb_ip 8080" || echo "[ERRO] sim_$$i não conecta TCP 8080 em tb"; \
	done

# === INTELLIGENT ANALYSIS ===
.PHONY: intelligent-analysis analyze-latest compare-urllc compare-profiles dashboard

# Run intelligent analysis on a specific test directory
# Usage: make intelligent-analysis TEST_DIR=results/test_20251006T004352Z_urllc
intelligent-analysis:
	@if [ -z "$(TEST_DIR)" ]; then \
		echo "❌ Erro: Use 'make intelligent-analysis TEST_DIR=<path_to_test_directory>'"; \
		echo "📁 Exemplo: make intelligent-analysis TEST_DIR=results/test_20251006T004352Z_urllc"; \
		exit 1; \
	fi
	@echo "🔍 Executando análise inteligente em $(TEST_DIR)..."
	@python3 scripts/reports/report_generators/intelligent_test_analysis.py "$(TEST_DIR)"

# Run intelligent analysis on the most recent URLLC test
analyze-latest:
	@echo "🔍 Encontrando o teste URLLC mais recente..."
	@latest_urllc=$$(find results -name "test_*_urllc" -type d | sort | tail -1); \
	if [ -z "$$latest_urllc" ]; then \
		echo "❌ Nenhum teste URLLC encontrado em results/"; \
		exit 1; \
	fi; \
	echo "📁 Analisando: $$latest_urllc"; \
	$(MAKE) intelligent-analysis TEST_DIR=$$latest_urllc

# Compare all URLLC tests and show evolution over time
compare-urllc:
	@echo "📊 Executando análise comparativa de todos os testes URLLC..."
	@python3 scripts/reports/report_generators/compare_urllc_tests.py results/

# Compare URLLC vs eMBB vs best_effort profiles
compare-profiles:
	@echo "⚔️ Executando comparação entre perfis de rede..."
	@python3 scripts/reports/report_generators/compare_urllc_vs_embb.py

# Generate executive dashboard of current URLLC status
dashboard:
	@echo "🎯 Gerando dashboard executivo URLLC..."
	@python3 scripts/urllc_dashboard.py
