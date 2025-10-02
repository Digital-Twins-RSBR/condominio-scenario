# Visualização de Topologia - Condomínio Scenario

Este módulo fornece ferramentas avançadas para visualizar e analisar a topologia da simulação Mininet/Containernet do projeto condomínio scenario.

## 🚀 Funcionalidades

### 1. Visualizador de Topologia (`topology_visualizer.py`)
- **Diagrama Principal**: Mostra todos os nós, switches e conexões
- **Visão Hierárquica**: Apresenta a arquitetura em camadas
- **Múltiplos Formatos**: PNG, PDF, GraphML, DOT
- **Estatísticas da Rede**: Métricas de conectividade e análise

### 2. Captura em Tempo Real (`live_topology_capture.py`)
- **Integração com Mininet**: Captura topologia durante execução
- **Monitoramento Contínuo**: Acompanha mudanças na rede
- **Relatórios HTML**: Interface web interativa

### 3. Integração com topo_qos.py
- **Visualização Automática**: Gera diagramas após configuração da rede
- **Configuração Flexível**: Diferentes números de simuladores
- **Output Personalizado**: Diretórios e formatos configuráveis

## 📦 Dependências

```bash
# Instalar dependências via apt (recomendado)
sudo apt update
sudo apt install -y python3-networkx python3-matplotlib python3-pydot graphviz

# Ou via pip (em virtual environment)
pip install networkx matplotlib pydot
```

## 🛠️ Como Usar

### Método 1: Visualização Estática
```bash
# Gerar visualizações para 5 simuladores
cd services/topology
python3 topology_visualizer.py --sims 5 --output ./topology_output

# Com relatório HTML
python3 live_topology_capture.py --report --output ./topology_output
```

### Método 2: Durante a Simulação
```bash
# Executar simulação com visualização automática
python3 topo_qos.py --sims 5 --visualize

# Modo verbose com visualização
python3 topo_qos.py --verbose --sims 10 --visualize
```

### Método 3: Demonstração Completa
```bash
# Executar script de demonstração
./demo_visualization.sh
```

## 📊 Outputs Gerados

### Arquivos de Imagem
- **`*_main.png`**: Diagrama principal da topologia
- **`*_hierarchical.png`**: Visão hierárquica em camadas
- **`*_graphviz.pdf`**: Diagrama PDF gerado pelo Graphviz

### Arquivos de Dados
- **`*.graphml`**: Formato GraphML para Gephi, Cytoscape, etc.
- **`*.dot`**: Formato DOT para Graphviz
- **`*_stats.json`**: Estatísticas detalhadas da rede

### Relatórios
- **`topology_report.html`**: Relatório interativo com todas as visualizações

## 🎨 Personalização

### Cores e Estilos
Edite as constantes no arquivo `topology_visualizer.py`:

```python
COLORS = {
    'main': '#2E86AB',      # Azul - ThingsBoard, Middleware
    'db': '#A23B72',        # Roxo - PostgreSQL
    'influx': '#F18F01',    # Laranja - InfluxDB
    'neo4j': '#C73E1D',     # Vermelho - Neo4j
    'parser': '#4ECDC4',    # Turquesa - Parser
    'switch': '#95A5A6',    # Cinza - Switches
    'sim': '#F39C12',       # Amarelo/Laranja - Simuladores
    'controller': '#27AE60' # Verde - Controller
}
```

### Tamanhos dos Nós
```python
SIZES = {
    'main': 1200,
    'db': 900,
    'influx': 700,
    # ... outros tipos
}
```

## 📈 Análise Avançada

### Usando Gephi
1. Instale o [Gephi](https://gephi.org/)
2. Abra o arquivo `.graphml` gerado
3. Aplique algoritmos de layout (Force Atlas, etc.)
4. Analise métricas de rede

### Usando NetworkX
```python
import networkx as nx

# Carregar topologia
G = nx.read_graphml('condominio_topology.graphml')

# Analisar métricas
print(f"Densidade: {nx.density(G)}")
print(f"Centralidade: {nx.betweenness_centrality(G)}")
```

## 🔧 Exemplos de Uso

### Exemplo 1: Visualização Básica
```bash
# Gerar topologia com 3 simuladores
python3 topology_visualizer.py --sims 3 --output ./test --filename my_topology
```

### Exemplo 2: Integração com Simulação
```python
from topo_qos import run_topo

# Executar simulação com visualização
run_topo(num_sims=5, visualize=True)
```

### Exemplo 3: Análise de Diferentes Configurações
```bash
# Comparar topologias com diferentes números de simuladores
for i in 3 5 10 15; do
    python3 topology_visualizer.py --sims $i --output ./comparison_$i --filename topo_$i
done
```

## 🎯 Casos de Uso

### 1. Documentação
- Gerar diagramas para relatórios e apresentações
- Documentar arquitetura do sistema
- Explicar configuração da rede

### 2. Debugging
- Visualizar problemas de conectividade
- Identificar gargalos na topologia
- Verificar configuração de links

### 3. Análise de Performance
- Comparar diferentes configurações
- Otimizar posicionamento de serviços
- Analisar caminhos de dados

### 4. Educação e Treinamento
- Ensinar conceitos de redes
- Demonstrar SDN/OpenFlow
- Visualizar IoT scenarios

## 📝 Estrutura dos Arquivos

```
services/topology/
├── topology_visualizer.py      # Visualizador principal
├── live_topology_capture.py    # Captura em tempo real
├── draw_topology.py           # Visualizador simples (legado)
├── demo_visualization.sh      # Script de demonstração
├── topo_qos.py               # Topologia principal (modificado)
└── README_topology.md        # Esta documentação
```

## 🐛 Troubleshooting

### Erro: "No module named 'networkx'"
```bash
sudo apt install python3-networkx python3-matplotlib
```

### Erro: "No display"
```bash
# Para ambientes sem display (SSH)
export MPLBACKEND=Agg
python3 topology_visualizer.py --sims 5
```

### Erro: "Permission denied"
```bash
# Dar permissões aos scripts
chmod +x *.py *.sh
```

### Graphviz PDF não gerado
```bash
# Instalar Graphviz
sudo apt install graphviz
```

## 🔗 Integração com Outras Ferramentas

### VS Code
- Use a extensão "Image Preview" para visualizar PNG
- Use "Live Server" para abrir relatórios HTML

### Jupyter Notebook
```python
from IPython.display import Image, HTML
Image('topology_main.png')
HTML('topology_report.html')
```

### CI/CD
```yaml
# GitHub Actions example
- name: Generate Topology
  run: |
    cd services/topology
    python3 topology_visualizer.py --sims 5
    
- name: Upload Artifacts
  uses: actions/upload-artifact@v2
  with:
    name: topology-diagrams
    path: services/topology/topology_output/
```

## 📚 Referências

- [NetworkX Documentation](https://networkx.org/)
- [Matplotlib Gallery](https://matplotlib.org/stable/gallery/)
- [Mininet Documentation](http://mininet.org/)
- [Containernet GitHub](https://github.com/containernet/containernet)

---

**Nota**: Este visualizador foi desenvolvido especificamente para o projeto condomínio scenario, mas pode ser adaptado para outras topologias Mininet/Containernet.
