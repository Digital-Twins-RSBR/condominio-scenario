#!/usr/bin/env python3
"""
Integração do visualizador com topo_qos.py
Captura a topologia em tempo real durante a execução do Mininet
"""

import os
import sys
import json
import time
import subprocess
from datetime import datetime

# Adicionar o caminho do visualizador
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.append(current_dir)

try:
    from topology_visualizer import TopologyVisualizer
    # Importar topo_qos apenas se necessário
    MININET_AVAILABLE = False
    try:
        from topo_qos import run_topo
        MININET_AVAILABLE = True
    except ImportError:
        pass
except ImportError as e:
    print(f"Erro ao importar módulos: {e}")
    print("Certifique-se de que os arquivos estão no diretório correto")
    sys.exit(1)

def capture_live_topology(net, output_dir="./live_topology"):
    """
    Captura a topologia ativa do Mininet e gera visualizações
    
    Args:
        net: Instância do Containernet
        output_dir: Diretório para salvar as visualizações
    """
    
    # Criar diretório de saída
    os.makedirs(output_dir, exist_ok=True)
    
    # Extrair informações da rede ativa
    nodes_info = {}
    links_info = []
    
    # Capturar nós
    for node in net.hosts + net.switches + net.controllers:
        node_name = node.name
        
        # Determinar tipo do nó
        if hasattr(node, 'dimage'):  # Container Docker
            if 'postgres' in node.dimage:
                node_type = 'db'
            elif 'influx' in node.dimage:
                node_type = 'influx'
            elif 'neo4j' in node.dimage:
                node_type = 'neo4j'
            elif 'parser' in node.dimage:
                node_type = 'parser'
            elif 'tb-node' in node.dimage:
                node_type = 'main'
            elif 'middts' in node.dimage:
                node_type = 'main'
            elif 'iot_simulator' in node.dimage:
                node_type = 'sim'
            else:
                node_type = 'main'
        elif 'controller' in node_name.lower():
            node_type = 'controller'
        elif node_name.startswith('s'):
            node_type = 'switch'
        else:
            node_type = 'sim'
            
        nodes_info[node_name] = {
            'type': node_type,
            'ips': [],
            'interfaces': []
        }
        
        # Capturar IPs e interfaces
        if hasattr(node, 'intfList'):
            for intf in node.intfList():
                if intf.IP():
                    nodes_info[node_name]['ips'].append(intf.IP())
                nodes_info[node_name]['interfaces'].append(intf.name)
    
    # Capturar links
    for link in net.links:
        intf1, intf2 = link.intf1, link.intf2
        node1, node2 = intf1.node.name, intf2.node.name
        
        link_info = {
            'source': node1,
            'target': node2,
            'interface1': intf1.name,
            'interface2': intf2.name,
            'bandwidth': getattr(link, 'bw', None),
            'delay': getattr(link, 'delay', None),
            'loss': getattr(link, 'loss', None)
        }
        links_info.append(link_info)
    
    # Criar arquivo de topologia
    topology_data = {
        'timestamp': datetime.now().isoformat(),
        'nodes': nodes_info,
        'links': links_info,
        'total_nodes': len(nodes_info),
        'total_links': len(links_info)
    }
    
    # Salvar dados da topologia
    topology_file = os.path.join(output_dir, 'live_topology.json')
    with open(topology_file, 'w') as f:
        json.dump(topology_data, f, indent=2)
    
    # Gerar visualizações usando o visualizador
    num_sims = len([n for n in nodes_info.keys() if n.startswith('sim_')])
    visualizer = TopologyVisualizer(num_sims=num_sims, output_dir=output_dir)
    
    # Construir grafo baseado nos dados capturados
    visualizer.build_topology_graph()
    
    # Sobrescrever com dados reais se necessário
    for node, info in nodes_info.items():
        if node in visualizer.graph.nodes():
            visualizer.graph.nodes[node]['type'] = info['type']
            visualizer.graph.nodes[node]['ips'] = info['ips']
    
    # Gerar visualizações
    outputs = visualizer.export_to_formats('live_topology')
    
    print(f"\n[VISUALIZER] Topologia capturada e visualizações geradas:")
    print(f"[VISUALIZER] Diretório: {output_dir}")
    for output in outputs:
        print(f"[VISUALIZER]   - {os.path.basename(output)}")
    
    return topology_file, outputs

def monitor_topology_changes(net, output_dir="./topology_monitoring", interval=30):
    """
    Monitora mudanças na topologia e gera visualizações periódicas
    
    Args:
        net: Instância do Containernet
        output_dir: Diretório para salvar monitoramento
        interval: Intervalo em segundos entre capturas
    """
    
    os.makedirs(output_dir, exist_ok=True)
    
    print(f"[MONITOR] Iniciando monitoramento da topologia (intervalo: {interval}s)")
    print(f"[MONITOR] Pressione Ctrl+C para parar")
    
    try:
        counter = 0
        while True:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            snapshot_dir = os.path.join(output_dir, f"snapshot_{timestamp}")
            
            print(f"[MONITOR] Captura #{counter + 1} - {timestamp}")
            capture_live_topology(net, snapshot_dir)
            
            counter += 1
            time.sleep(interval)
            
    except KeyboardInterrupt:
        print(f"\n[MONITOR] Monitoramento interrompido. Total de capturas: {counter}")

