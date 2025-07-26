#!/usr/bin/env python3
from mininet.topo import Topo
import pygraphviz as pgv

class DrawTopo(Topo):
    def build(self, num_sims=100):
        self.addSwitch("s_tb")
        self.addSwitch("s_md")
        self.addHost("tb")
        self.addHost("middts")
        self.addLink("tb", "s_tb")
        self.addLink("middts", "s_md")
        self.addLink("s_tb", "s_md")

        for i in range(1, num_sims + 1):
            h = f"sim_{i:03d}"
            sw = f"sw_{i:03d}"
            self.addHost(h)
            self.addSwitch(sw)
            self.addLink(h, sw)
            self.addLink(sw, "s_tb")
            self.addLink(sw, "s_tb")
            self.addLink(sw, "s_tb")

if __name__ == "__main__":
    from mininet.topo import Topo
    from mininet.util import dumpNodeConnections
    import matplotlib.pyplot as plt
    import networkx as nx

    topo = DrawTopo()
    G = nx.Graph()

    for node in topo.nodes():
        G.add_node(node)

    for src, dst, _ in topo.links(withKeys=True):
        G.add_edge(src, dst)

    nx.draw(G, with_labels=True, node_size=500, font_size=8)
    plt.title("Containernet Topology")
    plt.show()
