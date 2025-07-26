from mininet.net import Containernet
from mininet.node import Controller, DockerHost
from mininet.link import TCLink
from mininet.topo import Topo
from mininet.cli import CLI
from mininet.log import setLogLevel

class QosContainernetTopo(Topo):
    def build(self, num_sims=10):  # reduzido para teste inicial
        switch_tb = self.addSwitch('s_tb')
        switch_middts = self.addSwitch('s_middts')

        tb = self.addDocker('tb', ip='10.0.0.1', dimage="thingsboard:latest")
        middts = self.addDocker('middts', ip='10.0.0.2', dimage="middts:latest")

        self.addLink(tb, switch_tb)
        self.addLink(middts, switch_middts)
        self.addLink(switch_tb, switch_middts, cls=TCLink, bw=100, delay='5ms')

        for i in range(1, num_sims + 1):
            name = f'sim_{i:03d}'
            host = self.addDocker(name, dimage="iot_simulator:latest")
            switch = self.addSwitch(f's{i}')
            self.addLink(host, switch)
            self.addLink(switch, switch_tb, cls=TCLink, bw=10, delay='2ms')   # URLLC
            self.addLink(switch, switch_tb, cls=TCLink, bw=5, delay='20ms')   # eMBB
            self.addLink(switch, switch_tb, cls=TCLink, bw=1, delay='50ms', loss=5)  # Best Effort

if __name__ == '__main__':
    setLogLevel('info')
    net = Containernet(topo=QosContainernetTopo(num_sims=10), controller=Controller)
    net.start()
    CLI(net)
    net.stop()
