# 🧪 MidDiTS 6G Digital Twin Testbed

Este repositório contém um ambiente completo e reprodutível para simulação de sistemas de gêmeos digitais integrados a redes 5G/6G, com MidDiTS, ThingsBoard e múltiplos simuladores IoT, todos conectados via topologia definida no Mininet com suporte a QoS e slices (URLLC, eMBB, Best Effort).

---

## 🧩 Componentes

- **MidDiTS**: Middleware de orquestração e gerenciamento de Digital Twins.
- **ThingsBoard**: Plataforma de IoT para coleta e controle dos dispositivos.
- **IoT Simulator**: Simuladores de dispositivos físicos (lâmpadas, sensores, atuadores).
- **Mininet**: Simulador de rede para experimentos com controle de QoS.
- **Docker + Docker Compose**: Orquestração dos serviços.

---

## 📦 Estrutura do Repositório

```bash
middts/                 # Código-fonte do middleware MidDiTS
simulator/              # Código-fonte do IoT Simulator
mininet/                # Topologias em Python (topo.py e topo_qos.py)
generated/              # Arquivos docker-compose gerados
scripts/                # Scripts de instalação e controle
commands/               # Scripts para controle dos simuladores
Makefile                # Orquestrador principal
.env.example            # Variáveis de ambiente para setup
```

---

## 🚀 Primeiros Passos

### 1. Clone o repositório e configure seu .env

```bash
cp .env.example .env
# Edite o arquivo .env conforme suas URLs de repositórios
```

### 2. Instale tudo com o script de setup

```bash
chmod +x setup.sh
./setup.sh
```

Esse script:
- Instala pacotes como Docker, Mininet, Socat, Screen, etc.
- Clona ou atualiza `middts` e `iot_simulator` via SSH ou HTTPS
- Prepara o ambiente para execução.

---

## 🌐 Controle de Topologias com Makefile

### 🧩 Criar Topologia

```bash
make net-qos-interactive   # Cria a topologia com CLI ativa. Serve para rodar algo e depois ao sair matar tudo.
make net-qos-screen        # Cria a topologia rodando dentro de uma screen. Permitindo dar um detach ao final com ctrl + a + d e voltando usando screen -r mininet-session
make net-qos               # Cria a topologia em segundo plano (detach)
```

### 🔎 Acompanhar ou Gerenciar a Topologia

```bash
make net-cli               # Entra na CLI do Mininet via screen
make net-sessions          # Lista todas as screens abertas
make net-status            # Verifica se a screen mininet-session está ativa
make net-screen-kill       # Mata a screen ativa da topologia
make net-clean             # Limpa qualquer topologia anterior
```

---

## 🧰 Instalar e Rodar os Componentes

### ThingsBoard

```bash
make thingsboard           # Executa script de instalação no host 'tb'
```

### MidDiTS, Simuladores e Compose

```bash
make run                   # Sobe todos os containers (MidDiTS, TB, Simuladores)
make sims-start            # Sobe apenas os simuladores
make sims-stop             # Para todos os simuladores
make sims-call-all ARGS="status"    # Executa comando em todos
make sims-call ARGS="sim_001 sim_002 status"  # Em alguns
```

---

## 🎯 Visualização da Topologia

```bash
make net-graph             # Exibe grafo com xdot (requer graphviz)
```

---

## 🧹 Limpeza e Reset

```bash
make reset                 # Para e remove containers + limpa mininet
make uninstall             # Remove tudo (MidDiTS, Simuladores, dependências)
```

---

## 🔐 Exemplo de .env

```dotenv
USE_SSH=true
SIMULATOR_COUNT=100
MIDDTS_REPO_URL=https://github.com/Digital-Twins-RSBR/middleware-dt.git
SIMULATOR_REPO_URL=https://github.com/Digital-Twins-RSBR/iot_simulator.git
COMPOSE_NETWORK=simnet
INFLUXDB_TOKEN=admin_token_middts
INFLUXDB_ORG=middts
INFLUXDB_BUCKET=iot_data
```

---

## ✍️ Autoria

Este projeto foi criado e organizado por pesquisadores do IFRN, UFRN, UFF, University of Coimbra e University of North Carolina no contexto de avaliação de middleware para gêmeos digitais em redes 6G.
