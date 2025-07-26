from mininet.net import Containernet
from mininet.node import Controller, DockerHost
from mininet.link import TCLink
from mininet.topo import Topo
from mininet.cli import CLI
from mininet.log import setLogLevel

class SimpleContainernetTopo(Topo):
    def build(self):
        s1 = self.addSwitch("s1")
        tb = self.addDocker("tb", ip="10.0.0.1", dimage="thingsboard:latest")
        sim = self.addDocker("sim_001", ip="10.0.0.2", dimage="iot_simulator:latest")

        self.addLink(tb, s1)
        self.addLink(sim, s1)

if __name__ == '__main__':
    setLogLevel('info')
    net = Containernet(topo=SimpleContainernetTopo(), controller=Controller)
    net.start()
    CLI(net)
    net.stop()
