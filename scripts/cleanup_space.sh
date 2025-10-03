#!/bin/bash

# 🧹 Script de limpeza de espaço para cenário longo
# Remove imagens, volumes e containers orfãos com segurança

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧹 LIMPEZA DE ESPAÇO DOCKER${NC}"
echo -e "${BLUE}============================${NC}"
echo ""

# Verificar espaço antes
echo -e "${YELLOW}📊 Espaço ANTES da limpeza:${NC}"
docker system df
echo ""

# 1. Identificar containers ativos
echo -e "${YELLOW}🔍 Verificando containers ativos...${NC}"
ACTIVE_CONTAINERS=$(docker ps --format "{{.Names}}" | tr '\n' ' ')
echo -e "   Containers ativos: ${GREEN}${ACTIVE_CONTAINERS}${NC}"
echo ""

# 2. Remover imagens órfãs (tagged com <none>)
echo -e "${YELLOW}🗑️  Removendo imagens órfãs...${NC}"
DANGLING_IMAGES=$(docker images -f "dangling=true" -q)
if [ -n "$DANGLING_IMAGES" ]; then
    echo "   Encontradas $(echo $DANGLING_IMAGES | wc -w) imagens órfãs"
    docker rmi $DANGLING_IMAGES 2>/dev/null || echo "   Algumas imagens não puderam ser removidas (em uso)"
    echo -e "   ${GREEN}✅ Imagens órfãs removidas${NC}"
else
    echo -e "   ${GREEN}✅ Nenhuma imagem órfã encontrada${NC}"
fi
echo ""

# 3. Remover containers parados (exceto os importantes)
echo -e "${YELLOW}🗑️  Removendo containers parados...${NC}"
STOPPED_CONTAINERS=$(docker ps -a -f "status=exited" --format "{{.Names}}" | grep -v -E "^(mn\.|tb|influx|neo4j|postgres)" || true)
if [ -n "$STOPPED_CONTAINERS" ]; then
    echo "   Containers parados para remoção:"
    echo "$STOPPED_CONTAINERS" | sed 's/^/      /'
    echo "$STOPPED_CONTAINERS" | xargs docker rm 2>/dev/null || echo "   Alguns containers não puderam ser removidos"
    echo -e "   ${GREEN}✅ Containers parados removidos${NC}"
else
    echo -e "   ${GREEN}✅ Nenhum container parado para remover${NC}"
fi
echo ""

# 4. Listar volumes grandes
echo -e "${YELLOW}📁 Verificando volumes grandes...${NC}"
echo "   Volumes principais:"
for vol in influx_data tb_db_data neo4j_data db_data; do
    if docker volume ls --format "{{.Name}}" | grep -q "^${vol}$"; then
        SIZE=$(docker volume inspect $vol --format "{{.Mountpoint}}" | xargs du -sh 2>/dev/null | cut -f1 || echo "N/A")
        echo -e "      $vol: ${GREEN}$SIZE${NC}"
    fi
done
echo ""

# 5. Listar volumes órfãos
echo -e "${YELLOW}🔍 Verificando volumes órfãos...${NC}"
# Lista todos os volumes
ALL_VOLUMES=$(docker volume ls --format "{{.Name}}")
# Lista volumes em uso
USED_VOLUMES=$(docker ps -a --format "{{.Mounts}}" | tr ',' '\n' | grep -o '[a-f0-9]\{64\}' | sort -u || true)

ORPHAN_COUNT=0
echo "   Analisando $(echo "$ALL_VOLUMES" | wc -l) volumes..."

# Contar volumes órfãos (não vamos listar todos para não encher a tela)
for vol in $ALL_VOLUMES; do
    # Pular volumes importantes
    if echo "$vol" | grep -qE "^(influx_data|tb_db_data|neo4j_data|db_data|influx_logs|tb_logs|neo4j_logs|parser_logs|tb_assets)$"; then
        continue
    fi
    
    # Verificar se não está em uso
    if ! echo "$USED_VOLUMES" | grep -q "$vol"; then
        ORPHAN_COUNT=$((ORPHAN_COUNT + 1))
    fi
done

if [ $ORPHAN_COUNT -gt 0 ]; then
    echo -e "   ${YELLOW}⚠️  Encontrados $ORPHAN_COUNT volumes órfãos${NC}"
    echo -e "   ${YELLOW}💡 Execute: docker volume prune${NC}"
else
    echo -e "   ${GREEN}✅ Nenhum volume órfão detectado${NC}"
fi
echo ""

# 6. Verificar espaço após limpeza básica
echo -e "${YELLOW}📊 Espaço APÓS limpeza básica:${NC}"
docker system df
echo ""

# 7. Sugestões de limpeza adicional
AVAILABLE_GB=$(df /var | tail -1 | awk '{print int($4/1024/1024)}')
echo -e "${BLUE}💡 SUGESTÕES PARA LIBERAR MAIS ESPAÇO:${NC}"
echo ""

if [ $ORPHAN_COUNT -gt 0 ]; then
    echo -e "${YELLOW}1. Remover volumes órfãos:${NC}"
    echo -e "   ${YELLOW}docker volume prune -f${NC}"
    echo -e "   Economia estimada: ~$(($ORPHAN_COUNT * 10))MB"
    echo ""
fi

echo -e "${YELLOW}2. Limpar build cache:${NC}"
echo -e "   ${YELLOW}docker builder prune -f${NC}"
echo ""

echo -e "${YELLOW}3. Limpar imagens antigas não utilizadas:${NC}"
echo -e "   ${YELLOW}docker image prune -a -f${NC}"
echo -e "   ⚠️  Cuidado: Remove TODAS as imagens não utilizadas"
echo ""

echo -e "${YELLOW}4. Limpeza completa (PERIGOSO):${NC}"
echo -e "   ${YELLOW}docker system prune -a -f --volumes${NC}"
echo -e "   ⚠️  CUIDADO: Remove tudo não utilizado"
echo ""

# 8. Status final
echo -e "${BLUE}📋 RESUMO:${NC}"
echo -e "   • Espaço disponível: ${GREEN}${AVAILABLE_GB}GB${NC}"
echo -e "   • InfluxDB: ${GREEN}$(docker volume inspect influx_data --format "{{.Mountpoint}}" | xargs du -sh 2>/dev/null | cut -f1 || echo "N/A")${NC}"

if [ $AVAILABLE_GB -gt 10 ]; then
    echo -e "   • Status: ${GREEN}✅ Espaço suficiente para teste de 8h${NC}"
else
    echo -e "   • Status: ${RED}⚠️  Considere liberar mais espaço${NC}"
fi

echo ""
echo -e "${GREEN}🧹 Limpeza básica concluída!${NC}"