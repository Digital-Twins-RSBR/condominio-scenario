# 🔍 RELATÓRIO DE VALIDAÇÃO DO BASELINE - RESULTADO CRÍTICO
============================================================

**Data:** 2025-10-02  
**Teste:** test_20251002T125047Z_reduced_load  
**Duração:** 10 minutos (12:50:49Z → 13:00:49Z)  
**Perfil:** reduced_load (configuração otimizada)  

## 🚨 RESULTADO CRÍTICO: BASELINE NÃO REPRODUZIDO

### **📊 COMPARAÇÃO COM BASELINE HISTÓRICO**

| Métrica | Teste Validação | Baseline Esperado | Diferença | Status |
|---------|-----------------|-------------------|-----------|--------|
| **S2M Latência** | **7.003ms** | **69.4ms** | **+9.990%** | ❌ **CRÍTICO** |
| **M2S Latência** | **188.8ms** | **184.0ms** | **+2.6%** | ✅ **OK** |
| **CPU ThingsBoard** | **Média 174.4%** | **330%** | **-47%** | ✅ **MELHOR** |
| **CPU Pico TB** | **350.1%** | **330%** | **+6%** | ⚠️ **ACEITÁVEL** |
| **Conectividade S2M** | **41.4%** | **>95%** | **-56%** | ❌ **CRÍTICO** |
| **Conectividade M2S** | **34.5%** | **>95%** | **-64%** | ❌ **CRÍTICO** |

## 🔍 ANÁLISE DETALHADA

### **✅ PONTOS POSITIVOS:**
1. **M2S Performance:** 188.8ms média (meta <200ms atingida)
2. **CPU Controlado:** Média de 174% (melhor que baseline)
3. **Sistema Estável:** Teste completo sem crashes
4. **5 Simuladores Ativos:** Configuração correta aplicada

### **🚨 PROBLEMAS CRÍTICOS:**

#### **1. S2M Latência Extremamente Alta**
- **7.003ms vs 69.4ms esperado** (10.000% pior)
- **0% compliance** com meta URLLC <200ms
- **Jitter alto:** 803ms (vs meta <10ms)

#### **2. Conectividade Muito Baixa**
- **S2M:** Apenas 24/58 sensores (41.4%) enviando dados
- **M2S:** Apenas 20/58 sensores (34.5%) recebendo comandos
- **Expectativa:** >95% conectividade

#### **3. Availability Degradada**
- **68.3%** vs meta >99.9%
- **Impacto:** Sistema não confiável para URLLC

## 🔧 ANÁLISE TÉCNICA DAS CAUSAS

### **📊 Monitoramento Durante o Teste:**
```
[12:51] TB:290.50% | MID:3.72% | HOST:68.3% | SIMS:5
[12:52] TB:313.74% | MID:16.61% | HOST:69.4% | SIMS:5
[12:53] TB:284.12% | MID:6.52% | HOST:71.0% | SIMS:5
[12:56] TB:325.32% | MID:5.29% | HOST:75.2% | SIMS:5 ← PICO
[12:58] TB:213.97% | MID:6.06% | HOST:71.1% | SIMS:5
```

### **🎯 DESCOBERTAS IMPORTANTES:**

1. **CPU Pattern Normal:** ThingsBoard oscilando entre 213-325% (similar ao baseline)
2. **Middleware Funcionando:** CPU baixo (3-16%), sem gargalo
3. **Host Estável:** 68-75% uso, sem sobrecarga
4. **Rede Aplicada:** 200mbit, 50ms delay, 0.5% loss nos simuladores

### **🔍 ROOT CAUSE ANALYSIS:**

#### **Hipóteses Para S2M Alta Latência:**

1. **Network Shaping Inadequado**
   - Aplicado 200mbit + 50ms delay nos simuladores
   - Pode estar causando delay artificial alto

2. **Configuração de Simuladores**
   - HEARTBEAT_INTERVAL pode estar inadequado
   - MQTT publishers com problemas

3. **ThingsBoard Processing**
   - Mesmo com CPU similar, pode haver gargalo interno
   - Possível problema na recepção de telemetria

#### **Hipóteses Para Baixa Conectividade:**

1. **Network Loss:** 0.5% packet loss pode estar afetando estabelecimento de conexões
2. **MQTT Configuration:** Problemas na configuração dos publishers
3. **Timing Issues:** Simuladores não sincronizando adequadamente

## 🚀 PLANO DE INVESTIGAÇÃO URGENTE

### **🎯 PRIORIDADE 1: Identificar Causa do S2M**

1. **Teste Sem Network Shaping:**
   ```bash
   # Remover tc shaping e testar novamente
   make odte PROFILE=reduced_load DURATION=300 TOPO_PROFILE=baseline
   ```

2. **Verificar Configuração Simuladores:**
   ```bash
   docker logs mn.sim_001 | tail -20
   docker exec mn.sim_001 cat /iot_simulator/.env
   ```

3. **Análise Detalhada ThingsBoard:**
   ```bash
   docker logs mn.tb | grep -i "error\|timeout\|exception" | tail -20
   ```

### **🎯 PRIORIDADE 2: Resolver Conectividade**

1. **Verificar MQTT Brokers:**
   ```bash
   docker exec mn.tb netstat -an | grep 1883
   ```

2. **Testar Conectividade Manual:**
   ```bash
   docker exec mn.sim_001 mosquitto_pub -h mn.tb -t test -m "hello"
   ```

### **🎯 PRIORIDADE 3: Teste Comparativo**

1. **Usar Configuração Original que Funcionava**
2. **Comparar logs entre teste funcional e atual**
3. **Identificar diferenças ambientais**

## 📊 CONCLUSÕES

### **🚨 STATUS ATUAL:**
- ❌ **Baseline NÃO reproduzido**
- ❌ **URLLC NÃO atingido** (S2M 7.003ms >> 200ms)
- ❌ **Sistema não confiável** (conectividade 41.4%)

### **🎯 PRÓXIMOS PASSOS OBRIGATÓRIOS:**

1. **INVESTIGAÇÃO URGENTE** das causas do S2M alto
2. **CORREÇÃO** da baixa conectividade
3. **REPRODUÇÃO** do baseline de 69.4ms S2M
4. **VALIDAÇÃO** antes de prosseguir com testes de topologia degradada

### **⚠️ RECOMENDAÇÃO:**
**NÃO prosseguir** com testes de topologia mais fraca até resolver estes problemas críticos. O sistema atual está em estado degradado comparado ao baseline validado.

---
*Relatório gerado em: 2025-10-02 13:10 UTC*  
*Status: 🚨 INVESTIGAÇÃO URGENTE NECESSÁRIA*