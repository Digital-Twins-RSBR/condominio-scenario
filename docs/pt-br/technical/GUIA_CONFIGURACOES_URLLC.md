# 🔧 GUIA DE CONFIGURAÇÕES URLLC - PROCEDIMENTOS OPERACIONAIS
===============================================================================

## 🎯 CONFIGURAÇÃO ÓTIMA IDENTIFICADA

### Sistema Vencedor:
- **Perfil:** `reduced_load`
- **Simuladores:** 5 ativos (mn.sim_001 até mn.sim_005)
- **Latências alcançadas:** S2M 69.4ms, M2S 184.0ms ✅
- **CPU ThingsBoard:** ~330% pico, ~172% médio

## 📋 PROCEDIMENTOS OPERACIONAIS

### 1. Aplicar Configuração Ótima (Método Hot-Swap)
```bash
# Aplicar perfil reduced_load sem reiniciar
make apply-profile CONFIG_PROFILE=reduced_load

# Reduzir simuladores para 5
for i in 006 007 008 009 010; do
    docker stop mn.sim_$i 2>/dev/null || true
done

# Verificar simuladores ativos
docker ps --format "{{.Names}}" | grep mn.sim
```

### 2. Executar Teste URLLC com Monitoramento
```bash
# Teste padrão 120s com monitoramento
make odte-monitored PROFILE=urllc DURATION=120

# Verificar se latências estão dentro da meta
# S2M e M2S devem estar <200ms
```

### 3. Verificação de Health Check
```bash
# Verificar CPU ThingsBoard (deve estar <350%)
docker stats mn.tb --no-stream

# Verificar conectividade simuladores
docker exec mn.sim_001 ping -c 1 10.0.0.11

# Verificar logs de erro
docker logs mn.tb --tail 50 | grep -i error
```

## ⚙️ CONFIGURAÇÕES DETALHADAS

### Perfil reduced_load.yml (ATIVO)
```yaml
# RPC Configuration
CLIENT_SIDE_RPC_TIMEOUT: 150

# HTTP Optimization  
HTTP_REQUEST_TIMEOUT_MS: 750
HTTP_MAX_CONNECTIONS: 200
HTTP_MAX_CONNECTIONS_PER_ROUTE: 50
HTTP_CONNECTION_TIMEOUT_MS: 500
HTTP_SOCKET_TIMEOUT_MS: 750

# Batch Processing
SQL_TS_BATCH_SIZE: 1500
SQL_TS_BATCH_MAX_DELAY_MS: 8
SQL_TS_LATEST_BATCH_SIZE: 750
SQL_TS_LATEST_BATCH_MAX_DELAY_MS: 4
SQL_TS_BATCH_THREADS: 3
SQL_TS_LATEST_BATCH_THREADS: 3

# Queue Optimization
TB_QUEUE_CORE_POLL_INTERVAL_MS: 10
TB_QUEUE_CORE_PARTITIONS: 8
TB_QUEUE_CORE_WORKERS: 16
TB_QUEUE_RULE_ENGINE_THREAD_POOL_SIZE: 32
TB_QUEUE_TRANSPORT_THREAD_POOL_SIZE: 32
TB_QUEUE_JS_THREAD_POOL_SIZE: 16

# JVM Optimization (Moderada - eficiente)
JAVA_OPTS: "-Xms6g -Xmx8g -XX:+UseG1GC -XX:MaxGCPauseMillis=15 -XX:G1HeapRegionSize=16m -XX:+UseStringDeduplication -XX:G1NewSizePercent=40 -XX:G1MaxNewSizePercent=60 -server"

# Actor System (Balanceado)
ACTORS_SYSTEM_THROUGHPUT: 5
ACTORS_SYSTEM_DEVICE_DISPATCHER_POOL_SIZE: 4
ACTORS_SYSTEM_RULE_DISPATCHER_POOL_SIZE: 8
ACTORS_RULE_DB_CALLBACK_THREAD_POOL_SIZE: 25

# Database Connection Pool
SPRING_DATASOURCE_MAXIMUM_POOL_SIZE: 16

# MQTT Optimization
MQTT_TIMEOUT_MS: 5000
NETTY_WORKER_GROUP_THREADS: 8

# Sistema
HEARTBEAT_INTERVAL: 3
```

## 🎯 MÉTRICAS DE MONITORAMENTO

### Limites Operacionais Seguros:
- **CPU ThingsBoard:** <350% (ótimo: ~330%)
- **CPU Host:** <80%
- **Latência S2M:** <200ms (ótimo: ~70ms)
- **Latência M2S:** <200ms (ótimo: ~180ms)
- **Simuladores ativos:** 5 (máximo testado com sucesso)

### Comandos de Monitoramento:
```bash
# Monitoramento contínuo de CPU
watch -n 5 'docker stats mn.tb mn.middts --no-stream'

# Verificar latências em tempo real durante teste
tail -f results/test_*/generated_reports/*latencia_stats*.csv

# Monitoramento completo com análise de gargalos
make odte-monitored DURATION=60
```

## 📁 PERFIS DE CONFIGURAÇÃO DISPONÍVEIS

### 📊 Resumo Comparativo dos Perfis

