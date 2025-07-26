from mininet.topo import Topo

class QosTopo(Topo):
    def build(self, num_sims=100):
        switch_tb = self.addSwitch('s_tb')
        switch_middts = self.addSwitch('s_middts')
        host_tb = self.addHost('tb')
        host_middts = self.addHost('middts')
        self.addLink(host_tb, switch_tb)
        self.addLink(host_middts, switch_middts)
        self.addLink(switch_tb, switch_middts)

        for i in range(1, num_sims + 1):
            host_name = f'sim_{i:03d}'
            switch_name = f's{i:03d}'
            host = self.addHost(host_name)
            sw = self.addSwitch(switch_name)
            self.addLink(host, sw)
            self.addLink(sw, switch_tb)
            self.addLink(sw, switch_tb)
            self.addLink(sw, switch_tb)

if __name__ == '__main__':
    topo = QosTopo(num_sims=100)
    dot = 'graph G {\n'
    for node in topo.nodes():
        dot += f'  "{node}";\n'
    for src, dst in topo.links():
        dot += f'  "{src}" -- "{dst}";\n'
    dot += '}\n'
    with open('topology.dot', 'w') as f:
        f.write(dot)
    print("[✓] Arquivo topology.dot gerado.")

    #dot -Tpng topology.dot -o topology.png
    #xdg-open topology.png

