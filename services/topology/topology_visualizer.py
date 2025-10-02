#!/usr/bin/env python3
"""
Visualizador de Topologia para Containernet
Gera representações gráficas da simulação Mininet/Containernet
"""

import os
import sys
import argparse
import networkx as nx
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.lines import Line2D
import subprocess
import json
from datetime import datetime

# Configurações de estilo
plt.style.use('default')
FIGSIZE = (16, 12)
DPI = 300

# Cores para diferentes tipos de nós
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

SIZES = {
    'main': 1200,
    'db': 900,
    'influx': 700,
    'neo4j': 700,
    'parser': 600,
    'switch': 400,
    'sim': 300,
    'controller': 800
}

class TopologyVisualizer:
    def __init__(self, num_sims=5, output_dir='./topology_output'):
        self.num_sims = num_sims
        self.output_dir = output_dir
        self.graph = nx.Graph()  # Usar Graph simples em vez de MultiGraph
        self.positions = {}
        
        # Criar diretório de saída
        os.makedirs(output_dir, exist_ok=True)
        
    def build_topology_graph(self):
        """Constrói o grafo baseado na topologia definida em topo_qos.py"""
        
        # Nós principais
        nodes = [
            ('c0', 'controller'),           # Controller
            ('tb', 'main'),                 # ThingsBoard
            ('middts', 'main'),             # Middleware
            ('db', 'db'),                   # PostgreSQL
            ('influxdb', 'influx'),         # InfluxDB
            ('neo4j', 'neo4j'),             # Neo4j
            ('parser', 'parser'),           # Parser
        ]
        
        # Switches
        switches = [
            ('s1', 'switch'),  # Switch ThingsBoard
            ('s2', 'switch'),  # Switch Middleware
        ]
        
        # Adicionar switches dos simuladores
        sim_switches = []
        for i in range(self.num_sims):
            sw_name = f's{i+3}'
            switches.append((sw_name, 'switch'))
            sim_switches.append(sw_name)
        
        # Simuladores
        simulators = []
        for i in range(1, self.num_sims + 1):
            sim_name = f'sim_{i:03d}'
            nodes.append((sim_name, 'sim'))
            simulators.append(sim_name)
        
        # Adicionar todos os nós ao grafo
        for node, node_type in nodes + switches:
            self.graph.add_node(node, type=node_type)
        
        # Links principais
        main_links = [
            ('c0', 's1'),      # Controller para switch principal
            ('tb', 's1'),      # ThingsBoard
            ('middts', 's2'),  # Middleware
            ('s1', 's2'),      # Interconexão switches principais
        ]
        
        # Links dos serviços para os switches
        service_links = [
            ('db', 's1'),      # PostgreSQL para ambos switches
            ('db', 's2'),
            ('influxdb', 's2'), # InfluxDB para middleware e simuladores
            ('neo4j', 's2'),   # Neo4j apenas para middleware
            ('parser', 's2'),  # Parser apenas para middleware
        ]
        
        # Links dos simuladores
        sim_links = []
        for i, (sim, sw) in enumerate(zip(simulators, sim_switches)):
            sim_links.extend([
                (sim, sw),          # Simulador para seu switch
                (sw, 's1'),         # Switch do simulador para switch principal
                ('db', sw),         # Alguns simuladores podem acessar DB
                ('influxdb', sw),   # InfluxDB para todos os simuladores
            ])
        
        # Adicionar todas as arestas
        for src, dst in main_links + service_links + sim_links:
            if src in [n[0] for n in nodes + switches] and dst in [n[0] for n in nodes + switches]:
                self.graph.add_edge(src, dst)
    
    def calculate_positions(self):
        """Calcula posições otimizadas para os nós"""
        
        # Posições fixas para nós principais
        fixed_positions = {
            'c0': (0, 2),           # Controller no topo
            'tb': (-2, 0),          # ThingsBoard à esquerda
            'middts': (2, 0),       # Middleware à direita
            's1': (-1, 0.5),        # Switch TB
            's2': (1, 0.5),         # Switch Middleware
            'db': (0, 1),           # PostgreSQL no centro-superior
            'influxdb': (3, 1),     # InfluxDB à direita
            'neo4j': (1, 1.5),      # Neo4j acima do middleware
            'parser': (2, -1),      # Parser abaixo do middleware
        }
        
        # Use spring layout para posicionamento inicial
        pos = nx.spring_layout(self.graph, k=2, iterations=50, seed=42)
        
        # Aplicar posições fixas
        for node, position in fixed_positions.items():
            if node in pos:
                pos[node] = position
        
        # Posicionar simuladores em arco
        sim_nodes = [n for n in self.graph.nodes() if n.startswith('sim_')]
        if sim_nodes:
            import math
            radius = 4
            angle_step = 2 * math.pi / len(sim_nodes)
            
            for i, sim in enumerate(sorted(sim_nodes)):
                angle = i * angle_step - math.pi/2  # Começar do topo
                x = radius * math.cos(angle)
                y = radius * math.sin(angle) - 2  # Mover para baixo
                pos[sim] = (x, y)
        
        # Posicionar switches dos simuladores próximos aos simuladores
        for i in range(self.num_sims):
            sw = f's{i+3}'
            sim = f'sim_{i+1:03d}'
            if sw in pos and sim in pos:
                # Colocar switch entre simulador e centro
                sim_pos = pos[sim]
                center = (0, 0)
                # Mover switch 30% do caminho do simulador para o centro
                pos[sw] = (
                    sim_pos[0] * 0.7 + center[0] * 0.3,
                    sim_pos[1] * 0.7 + center[1] * 0.3
                )
        
        self.positions = pos
    
    def draw_network_diagram(self, title="Topologia Containernet - Condomínio Scenario"):
        """Desenha o diagrama principal da rede"""
        
        fig, ax = plt.subplots(figsize=FIGSIZE, dpi=DPI)
        
        # Preparar dados para desenho
        node_colors = []
        node_sizes = []
        node_labels = {}
        
        for node in self.graph.nodes():
            node_data = self.graph.nodes[node]
            node_type = node_data.get('type', 'sim')
            
            node_colors.append(COLORS.get(node_type, COLORS['sim']))
            node_sizes.append(SIZES.get(node_type, SIZES['sim']))
            
            # Labels customizados
            if node.startswith('sim_'):
                node_labels[node] = f"SIM\n{node[-3:]}"
            elif node.startswith('s') and len(node) <= 3:
                node_labels[node] = f"SW\n{node[1:]}"
            else:
                node_labels[node] = node.upper()
        
        # Desenhar nós
        nx.draw_networkx_nodes(
            self.graph, self.positions,
            node_color=node_colors,
            node_size=node_sizes,
            alpha=0.9,
            ax=ax
        )
        
        # Desenhar arestas com diferentes estilos
        edge_lists = {
            'main': [],      # Links principais
            'service': [],   # Links de serviços
            'sim': []        # Links de simuladores
        }
        
        for edge in self.graph.edges():
            src, dst = edge
            if (src in ['c0', 'tb', 'middts', 's1', 's2'] and 
                dst in ['c0', 'tb', 'middts', 's1', 's2']):
                edge_lists['main'].append(edge)
            elif (src in ['db', 'influxdb', 'neo4j', 'parser'] or 
                  dst in ['db', 'influxdb', 'neo4j', 'parser']):
                edge_lists['service'].append(edge)
            else:
                edge_lists['sim'].append(edge)
        
        # Desenhar diferentes tipos de arestas
        nx.draw_networkx_edges(
            self.graph, self.positions,
            edgelist=edge_lists['main'],
            edge_color='#2C3E50', width=3, alpha=0.8, ax=ax
        )
        
        nx.draw_networkx_edges(
            self.graph, self.positions,
            edgelist=edge_lists['service'],
            edge_color='#E74C3C', width=2, alpha=0.7, ax=ax
        )
        
        nx.draw_networkx_edges(
            self.graph, self.positions,
            edgelist=edge_lists['sim'],
            edge_color='#BDC3C7', width=1, alpha=0.6, ax=ax
        )
        
        # Desenhar labels
        nx.draw_networkx_labels(
            self.graph, self.positions,
            labels=node_labels,
            font_size=8, font_weight='bold',
            ax=ax
        )
        
        # Adicionar informações da rede
        info_text = (
            f"Simuladores: {self.num_sims}\n"
            f"Switches: {len([n for n in self.graph.nodes() if self.graph.nodes[n].get('type') == 'switch'])}\n"
            f"Serviços: {len([n for n in self.graph.nodes() if self.graph.nodes[n].get('type') not in ['switch', 'sim', 'controller']])}\n"
            f"Total de nós: {self.graph.number_of_nodes()}\n"
            f"Total de links: {self.graph.number_of_edges()}"
        )
        
        ax.text(0.02, 0.98, info_text, transform=ax.transAxes, 
                verticalalignment='top', fontsize=10,
                bbox=dict(boxstyle="round,pad=0.3", facecolor="lightgray", alpha=0.8))
        
        # Criar legenda
        legend_elements = [
            Line2D([0], [0], marker='o', color='w', label='ThingsBoard/Middleware',
                   markerfacecolor=COLORS['main'], markersize=12),
            Line2D([0], [0], marker='o', color='w', label='PostgreSQL',
                   markerfacecolor=COLORS['db'], markersize=10),
            Line2D([0], [0], marker='o', color='w', label='InfluxDB',
                   markerfacecolor=COLORS['influx'], markersize=9),
            Line2D([0], [0], marker='o', color='w', label='Neo4j',
                   markerfacecolor=COLORS['neo4j'], markersize=9),
            Line2D([0], [0], marker='o', color='w', label='Parser',
                   markerfacecolor=COLORS['parser'], markersize=8),
            Line2D([0], [0], marker='o', color='w', label='Switches',
                   markerfacecolor=COLORS['switch'], markersize=7),
            Line2D([0], [0], marker='o', color='w', label='Simuladores',
                   markerfacecolor=COLORS['sim'], markersize=6),
            Line2D([0], [0], marker='o', color='w', label='Controller',
                   markerfacecolor=COLORS['controller'], markersize=10),
        ]
        
        ax.legend(handles=legend_elements, loc='upper right', bbox_to_anchor=(0.98, 0.98))
        
        ax.set_title(title, fontsize=16, fontweight='bold', pad=20)
        ax.axis('off')
        plt.tight_layout()
        
        return fig
    
    def draw_hierarchical_view(self):
        """Desenha uma visão hierárquica da topologia"""
        
        fig, ax = plt.subplots(figsize=(14, 10), dpi=DPI)
        
        # Criar grafo hierárquico
        hier_graph = nx.DiGraph()
        
        # Níveis hierárquicos
        levels = {
            0: ['c0'],  # Controller
            1: ['tb', 'middts'],  # Aplicações principais
            2: ['s1', 's2'],  # Switches principais
            3: ['db', 'influxdb', 'neo4j', 'parser'],  # Serviços
            4: [f's{i+3}' for i in range(self.num_sims)],  # Switches simuladores
            5: [f'sim_{i+1:03d}' for i in range(self.num_sims)]  # Simuladores
        }
        
        # Calcular posições hierárquicas
        hier_pos = {}
        for level, nodes in levels.items():
            y = -level  # Níveis descendentes
            for i, node in enumerate(nodes):
                x = (i - len(nodes)/2 + 0.5) * 2  # Espaçamento horizontal
                hier_pos[node] = (x, y)
        
        # Adicionar nós e arestas ao grafo hierárquico
        for level_nodes in levels.values():
            for node in level_nodes:
                if node in self.graph.nodes():
                    hier_graph.add_node(node, type=self.graph.nodes[node].get('type', 'sim'))
        
        # Adicionar arestas hierárquicas principais
        hier_edges = [
            ('c0', 's1'), ('c0', 's2'),
            ('tb', 's1'), ('middts', 's2'),
            ('s1', 'db'), ('s2', 'db'),
            ('s2', 'influxdb'), ('s2', 'neo4j'), ('s2', 'parser')
        ]
        
        for src, dst in hier_edges:
            if src in hier_graph.nodes() and dst in hier_graph.nodes():
                hier_graph.add_edge(src, dst)
        
        # Conectar simuladores aos seus switches
        for i in range(self.num_sims):
            sim = f'sim_{i+1:03d}'
            sw = f's{i+3}'
            if sim in hier_graph.nodes() and sw in hier_graph.nodes():
                hier_graph.add_edge(sw, sim)
                hier_graph.add_edge(sw, 's1')  # Conectar à rede principal
        
        # Desenhar nós
        for level, nodes in levels.items():
            level_nodes = [n for n in nodes if n in hier_graph.nodes()]
            if level_nodes:
                node_colors = [COLORS.get(hier_graph.nodes[n].get('type', 'sim'), COLORS['sim']) 
                              for n in level_nodes]
                node_sizes = [SIZES.get(hier_graph.nodes[n].get('type', 'sim'), SIZES['sim']) * 0.8 
                             for n in level_nodes]
                level_pos = {n: hier_pos[n] for n in level_nodes}
                
                nx.draw_networkx_nodes(
                    hier_graph, level_pos,
                    nodelist=level_nodes,
                    node_color=node_colors,
                    node_size=node_sizes,
                    alpha=0.9, ax=ax
                )
        
        # Desenhar arestas
        nx.draw_networkx_edges(
            hier_graph, hier_pos,
            edge_color='gray', arrows=True, arrowsize=20,
            width=1.5, alpha=0.7, ax=ax
        )
        
        # Labels
        node_labels = {}
        for node in hier_graph.nodes():
            if node.startswith('sim_'):
                node_labels[node] = f"S{node[-3:]}"
            elif node.startswith('s'):
                node_labels[node] = node.upper()
            else:
                node_labels[node] = node.upper()
        
        nx.draw_networkx_labels(
            hier_graph, hier_pos,
            labels=node_labels,
            font_size=8, font_weight='bold', ax=ax
        )
        
        # Adicionar labels de níveis
        level_labels = [
            "CONTROLLER", "APPLICATIONS", "CORE SWITCHES", 
            "SERVICES", "SIM SWITCHES", "SIMULATORS"
        ]
        
        for i, label in enumerate(level_labels[:len(levels)]):
            ax.text(-8, -i, label, fontsize=10, fontweight='bold',
                   verticalalignment='center',
                   bbox=dict(boxstyle="round,pad=0.3", facecolor="lightblue", alpha=0.7))
        
        ax.set_title("Visão Hierárquica da Topologia", fontsize=16, fontweight='bold', pad=20)
        ax.axis('off')
        plt.tight_layout()
        
        return fig
    
    def generate_network_stats(self):
        """Gera estatísticas da rede"""
        stats = {
            'timestamp': datetime.now().isoformat(),
            'total_nodes': self.graph.number_of_nodes(),
            'total_edges': self.graph.number_of_edges(),
            'simulators': self.num_sims,
            'node_types': {},
            'connectivity': {},
            'network_metrics': {}
        }
        
        # Contar tipos de nós
        for node in self.graph.nodes():
            node_type = self.graph.nodes[node].get('type', 'unknown')
            stats['node_types'][node_type] = stats['node_types'].get(node_type, 0) + 1
        
        # Métricas de conectividade
        stats['connectivity'] = {
            'average_degree': sum(dict(self.graph.degree()).values()) / self.graph.number_of_nodes(),
            'density': nx.density(self.graph),
            'is_connected': nx.is_connected(self.graph)
        }
        
        # Métricas de rede
        if nx.is_connected(self.graph):
            try:
                stats['network_metrics'] = {
                    'diameter': nx.diameter(self.graph),
                    'average_shortest_path': nx.average_shortest_path_length(self.graph),
                    'clustering_coefficient': nx.average_clustering(self.graph)
                }
            except Exception as e:
                stats['network_metrics'] = {'error': f'Erro ao calcular métricas: {str(e)}'}
        
        return stats
    
    def export_to_formats(self, base_filename="topology"):
        """Exporta a topologia em múltiplos formatos"""
        
        self.build_topology_graph()
        self.calculate_positions()
        
        outputs = []
        
        # 1. Diagrama principal PNG
        fig1 = self.draw_network_diagram()
        main_file = os.path.join(self.output_dir, f"{base_filename}_main.png")
        fig1.savefig(main_file, dpi=DPI, bbox_inches='tight')
        outputs.append(main_file)
        plt.close(fig1)
        
        # 2. Visão hierárquica PNG
        fig2 = self.draw_hierarchical_view()
        hier_file = os.path.join(self.output_dir, f"{base_filename}_hierarchical.png")
        fig2.savefig(hier_file, dpi=DPI, bbox_inches='tight')
        outputs.append(hier_file)
        plt.close(fig2)
        
        # 3. Arquivo GraphML para análise posterior
        graphml_file = os.path.join(self.output_dir, f"{base_filename}.graphml")
        nx.write_graphml(self.graph, graphml_file)
        outputs.append(graphml_file)
        
        # 4. Arquivo DOT para Graphviz
        dot_file = os.path.join(self.output_dir, f"{base_filename}.dot")
        nx.drawing.nx_pydot.write_dot(self.graph, dot_file)
        outputs.append(dot_file)
        
        # 5. Estatísticas JSON
        stats = self.generate_network_stats()
        stats_file = os.path.join(self.output_dir, f"{base_filename}_stats.json")
        with open(stats_file, 'w') as f:
            json.dump(stats, f, indent=2)
        outputs.append(stats_file)
        
        # 6. Gerar PDF com Graphviz (se disponível)
        try:
            pdf_file = os.path.join(self.output_dir, f"{base_filename}_graphviz.pdf")
            subprocess.run(['dot', '-Tpdf', dot_file, '-o', pdf_file], 
                          check=True, capture_output=True)
            outputs.append(pdf_file)
        except (subprocess.CalledProcessError, FileNotFoundError):
            print("Aviso: Graphviz não disponível para gerar PDF")
        
        return outputs

