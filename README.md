# 🧪 MidDiTS 6G Digital Twin Testbed

Este repositório contém um ambiente completo e reprodutível para simulação de sistemas de gêmeos digitais integrados a redes 5G/6G, com MidDiTS, ThingsBoard e múltiplos simuladores IoT.

## 🧩 Componentes

- **MidDiTS**: Middleware de orquestração e gerenciamento de Digital Twins.
- **ThingsBoard**: Plataforma de IoT para coleta e controle dos dispositivos.
- **IoT Simulator**: Simula dispositivos físicos (ex: sensores de fumaça, fechaduras, lâmpadas).
- **Mininet**: Simulador de rede para experimentos com QoS e Slicing.

## 📦 Estrutura

```bash
middts/                 # Código do middleware MidDiTS
simulator/              # Código do IoT Simulator
topologias/             # Arquivos de topologia Mininet
scripts/               # Scripts de controle e instalação
Makefile                # Orquestra instalação e execução
.env.example            # Variáveis para clonar repositórios privados
```

## 🚀 Como usar

### 1. Clone este repositório e prepare o .env

```bash
cp .env.example .env
# Edite .env com os repositórios privados (GitLab)
```

### 2. Configure tudo com Make

```bash
./setup.sh        # Roda o make setup e make install
make net          # Roda topologia Mininet simples
make net-qos      # Roda topologia com slices de rede (URLLC, eMBB, Best Effort)
make run          # Sobe MidDiTS, ThingsBoard e simuladores
```

---

## Instalação Inicial Manual na VM

Se preferir instalar manualmente ou não utilizar o Makefile, siga os passos abaixo:

### 1. Dependências

Certifique-se de que sua VM possui:
- Docker
- Docker Compose
- Git
- Python 3 (para scripts auxiliares)

### 2. Configuração do ambiente

1. Clone este repositório:
   ```bash
   git clone <url-do-repositorio-condominio-scenario>
   cd condominio-scenario
   ```

2. Configure o arquivo `.env` conforme exemplo abaixo:
   ```env
   # Exemplo de token de acesso GitLab
   GITLAB_TOKEN=seu_token_aqui

   # .env
   SIMULATOR_COUNT=100
   MIDDTS_REPO_URL=https://github.com/seu-usuario/middts.git
   SIMULATOR_REPO_URL=https://github.com/seu-usuario/iot_simulator.git
   COMPOSE_NETWORK=simnet
   INFLUXDB_TOKEN=admin_token_middts
   INFLUXDB_ORG=middts
   INFLUXDB_BUCKET=iot_data
   ```

### 3. Clonagem dos projetos necessários

Clone os repositórios do `middts` e do `iot_simulator` conforme URLs configuradas no `.env`.

### 4. Build das imagens Docker

Certifique-se de que as imagens do `middts` e do `iot_simulator` estejam construídas e disponíveis localmente ou em um registry acessível.

Exemplo para build local:
```bash
cd middts
docker build -t middts:latest .
cd ../iot_simulator
docker build -t iot_simulator:latest .
```

### 5. Gerar o arquivo docker-compose

Execute o script para gerar o arquivo de composição dos containers:
```bash
python3 generate-compose.py
```
O arquivo será gerado em `generated/docker-compose.generated.yml`.

### 6. Subir o cenário

Utilize o docker-compose para subir o ambiente:
```bash
docker-compose -f generated/docker-compose.generated.yml up -d
```

### 7. Acesso aos serviços

- Thingsboard: acesse pela porta padrão configurada no compose
- Middts: acesse pela porta 8000

### Observações

- Cada simulador terá 3 conexões com o Thingsboard, respeitando o QoS.
- O Thingsboard terá 3 conexões com o Middts para QoS.
- O Middts pode ser acessado para gerar digital twins dos devices de cada casa.

Se ocorrer algum erro durante o processo, siga as mensagens de erro e reporte para correção.

### 3. Controle os simuladores

```bash
make sims-start                           # Inicia 100 containers
make sims-call ARGS="sync"               # Roda comando em todos
make sims-call ARGS="sim_001 sim_002 status"  # Apenas em alguns
make sims-stop                            # Para todos os simuladores
```

### 4. Acesse os serviços

- ThingsBoard: http://localhost:8080  
- MidDiTS API: http://localhost:8000  

## 🧹 Reset e limpeza

```bash
make reset        # Para containers e limpa Mininet
make uninstall    # Remove tudo da máquina (reversão total)
```

## ✍️ Autor

Este projeto foi criado e organizado por pesquisadores do IFRN, UFRN, UFF, University of Coimbra and University of North Carolina  no contexto de avaliação de middleware para gêmeos digitais em redes 6G.
