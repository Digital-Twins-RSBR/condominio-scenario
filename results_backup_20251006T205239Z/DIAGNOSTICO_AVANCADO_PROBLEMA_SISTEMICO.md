# 🚨 DIAGNÓSTICO AVANÇADO - PROBLEMA SISTÊMICO DETECTADO
========================================================

**Data:** 2025-10-02 18:30 UTC  
**Investigação:** Por que baseline ainda não foi reproduzido mesmo sem network shaping  

## 📊 **RESULTADOS COMPARATIVOS:**

### **🔍 ANÁLISE DOS 3 TESTES:**

| Teste | Network Config | S2M Latência | M2S Latência | Conectividade | Throughput |
|-------|----------------|--------------|--------------|---------------|------------|
| **1. reduced_load (monitored)** | 200mbit + 50ms + 0.5% | 7.003ms | 188.8ms | 41.4% | Muito baixo |
| **2. reduced_load (normal)** | 200mbit + 50ms + 0.5% | 7.224ms | 163.5ms | 41.4% | Muito baixo |
| **3. urllc (otimizado)** | 1000mbit + 0.2ms + 0% | **7.263ms** | **178.0ms** | **41.4%** | **Muito baixo** |

### **🎯 DESCOBERTA CRÍTICA:**
**Network shaping NÃO É a única causa do problema!**

## 🔍 **ANÁLISE TÉCNICA:**

### **✅ EVIDÊNCIAS QUE O NETWORK SHAPING FOI CORRIGIDO:**
- Network config mudou de `200mbit + 50ms` para `1000mbit + 0.2ms`
- M2S latência melhorou ligeiramente (188.8ms → 178.0ms)
- Jitter permanece alto mas consistente

### **🚨 PROBLEMAS SISTÊMICOS IDENTIFICADOS:**

#### **1. Baixíssimo Throughput:**
```
Sensor ativo processou apenas 6 mensagens em 5 minutos
Expectativa: ~300 mensagens (1 msg/s * 300s)
Atual: 6 mensagens = 0.02 msg/s (98% abaixo do esperado)
```

#### **2. Conectividade Consistentemente Baixa:**
- **41.4% S2M** em todos os 3 testes
- **34.5% M2S** em todos os 3 testes
- **Invariável** independente de network shaping

#### **3. S2M Latência Extremamente Alta:**
- **7+ segundos** em todos os 3 testes
- **Invariável** independente de network shaping
- **10.000% acima** do baseline histórico (69.4ms)

## 🔧 **HIPÓTESES PARA INVESTIGAÇÃO:**

### **🎯 HIPÓTESE 1: Problema no HEARTBEAT_INTERVAL**
**Arquivo:** `/var/condominio-scenario/config/thingsboard-urllc.yml`
```yaml
HEARTBEAT_INTERVAL: 3  # Pode estar muito baixo?
```

**Teste:** Verificar se simuladores estão enviando com intervalo correto

### **🎯 HIPÓTESE 2: Middleware em DEFER_START**
**Evidência:** 
```
[entrypoint] DEFER_START=1 -> aguardando start externo (tail infinito)
```

**Teste:** Verificar se middleware realmente subiu durante os testes

### **🎯 HIPÓTESE 3: Configuração ThingsBoard Incorreta**
**Possível:** RPC timeout ou configuração de batch processing inadequada

### **🎯 HIPÓTESE 4: Estado dos Digital Twins**
**Possível:** Digital Twins não criados ou em estado inconsistente

### **🎯 HIPÓTESE 5: Problemas de Sincronização**
**Possível:** Simuladores e middleware não sincronizando adequadamente

## 🚀 **PLANO DE INVESTIGAÇÃO:**

### **🔍 PRIORIDADE 1: Verificar Estado Atual**
```bash
# 1. Verificar se middleware está realmente rodando
docker exec mn.middts ps aux | grep python

# 2. Verificar configuração heartbeat nos simuladores
docker exec mn.sim_001 env | grep HEARTBEAT

# 3. Verificar se Digital Twins existem
docker exec mn.middts python3 manage.py shell -c "
from orchestrator.models import DigitalTwinInstance
print(f'Digital Twins: {DigitalTwinInstance.objects.count()}')"

# 4. Verificar logs de ThingsBoard durante teste
docker logs mn.tb | tail -50
```

### **🔍 PRIORIDADE 2: Teste de Baseline Real**
Executar teste com configuração que sabidamente funcionou no passado:
- Usar perfil `test05_best_performance`
- Verificar se baseline histórico pode ser reproduzido

### **🔍 PRIORIDADE 3: Reset Completo**
Se problemas persistirem, fazer reset completo:
```bash
make clean
make build-images
make topo CONFIG_PROFILE=reduced_load
```

## 📊 **CONCLUSÕES PRELIMINARES:**

1. **✅ Network shaping corrigido** - não é mais a causa raiz
2. **❌ Problema sistêmico detectado** - throughput 98% abaixo do esperado  
3. **❌ Conectividade persistentemente baixa** - independente de config
4. **🔍 Investigação necessária** - problema mais profundo no sistema

### **🎯 PRÓXIMA AÇÃO:**
**Executar diagnóstico completo do estado do sistema** antes de prosseguir com testes de topologia degradada.

---
*Diagnóstico gerado em: 2025-10-02 18:30 UTC*  
*Status: 🚨 PROBLEMA SISTÊMICO DETECTADO - INVESTIGAÇÃO NECESSÁRIA*