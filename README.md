# 🧪 MidDiTS 6G Digital Twin Testbed (Containernet Edition)

Este repositório fornece um ambiente completo e reprodutível para simulações de gêmeos digitais em cenários de redes 5G/6G. Utiliza **Containernet** para simular hosts como containers Docker, com integração de QoS e múltiplos caminhos entre dispositivos simulados e um broker IoT (ThingsBoard).

## 🔧 Componentes

- **MidDiTS**: Middleware de gerenciamento e orquestração de Digital Twins.
- **ThingsBoard**: Plataforma de IoT para coleta, visualização e controle.
- **IoT Simulator**: Simula sensores físicos que se conectam via MQTT e escrevem telemetria.
- **Containernet**: Simulador de rede baseado em Docker com suporte a topologias customizadas e controle de links.

## 📁 Estrutura do Projeto

```bash
topology/                 # Arquivos de topologia (topo.py, topo_qos.py, draw_topology.py)
scripts/                  # Scripts utilitários (instalação, montagem de volumes, etc.)
middleware-dt/                   # Repositório clonado do MidDiTS
iot_simulator/                # Repositório clonado do IoT Simulator
setup.sh                  # Script para instalação completa
Makefile                  # Automação dos comandos
.env.example              # Arquivo com variáveis de configuração
```

---

## 🚀 Como usar

### 1. Clonar este repositório e preparar o `.env`
Você pode clonar o repositório direto ou adicionar uma chave ssh
para poder baixar os repositórios do middts e do simulator.

```bash
git clone https://github.com/seu-usuario/condominio-scenario.git
cd condominio-scenario
cp .env.example .env
nano .env  # Edite com URLs dos repositórios
```

### 2. Executar o setup

```bash
chmod +x setup.sh

./setup.sh        # Instala tudo e configura Containernet
make setup        # Clona/atualiza MiddTS e Simulator
make install      # Instala dependências
make build-images # Compila as imagens Docker locais
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
# Interativo
make topo

# Em background (com screen):
make net-qos    # Sobe topologia em screen
make net-cli    # Volta à CLI da sessão quando quiser

# Para parar e limpar
make net-clean
```

## 🎯 O que acontece na topologia:

- Um container Docker executa o ThingsBoard (imagem thingsboard/tb:<versão>).
- Outro container roda o MidDiTS (imagem middts:latest).
- SIMULATOR_COUNT containers iot_simulator:latest simulam casas/dispositivos.
- Cada simulador gera três links com QoS (URLLC, eMBB, Best Effort) até o ThingsBoard.
- Link dedicado conecta ThingsBoard ↔ MidDiTS.

---

## 🎯 Visualizando o desenho da topologia

- Seção futura

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

## 🧩 Executando o Parser (fora da topologia)

O `parser` foi retirado da topologia Containernet e deve ser executado como um container Docker normal no host para que o MidDiTS (middts) possa acessá-lo via porta mapeada.

Você pode usar os alvos do Makefile:

```bash
make run-parser   # Inicia um container 'parser' (detached) usando a imagem local parserwebapi-tools:latest
make stop-parser  # Para e remove o container 'parser'
```

Por padrão o `make run-parser` mapeará as portas 8080->8082 e 8081->8083 no host. Ajuste manualmente se necessário.

Os logs do parser (stdout/stderr) serão seguidos pelo assistente de topologia e gravados em `deploy/logs/parser_start.log` quando o container externo estiver rodando com o nome `parser`.


---

## Erros conhecidos

The following packages have unmet dependencies:
containerd.io : Conflicts: containerd

Código pra resolver: 
``` bash
sudo rm -f /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get purge -y containerd.io
sudo apt-get autoremove -y
```

---

## ✍️ Créditos

Este projeto foi idealizado e mantido por pesquisadores do **IFRN**, **UFRN**, **UFF**, **University of Coimbra** e **University of North Carolina**, como parte de experimentos sobre **Gêmeos Digitais e redes 6G**.
