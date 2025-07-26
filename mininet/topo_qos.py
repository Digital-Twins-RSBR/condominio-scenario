from mininet.topo import Topo
from mininet.link import TCLink
from mininet.net import Mininet
from mininet.node import Controller, Node
from mininet.log import setLogLevel
from mininet.cli import CLI

class QosTopo(Topo):
    def build(self, num_sims=100):
        # Switch central para comunicação
        switch_tb = self.addSwitch('s_tb')
        switch_middts = self.addSwitch('s_middts')

        # Adiciona ThingsBoard e MidDiTS
        host_tb = self.addHost('tb')
        host_middts = self.addHost('middts')

        self.addLink(host_tb, switch_tb)
        self.addLink(host_middts, switch_middts)

        # Conexão entre ThingsBoard e MidDiTS
        self.addLink(switch_tb, switch_middts, cls=TCLink, bw=100, delay='5ms')

        for i in range(1, num_sims + 1):
            host_name = f'sim_{i:03d}'
            switch_name = f's_{i:03d}'
            self.addSwitch(switch_name)
            self.addHost(host_name)
            self.addLink(host_name, switch_name)

            # 3 caminhos para o ThingsBoard via switch_tb
            self.addLink(switch_name, switch_tb, cls=TCLink, bw=10, delay='2ms', loss=0, max_queue_size=100, use_htb=True)  # URLLC
            self.addLink(switch_name, switch_tb, cls=TCLink, bw=5, delay='20ms', loss=0, max_queue_size=200, use_htb=True)  # eMBB
            self.addLink(switch_name, switch_tb, cls=TCLink, bw=1, delay='50ms', loss=5, max_queue_size=50, use_htb=True)   # Best Effort


if __name__ == '__main__':
    setLogLevel('info')
    topo = QosTopo(num_sims=100)
    net = Mininet(topo=topo, controller=Controller, link=TCLink, autoSetMacs=True, autoStaticArp=True)
    net.start()

    print("[INFO] Teste de conectividade:")
    net.pingAll()

    CLI(net)
    net.stop()
