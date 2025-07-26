# 🧪 MidDiTS 6G Digital Twin Testbed (Containernet Edition)

Este repositório fornece um ambiente completo e reprodutível para simulações de gêmeos digitais em cenários de redes 5G/6G. Utiliza **Containernet** para simular hosts como containers Docker, com integração de QoS e múltiplos caminhos entre dispositivos simulados e um broker IoT (ThingsBoard).

## 🔧 Componentes

- **MidDiTS**: Middleware de gerenciamento e orquestração de Digital Twins.
- **ThingsBoard**: Plataforma de IoT para coleta, visualização e controle.
- **IoT Simulator**: Simula sensores físicos que se conectam via MQTT e escrevem telemetria.
- **Containernet**: Simulador de rede baseado em Docker com suporte a topologias customizadas e controle de links.

## 📁 Estrutura do Projeto

```bash
containernet/             # Arquivos de topologia (topo.py, topo_qos.py, draw_topology.py)
scripts/                  # Scripts utilitários (instalação, montagem de volumes, etc.)
middts/                   # Repositório clonado do MidDiTS
simulator/                # Repositório clonado do IoT Simulator
setup.sh                  # Script para instalação completa
Makefile                  # Automação dos comandos
.env.example              # Arquivo com variáveis de configuração
```

---

## 🚀 Como usar

### 1. Clonar este repositório e preparar o `.env`

```bash
git clone https://github.com/seu-usuario/condominio-scenario.git
cd condominio-scenario
cp .env.example .env
nano .env  # Edite com URLs dos repositórios
```

### 2. Executar o setup

```bash
chmod +x setup.sh
./setup.sh
```

Isso irá:
- Instalar dependências
- Clonar os repositórios
- Preparar os arquivos compartilhados
- Ativar o Docker

---

## 🧱 Criando a Topologia

### Topologia com QoS (3 caminhos por simulador)

```bash
sudo python3 containernet/topo_qos.py

# ou então

make topo
```

A topologia conterá:
- 100 hosts simuladores (`sim_001` a `sim_100`)
- Host `tb` (ThingsBoard)
- Host `middts` (MidDiTS)
- Cada simulador terá 3 links para `tb`, com diferentes características de QoS (URLLC, eMBB, Best Effort)

---

## 🧠 Interagindo com a Rede

Você pode usar o prompt da Containernet (baseado no Mininet):

```bash
containernet> pingall
containernet> sim_001 ifconfig
containernet> sim_001 python3 start_simulator.py
```

Ou, se estiver usando um Makefile com automações, por exemplo:

```bash
make run
make sims-start
make sims-call ARGS="sim_001 status"
```

---

## 📦 Subindo os Serviços

1. Acesse o host `tb` na Containernet:
```bash
containernet> tb bash
```

2. Execute o script de instalação do ThingsBoard:
```bash
cd /mnt/scripts
./install_thingsboard_in_namespace.sh
```

3. Faça o mesmo para o MidDiTS no host `middts`.

---

## 🔗 Montando Diretórios Compartilhados (Scripts, Configs)

```bash
make mount-shared-dirs
```

Isso montará o diretório `scripts/` local como `/mnt/scripts/` dentro de todos os hosts da topologia.

---

## 📊 Visualizando a Topologia

```bash
make net-graph
```

> Requer o pacote `graphviz` e o utilitário `xdot`.

---

## 🧹 Reset e Limpeza

```bash
make clean           # Remove repositórios
make reset           # Para containers
```

---

## ✍️ Créditos

Este projeto foi idealizado e mantido por pesquisadores do **IFRN**, **UFRN**, **UFF**, **University of Coimbra** e **University of North Carolina**, como parte de experimentos sobre **Gêmeos Digitais e redes 6G**.
