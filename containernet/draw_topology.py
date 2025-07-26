from mininet.topo import Topo
from mininet.topo import SingleSwitchTopo
from mininet.util import dumpNodeConnections
from mininet.log import setLogLevel
import networkx as nx
import matplotlib.pyplot as plt

def visualize_topology(topo):
    G = nx.Graph()

    for node in topo.nodes():
        G.add_node(node)

    for src, dst, _ in topo.links(sort=True, withKeys=True):
        G.add_edge(src, dst)

    nx.draw(G, with_labels=True, node_size=500, node_color='lightblue')
    plt.title("Network Topology")
    plt.show()

if __name__ == '__main__':
    setLogLevel('info')
    topo = SingleSwitchTopo(k=3)
    visualize_topology(topo)