| Perfil | RPC Timeout | JVM Heap | CPU Resultado | Latência S2M | Status |
|--------|-------------|----------|---------------|--------------|--------|
| **reduced_load** | 150ms | 6-8GB | 330% | **69.4ms** | ✅ **ÓTIMO** |
| ultra_aggressive | 200ms | 12-16GB | 472% | 336.8ms | ❌ Alto CPU |
| extreme_performance | 100ms | 10-12GB | - | - | 🧪 Experimental |
| test05_best_performance | 1000ms | 4GB | - | - | 📝 Baseline |
| rpc_ultra_aggressive | 300ms | - | - | - | 📝 Intermediário |

### 🏆 PERFIL PRINCIPAL: reduced_load.yml ⭐

**Características:**
- **Objetivo:** Análise de saturação com configurações balanceadas
- **Foco:** Performance sustentável com recursos moderados
- **Uso recomendado:** Produção URLLC com 5 simuladores

**Resultados Comprovados:**
- ✅ **S2M:** 69.4ms (meta: <200ms)
- ✅ **M2S:** 184.0ms (meta: <200ms)  
- ✅ **CPU:** 330% pico, 172% médio
- ✅ **Estabilidade:** Testado com sucesso

### 📋 Perfis Alternativos

#### 1. test05_best_performance.yml
- **Propósito:** Configuração baseline balanceada  
- **RPC:** 1000ms (conservador)
- **JVM:** 4GB heap
- **Status:** Funcional para desenvolvimento

#### 2. ultra_aggressive.yml
- **Propósito:** Configurações máximas (EVITAR)
- **RPC:** 200ms, **JVM:** 12-16GB heap  
- **Resultado:** ❌ CPU muito alto (472%), latências ruins
- **Status:** Falhou por sobrecarga

#### 3. extreme_performance.yml
- **Propósito:** Configurações experimentais ultra-avançadas
- **RPC:** 100ms (ultra-agressivo)
- **JVM:** 10-12GB com otimizações avançadas
- **Status:** 🧪 Experimental (não testado em produção)

### 🎯 Recomendações de Uso

#### ✅ **Para Produção URLLC:**
**Use: reduced_load.yml**
- Testado e validado
- Latências garantidas <200ms
- CPU controlado
- 5 simuladores simultâneos

#### 🧪 **Para Testes Experimentais:**
**Use: extreme_performance.yml**
- Configurações avançadas
- JVM otimizado para alta carga
- Para testar com mais simuladores

#### 🛠️ **Para Desenvolvimento:**
**Use: test05_best_performance.yml**
- Configurações conservadoras
- Estável para desenvolvimento
- Menor uso de recursos

### 🔧 Aplicação dos Perfis

```bash
# Aplicar perfil sem reiniciar topologia
make apply-profile CONFIG_PROFILE=reduced_load

# Ou recriar topologia com perfil
make topo CONFIG_PROFILE=reduced_load SIMS=5

# Verificar perfil aplicado
make show-current-config

# Testar com monitoramento
make odte-monitored DURATION=120
```

## 🚨 TROUBLESHOOTING

### Problema: CPU ThingsBoard >400%
**Solução:**
1. Verificar número de simuladores ativos
2. Reduzir para 5 simuladores se necessário
3. Aplicar perfil reduced_load
4. Reiniciar ThingsBoard se persistir

### Problema: Latências >200ms
**Solução:**
1. Verificar CPU usage (pode estar sobrecarregado)
2. Confirmar perfil reduced_load aplicado
3. Verificar conectividade de rede
4. Reduzir simuladores se necessário

### Problema: Simuladores desconectando
**Solução:**
1. Verificar logs: `docker logs mn.sim_001`
2. Verificar conectividade: `docker exec mn.sim_001 ping 10.0.0.11`
3. Reiniciar simulador específico se necessário
4. Verificar HEARTBEAT_INTERVAL (deve ser 3s)

## 🔄 PROCEDIMENTOS DE RESET

### Reset Completo (se necessário):
```bash
# Parar topologia
make stop

# Limpar containers e volumes
make clean

# Recriar com configuração ótima
make topo CONFIG_PROFILE=reduced_load SIMS=5

# Verificar resultado
make odte-monitored DURATION=60
```

### Reset Suave (preservar dados):
```bash
# Reiniciar apenas ThingsBoard
docker restart mn.tb

# Aguardar inicialização
sleep 30

# Aplicar configuração
make apply-profile CONFIG_PROFILE=reduced_load

# Verificar health
make check-tb
```

## 📊 BENCHMARKS DE REFERÊNCIA

### Configuração Baseline (reduced_load + 5 sims):
- **S2M Latência:** 69.4ms ± 10ms
- **M2S Latência:** 184.0ms ± 20ms  
- **CPU ThingsBoard:** 330% pico, 172% médio
- **CPU Host:** ~70%
- **Throughput:** Estável para 5 dispositivos simultâneos

### Limites Máximos Testados:
- **10 simuladores:** CPU 472%, latências >300ms ❌
- **5 simuladores:** CPU 330%, latências <200ms ✅
- **Configuração recomendada:** 5 simuladores para URLLC

## 🎯 CHECKLIST DE VALIDAÇÃO

### Antes de cada teste:
- [ ] Verificar 5 simuladores ativos
- [ ] Confirmar perfil reduced_load aplicado  
- [ ] CPU ThingsBoard <350%
- [ ] Conectividade simuladores OK
- [ ] Espaço em disco para resultados

### Após cada teste:
- [ ] Latências S2M e M2S <200ms
- [ ] CPU pico <400%
- [ ] Logs sem erros críticos
- [ ] Resultados salvos corretamente
- [ ] Análise de gargalos realizada

---
**Última atualização:** 02/10/2025  
**Versão:** 1.0 - Configuração Ótima Validada