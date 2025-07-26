from mininet.topo import Topo
from mininet.net import Mininet
from mininet.link import TCLink
from mininet.cli import CLI

class SimpleTBTopo(Topo):
    def build(self):
        s1 = self.addSwitch('s1')
        sim = self.addHost('sim', ip='10.0.0.1/24')
        middts = self.addHost('middts', ip='10.0.0.2/24')
        tb = self.addHost('tb', ip='10.0.0.3/24')
        self.addLink(sim, s1)
        self.addLink(middts, s1)
        self.addLink(tb, s1)

if __name__ == '__main__':
    topo = SimpleTBTopo()
    net = Mininet(topo=topo, controller=None, link=TCLink)
    net.addController('c0')
    net.start()
    print("\n[Mininet iniciado]")
    print("Hosts disponíveis: sim, middts, tb")
    print("Para instalar o ThingsBoard, use: tb ./install_thingsboard_in_namespace.sh")
    CLI(net)
    net.stop()