def generate_topology_report(topology_dir="./topology_output"):
    """
    Gera um relatório HTML com todas as visualizações
    """
    
    if not os.path.exists(topology_dir):
        print(f"Diretório não encontrado: {topology_dir}")
        return
    
    html_content = f"""
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Relatório de Topologia - Condomínio Scenario</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }}
        .container {{ max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
        h1 {{ color: #2c3e50; text-align: center; }}
        h2 {{ color: #34495e; border-bottom: 2px solid #3498db; padding-bottom: 10px; }}
        .topology-section {{ margin: 30px 0; }}
        .image-container {{ text-align: center; margin: 20px 0; }}
        .image-container img {{ max-width: 100%; height: auto; border: 1px solid #ddd; border-radius: 4px; }}
        .stats {{ background: #ecf0f1; padding: 15px; border-radius: 4px; margin: 15px 0; }}
        .file-list {{ background: #f8f9fa; padding: 15px; border-radius: 4px; }}
        .file-list ul {{ list-style-type: none; padding: 0; }}
        .file-list li {{ padding: 5px 0; border-bottom: 1px solid #dee2e6; }}
        .timestamp {{ color: #7f8c8d; font-style: italic; }}
    </style>
</head>
<body>
    <div class="container">
        <h1>Relatório de Topologia</h1>
        <h2>Condomínio Scenario - Containernet Simulation</h2>
        
        <div class="timestamp">
            Gerado em: {datetime.now().strftime("%d/%m/%Y às %H:%M:%S")}
        </div>
        
        <div class="topology-section">
            <h2>Diagrama Principal da Rede</h2>
            <div class="image-container">
                <img src="condominio_topology_main.png" alt="Topologia Principal" />
            </div>
            <p>Este diagrama mostra a topologia completa da simulação, incluindo todos os nós, switches e suas interconexões.</p>
        </div>
        
        <div class="topology-section">
            <h2>Visão Hierárquica</h2>
            <div class="image-container">
                <img src="condominio_topology_hierarchical.png" alt="Visão Hierárquica" />
            </div>
            <p>Esta visualização apresenta a arquitetura em camadas, facilitando o entendimento dos diferentes níveis da infraestrutura.</p>
        </div>
        
        <div class="topology-section">
            <h2>Estatísticas da Rede</h2>
            <div class="stats" id="network-stats">
                Carregando estatísticas...
            </div>
        </div>
        
        <div class="topology-section">
            <h2>Arquivos Gerados</h2>
            <div class="file-list">
                <ul>
                    <li>📊 <strong>condominio_topology_main.png</strong> - Diagrama principal</li>
                    <li>📈 <strong>condominio_topology_hierarchical.png</strong> - Visão hierárquica</li>
                    <li>📄 <strong>condominio_topology.graphml</strong> - Formato GraphML para análise</li>
                    <li>🔗 <strong>condominio_topology.dot</strong> - Formato DOT (Graphviz)</li>
                    <li>📋 <strong>condominio_topology_stats.json</strong> - Estatísticas detalhadas</li>
                    <li>📑 <strong>condominio_topology_graphviz.pdf</strong> - PDF gerado pelo Graphviz</li>
                </ul>
            </div>
        </div>
    </div>
    
    <script>
        // Carregar estatísticas do arquivo JSON
        fetch('condominio_topology_stats.json')
            .then(response => response.json())
            .then(data => {{
                const statsDiv = document.getElementById('network-stats');
                statsDiv.innerHTML = `
                    <h3>Métricas Gerais</h3>
                    <p><strong>Total de Nós:</strong> ${{data.total_nodes}}</p>
                    <p><strong>Total de Links:</strong> ${{data.total_edges}}</p>
                    <p><strong>Simuladores:</strong> ${{data.simulators}}</p>
                    <p><strong>Densidade da Rede:</strong> ${{data.connectivity.density.toFixed(3)}}</p>
                    <p><strong>Grau Médio:</strong> ${{data.connectivity.average_degree.toFixed(2)}}</p>
                    <p><strong>Rede Conectada:</strong> ${{data.connectivity.is_connected ? 'Sim' : 'Não'}}</p>
                    
                    <h3>Tipos de Nós</h3>
                    ${{Object.entries(data.node_types).map(([type, count]) => `<p><strong>${{type}}:</strong> ${{count}}</p>`).join('')}}
                `;
            }})
            .catch(error => {{
                document.getElementById('network-stats').innerHTML = 'Erro ao carregar estatísticas.';
            }});
    </script>
</body>
</html>
    """
    
    report_file = os.path.join(topology_dir, 'topology_report.html')
    with open(report_file, 'w', encoding='utf-8') as f:
        f.write(html_content)
    
    print(f"Relatório HTML gerado: {report_file}")
    return report_file

if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Ferramentas de visualização de topologia')
    parser.add_argument('--sims', type=int, default=5, help='Número de simuladores')
    parser.add_argument('--output', type=str, default='./topology_output', help='Diretório de saída')
    parser.add_argument('--report', action='store_true', help='Gerar relatório HTML')
    parser.add_argument('--monitor', action='store_true', help='Modo monitoramento (experimental)')
    
    args = parser.parse_args()
    
    if args.report:
        generate_topology_report(args.output)
    elif args.monitor:
        print("Modo monitoramento requer integração com instância ativa do Mininet")
        print("Use esta funcionalidade dentro do script topo_qos.py")
    else:
        # Gerar visualização estática
        visualizer = TopologyVisualizer(num_sims=args.sims, output_dir=args.output)
        outputs = visualizer.export_to_formats('condominio_topology')
        
        print(f"Visualizações geradas em: {args.output}")
        for output in outputs:
            print(f"  - {os.path.basename(output)}")
        
        # Gerar relatório HTML
        generate_topology_report(args.output)
