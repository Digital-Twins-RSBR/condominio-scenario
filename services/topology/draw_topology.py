#!/usr/bin/env python3
import networkx as nx
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D

def build_graph(num_sims=5):
    G = nx.MultiGraph()
    # Core services
    G.add_node('tb', type='main')
    G.add_node('middts', type='main')
    G.add_node('db', type='db')
    G.add_node('influxdb', type='influx')
    G.add_node('neo4j', type='neo4j')
    G.add_node('parser', type='parser')
    # Core switches
    G.add_node('s1', type='sw')
    G.add_node('s2', type='sw')

    # Core links
    G.add_edge('tb', 's1')
    G.add_edge('middts', 's2')
    G.add_edge('s1', 's2')

    # Links from core services to switches (match topo_qos.py)
    G.add_edge('db', 's1')
    G.add_edge('db', 's2')
    G.add_edge('influxdb', 's2')
    G.add_edge('neo4j', 's2')
    G.add_edge('parser', 's2')
    for i in range(1, num_sims + 1):
        sim = f'sim_{i:03d}'
        sw = f's{i+2}'
        G.add_node(sim, type='sim')
        G.add_node(sw, type='sw')
        G.add_edge(sim, sw)
    # Each simulator switch peers to the tb switch and the db/influx networks
    G.add_edge(sw, 's1', label='10Mbps/2ms')
    G.add_edge(sw, 's1', label='5Mbps/20ms')
    G.add_edge(sw, 's1', label='1Mbps/50ms/5%loss')
    G.add_edge('db', sw)
    G.add_edge('influxdb', sw)
    return G

if __name__ == "__main__":
    num_sims = 5
    G = build_graph(num_sims)
    pos = nx.spring_layout(G, seed=42)
    pos['tb'] = [-0.5, 0.0]
    pos['middts'] = [0.5, 0.0]
    pos['s1'] = [0.0, 0.2]
    pos['s2'] = [0.0, -0.2]
    # Additional core service positions
    pos['db'] = [0.0, 0.6]
    pos['influxdb'] = [0.5, 0.6]
    pos['neo4j'] = [-0.5, 0.6]
    pos['parser'] = [0.5, -0.6]

    # Desenhar nós principais, switches e simuladores com tamanhos diferentes
    node_sizes = []
    node_colors = []
    for n in G.nodes(data=True):
        t = n[1].get('type')
        if t == 'main':
            node_sizes.append(700)
            node_colors.append('tab:blue')
        elif t == 'sw':
            node_sizes.append(400)
            node_colors.append('tab:gray')
        elif t == 'sim':
            node_sizes.append(200)
            node_colors.append('tab:orange')
        elif t == 'db':
            node_sizes.append(650)
            node_colors.append('tab:red')
        elif t == 'influx':
            node_sizes.append(500)
            node_colors.append('tab:purple')
        elif t == 'neo4j':
            node_sizes.append(500)
            node_colors.append('saddlebrown')
        elif t == 'parser':
            node_sizes.append(350)
            node_colors.append('tab:cyan')
        else:
            node_sizes.append(200)
            node_colors.append('tab:orange')
    nx.draw_networkx_nodes(G, pos, node_size=node_sizes, node_color=node_colors)
    nx.draw_networkx_labels(G, pos, font_size=8)

    # Desenhar arestas principais
    core_edges = [('tb','s1'), ('middts','s2'), ('s1','s2'), ('db','s1'), ('db','s2'), ('influxdb','s2'), ('neo4j','s2'), ('parser','s2')]
    nx.draw_networkx_edges(G, pos, edgelist=core_edges, width=2, edge_color='gray')

    # Desenhar múltiplos links com curvaturas e cores diferentes
    color_map = {
        '10Mbps/2ms': ('tab:blue', 0.3),
        '5Mbps/20ms': ('tab:orange', 0.0),
        '1Mbps/50ms/5%loss': ('tab:green', -0.3)
    }
    for label, (color, rad) in color_map.items():
        edges = [(u, v) for u, v, d in G.edges(data=True) if d.get('label') == label]
        nx.draw_networkx_edges(G, pos, edgelist=edges, width=2, edge_color=color, connectionstyle=f'arc3,rad={rad}')

    # Legenda manual
    legend_elements = [
        Line2D([0], [0], color='tab:blue', lw=2, label='10Mbps/2ms'),
        Line2D([0], [0], color='tab:orange', lw=2, label='5Mbps/20ms'),
        Line2D([0], [0], color='tab:green', lw=2, label='1Mbps/50ms/5%loss'),
        Line2D([0], [0], marker='o', color='w', label='ThingsBoard', markerfacecolor='tab:blue', markersize=10),
        Line2D([0], [0], marker='o', color='w', label='middts', markerfacecolor='tab:blue', markersize=10),
        Line2D([0], [0], marker='o', color='w', label='Switch', markerfacecolor='tab:gray', markersize=7),
        Line2D([0], [0], marker='o', color='w', label='Simulador', markerfacecolor='tab:orange', markersize=5)
    ]
    # Serviços adicionais
    legend_elements += [
        Line2D([0], [0], marker='o', color='w', label='Postgres (db)', markerfacecolor='tab:red', markersize=9),
        Line2D([0], [0], marker='o', color='w', label='InfluxDB', markerfacecolor='tab:purple', markersize=8),
        Line2D([0], [0], marker='o', color='w', label='Neo4j', markerfacecolor='saddlebrown', markersize=8),
        Line2D([0], [0], marker='o', color='w', label='Parser', markerfacecolor='tab:cyan', markersize=7),
    ]
    plt.legend(handles=legend_elements, loc='best')
    plt.title("Containernet Topology (MultiGraph)")
    plt.savefig("topologia.png", dpi=200, bbox_inches='tight')
    plt.show()