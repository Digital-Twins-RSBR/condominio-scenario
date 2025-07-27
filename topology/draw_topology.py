#!/usr/bin/env python3
import networkx as nx
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D

def build_graph(num_sims=5):
    G = nx.MultiGraph()
    G.add_node('tb', type='main')
    G.add_node('middts', type='main')
    G.add_node('s1', type='main')
    G.add_node('s2', type='main')
    G.add_edge('tb', 's1')
    G.add_edge('middts', 's2')
    G.add_edge('s1', 's2')
    for i in range(1, num_sims + 1):
        sim = f'sim_{i:03d}'
        sw = f's{i+2}'
        G.add_node(sim, type='sim')
        G.add_node(sw, type='sw')
        G.add_edge(sim, sw)
        G.add_edge(sw, 's1', label='10Mbps/2ms')
        G.add_edge(sw, 's1', label='5Mbps/20ms')
        G.add_edge(sw, 's1', label='1Mbps/50ms/5%loss')
    return G

if __name__ == "__main__":
    num_sims = 5
    G = build_graph(num_sims)
    pos = nx.spring_layout(G, seed=42)
    pos['tb'] = [-0.5, 0.0]
    pos['middts'] = [0.5, 0.0]
    pos['s1'] = [0.0, 0.2]
    pos['s2'] = [0.0, -0.2]

    # Desenhar nós principais, switches e simuladores com tamanhos diferentes
    node_sizes = []
    node_colors = []
    for n in G.nodes(data=True):
        if n[1].get('type') == 'main':
            node_sizes.append(700)
            node_colors.append('tab:blue')
        elif n[1].get('type') == 'sw':
            node_sizes.append(400)
            node_colors.append('tab:gray')
        else:
            node_sizes.append(200)
            node_colors.append('tab:orange')
    nx.draw_networkx_nodes(G, pos, node_size=node_sizes, node_color=node_colors)
    nx.draw_networkx_labels(G, pos, font_size=8)

    # Desenhar arestas principais
    nx.draw_networkx_edges(G, pos, edgelist=[('tb','s1'), ('middts','s2'), ('s1','s2')], width=2, edge_color='gray')

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
        Line2D([0], [0], marker='o', color='w', label='ThingsBoard/MidDiTS', markerfacecolor='tab:blue', markersize=10),
        Line2D([0], [0], marker='o', color='w', label='Switch', markerfacecolor='tab:gray', markersize=7),
        Line2D([0], [0], marker='o', color='w', label='Simulador', markerfacecolor='tab:orange', markersize=5)
    ]
    plt.legend(handles=legend_elements, loc='best')
    plt.title("Containernet Topology (MultiGraph)")
    plt.savefig("topologia.png", dpi=200, bbox_inches='tight')
    plt.show()