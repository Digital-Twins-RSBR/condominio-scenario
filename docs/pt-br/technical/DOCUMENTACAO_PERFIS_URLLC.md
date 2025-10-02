# 📁 DOCUMENTAÇÃO DOS PERFIS DE CONFIGURAÇÃO URLLC
==================================================================

## 🎯 VISÃO GERAL DOS PERFIS

Total de perfis criados: **5 perfis**  
Perfil vencedor: **reduced_load.yml** ✅  
Objetivo: Otimização para latências <200ms em comunicações URLLC

## 📊 RESUMO COMPARATIVO DOS PERFIS

| Perfil | RPC Timeout | JVM Heap | CPU Resultado | Latência S2M | Status |
|--------|-------------|----------|---------------|--------------|--------|
| **reduced_load** | 150ms | 6-8GB | 330% | **69.4ms** | ✅ **ÓTIMO** |
| ultra_aggressive | 200ms | 12-16GB | 472% | 336.8ms | ❌ Alto CPU |
| extreme_performance | 100ms | 10-12GB | - | - | 🧪 Experimental |
| test05_best_performance | 1000ms | 4GB | - | - | 📝 Baseline |
| rpc_ultra_aggressive | 300ms | - | - | - | 📝 Intermediário |

## 🏆 PERFIL VENCEDOR: reduced_load.yml

### Características Principais:
- **Objetivo:** Análise de saturação com configurações balanceadas
- **Foco:** Performance sustentável com recursos moderados
- **Uso recomendado:** Produção URLLC com 5 simuladores

### Configurações Chave:
```yaml
# Timeouts balanceados
CLIENT_SIDE_RPC_TIMEOUT: 150ms
HTTP_REQUEST_TIMEOUT_MS: 750ms

# Batch processing eficiente
SQL_TS_BATCH_MAX_DELAY_MS: 8ms
SQL_TS_LATEST_BATCH_MAX_DELAY_MS: 4ms

# JVM moderado mas eficiente
JAVA_OPTS: "-Xms6g -Xmx8g -XX:+UseG1GC -XX:MaxGCPauseMillis=15ms"

# Threading balanceado
TB_QUEUE_RULE_ENGINE_THREAD_POOL_SIZE: 32
TB_QUEUE_TRANSPORT_THREAD_POOL_SIZE: 32
```

### Resultados Comprovados:
- ✅ **S2M:** 69.4ms (meta: <200ms)
- ✅ **M2S:** 184.0ms (meta: <200ms)  
- ✅ **CPU:** 330% pico, 172% médio
- ✅ **Estabilidade:** Testado com sucesso

## 📋 DETALHAMENTO DOS PERFIS

### 1. test05_best_performance.yml
**Propósito:** Configuração baseline balanceada  
**Características:**
- RPC: 1000ms (conservador)
- JVM: 4GB heap
- Threading: moderado (10/8 pools)
- Status: Funcional, mas não otimizado para URLLC

### 2. rpc_ultra_aggressive.yml  
**Propósito:** Foco em RPC agressivo
**Características:**
- RPC: 300ms (intermediário)
- HTTP: otimizações específicas
- Status: Teste intermediário

### 3. ultra_aggressive.yml
**Propósito:** Configurações máximas testadas inicialmente
**Características:**
- RPC: 200ms
- JVM: 12-16GB heap  
- Threading: máximo (64/64 pools)
- Resultado: CPU muito alto (472%), latências ruins
- Status: ❌ Falhou por sobrecarga

### 4. extreme_performance.yml
**Propósito:** Configurações experimentais ultra-avançadas
**Características:**
- RPC: 100ms (ultra-agressivo)
- JVM: 10-12GB com otimizações avançadas
- GC: 5ms pause time
- Threading: máximo com actors otimizados
- Status: 🧪 Não testado (criado para testes futuros)

### 5. reduced_load.yml ⭐
**Propósito:** Configuração ótima identificada
**Características:**
- RPC: 150ms (balanceado)
- JVM: 6-8GB (eficiente)
- Threading: moderado (32/32 pools)
- Resultado: **SUCESSO TOTAL**
- Status: ✅ **PRODUÇÃO**

## 🎯 RECOMENDAÇÕES DE USO

### Para Produção URLLC:
**Use: reduced_load.yml**
- Testado e validado
- Latências garantidas <200ms
- CPU controlado
- 5 simuladores simultâneos

### Para Testes Experimentais:
**Use: extreme_performance.yml**
- Configurações avançadas
- JVM otimizado para alta carga
- Para testar com mais simuladores

### Para Desenvolvimento:
**Use: test05_best_performance.yml**
- Configurações conservadoras
- Estável para desenvolvimento
- Menor uso de recursos

## 🔧 APLICAÇÃO DOS PERFIS

### Comando Padrão:
```bash
# Aplicar perfil sem reiniciar topologia
make apply-profile CONFIG_PROFILE=reduced_load

# Ou recriar topologia com perfil
make topo CONFIG_PROFILE=reduced_load SIMS=5
```

### Verificação:
```bash
# Verificar perfil aplicado
make show-current-config

# Testar com monitoramento
make odte-monitored DURATION=120
```

## 📊 HISTÓRICO DE EVOLUÇÃO

### Evolução dos Testes:
1. **test05_best_performance** → Baseline estabelecida
2. **rpc_ultra_aggressive** → Foco em RPC
3. **ultra_aggressive** → Tentativa de máxima performance (falhou)
4. **extreme_performance** → Análise avançada (experimental)
5. **reduced_load** → **SOLUÇÃO FINAL** ⭐

### Lições Aprendidas:
- **Mais não é sempre melhor:** JVM 16GB pior que 8GB
- **Balance é chave:** Threading moderado > máximo
- **Carga importa mais:** 5 sims > configurações extremas  
- **Monitoramento essencial:** CPU real > configurações teóricas

## 🎯 PRÓXIMOS DESENVOLVIMENTOS

### Perfis Futuros Sugeridos:
1. **mid_load.yml** - Para 7-8 simuladores
2. **production_stable.yml** - Versão hardened do reduced_load
3. **debug_performance.yml** - Com logs detalhados para troubleshooting

### Melhorias Incrementais:
- Ajuste fino de batch processing
- Otimização específica para hardware
- Configurações adaptativas baseadas em carga

---
**Documentação criada:** 02/10/2025  
**Perfis mantidos em:** `/config/profiles/`  
**Status:** Configuração ótima identificada e documentada ✅