def main():
    parser = argparse.ArgumentParser(description='Visualizador de Topologia Containernet')
    parser.add_argument('--sims', type=int, default=5, 
                       help='Número de simuladores (padrão: 5)')
    parser.add_argument('--output', type=str, default='./topology_output',
                       help='Diretório de saída (padrão: ./topology_output)')
    parser.add_argument('--filename', type=str, default='condominio_topology',
                       help='Nome base dos arquivos (padrão: condominio_topology)')
    parser.add_argument('--show', action='store_true',
                       help='Mostrar gráficos na tela (requer display)')
    
    args = parser.parse_args()
    
    # Criar visualizador
    visualizer = TopologyVisualizer(num_sims=args.sims, output_dir=args.output)
    
    # Gerar todas as visualizações
    print(f"Gerando visualizações para {args.sims} simuladores...")
    outputs = visualizer.export_to_formats(args.filename)
    
    print(f"\nArquivos gerados em '{args.output}':")
    for output in outputs:
        print(f"  - {os.path.basename(output)}")
    
    # Mostrar estatísticas
    stats = visualizer.generate_network_stats()
    print(f"\nEstatísticas da Rede:")
    print(f"  - Total de nós: {stats['total_nodes']}")
    print(f"  - Total de links: {stats['total_edges']}")
    print(f"  - Densidade: {stats['connectivity']['density']:.3f}")
    print(f"  - Grau médio: {stats['connectivity']['average_degree']:.2f}")
    
    if args.show:
        # Mostrar visualizações
        visualizer.build_topology_graph()
        visualizer.calculate_positions()
        
        fig1 = visualizer.draw_network_diagram()
        fig2 = visualizer.draw_hierarchical_view()
        plt.show()

if __name__ == '__main__':
    main()
