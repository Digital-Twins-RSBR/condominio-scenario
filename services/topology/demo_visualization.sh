#!/bin/bash
# Script para demonstrar as capacidades de visualização de topologia

echo "=== Demonstração do Visualizador de Topologia ==="
echo

# Verificar se as dependências estão instaladas
echo "1. Verificando dependências..."
python3 -c "import networkx, matplotlib; print('✓ NetworkX e Matplotlib instalados')" 2>/dev/null || {
    echo "❌ Dependências não encontradas. Instalando..."
    sudo apt update && sudo apt install -y python3-networkx python3-matplotlib python3-pydot graphviz
}

cd /home/ubuntu/projects/condominio-scenario/services/topology

# Gerar visualizações com diferentes números de simuladores
echo
echo "2. Gerando visualizações para diferentes configurações..."

for sims in 3 5 10; do
    echo "   → Configuração com $sims simuladores..."
    python3 topology_visualizer.py --sims $sims --output "./demo_output_${sims}sims" --filename "topology_${sims}sims"
done

echo
echo "3. Gerando relatórios HTML..."
for sims in 3 5 10; do
    python3 live_topology_capture.py --report --output "./demo_output_${sims}sims"
done

echo
echo "=== Resultados Gerados ==="
echo "Os seguintes diretórios foram criados com as visualizações:"
for sims in 3 5 10; do
    echo "  - ./demo_output_${sims}sims/"
    echo "    ├── topology_${sims}sims_main.png          (Diagrama principal)"
    echo "    ├── topology_${sims}sims_hierarchical.png  (Visão hierárquica)"
    echo "    ├── topology_${sims}sims.graphml           (Formato GraphML)"
    echo "    ├── topology_${sims}sims.dot               (Formato DOT)"
    echo "    ├── topology_${sims}sims_stats.json        (Estatísticas)"
    echo "    ├── topology_${sims}sims_graphviz.pdf      (PDF via Graphviz)"
    echo "    └── topology_report.html                   (Relatório HTML)"
done

echo
echo "=== Como visualizar ==="
echo "1. Para abrir relatórios HTML no browser:"
echo "   firefox ./demo_output_5sims/topology_report.html"
echo
echo "2. Para visualizar imagens PNG:"
echo "   eog ./demo_output_5sims/topology_5sims_main.png"
echo
echo "3. Para analisar no Gephi (software de análise de redes):"
echo "   Abra o arquivo .graphml no Gephi"
echo
echo "4. Para usar o visualizador durante a simulação:"
echo "   python3 topo_qos.py --sims 5 --visualize"
echo
echo "=== Arquivos de exemplo criados em: ==="
ls -la demo_output_*/ 2>/dev/null | head -20

echo
echo "✓ Demonstração concluída!"
