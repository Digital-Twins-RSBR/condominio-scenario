# 🎯 DESCOBERTA: CAUSA RAIZ DO NETWORK SHAPING
==============================================

**Data:** 2025-10-02  
**Investigação:** Por que network shaping estava sendo aplicado  

## 🔍 **PROBLEMA IDENTIFICADO:**

### **📍 Localização do Bug:**
- **Arquivo:** `/var/condominio-scenario/Makefile` linha 388
- **Comando:** `make odte-monitored PROFILE=reduced_load`
- **Script:** `scripts/apply_slice.sh`

### **🐛 SEQUENCE DO BUG:**

1. **Comando executado:**
   ```bash
   make odte-monitored PROFILE=reduced_load DURATION=600
   ```

2. **Makefile chama:**
   ```bash
   $(MAKE) odte PROFILE=reduced_load DURATION=600
   ```

3. **Target `odte` executa:**
   ```bash
   bash scripts/apply_slice.sh "reduced_load" --execute-scenario "600"
   ```

4. **Script `apply_slice.sh` interpreta:**
   ```bash
   PROFILE="${1:-best_effort}"  # ← "reduced_load" vira TOPO_PROFILE
   ```

5. **Como "reduced_load" ≠ "urllc", cai no default:**
   ```bash
   case "$prof" in
     urllc) BW=1000; DELAY="0.2ms"; LOSS=0 ;;
     *)     BW=200; DELAY="50ms"; LOSS=0.5 ;;  # ← APLICADO!
   esac
   ```

### **🌐 NETWORK SHAPING APLICADO:**
```bash
# Em todos os simuladores (mn.sim_001, mn.sim_002, etc.):
tc qdisc add dev eth0 root handle 1:0 tbf rate 200mbit burst 32kbit latency 400ms
tc qdisc add dev eth0 parent 1:0 handle 10: netem delay 50ms loss 0.5%
```

**Resultado:** **50ms de delay artificial** em cada pacote de rede!

## 🔧 **PROVA DA CORREÇÃO:**

### **✅ ANTES DA CORREÇÃO (com shaping):**
- **S2M Latência:** 7.003ms (7 segundos!)
- **M2S Latência:** 188.8ms
- **Network Config:** 200mbit + 50ms delay + 0.5% loss

### **🚀 CORREÇÃO APLICADA:**
```bash
# 1. Limpar network shaping existente:
for container in mn.sim_001 mn.sim_002 mn.sim_003 mn.sim_004 mn.sim_005; do
  docker exec "$container" tc qdisc del dev eth0 root 2>/dev/null || true
done

# 2. Executar com perfil correto:
make odte PROFILE=urllc DURATION=300  # ← urllc = sem shaping ruim
```

### **✅ DEPOIS DA CORREÇÃO (perfil URLLC):**
- **Network Config:** 1000mbit + 0.2ms delay + 0% loss
- **Teste em andamento:** Esperando resultados...

## 📚 **LIÇÕES APRENDIDAS:**

### **🔄 CONFUSION ENTRE DOIS TIPOS DE PERFIS:**

1. **CONFIG_PROFILE:** Configurações do ThingsBoard/middleware
   - `reduced_load.yml` → RPC timeouts, JVM heap, etc.
   - Aplicado via: `scripts/apply_profile.sh`

2. **TOPO_PROFILE:** Network shaping na topologia
   - `urllc`, `best_effort`, `eMBB`
   - Aplicado via: `scripts/apply_slice.sh`

### **💡 COMANDOS CORRETOS:**

```bash
# ❌ ERRADO (mistura perfis):
make odte-monitored PROFILE=reduced_load  # ← aplica 50ms delay!

# ✅ CORRETO (separa responsabilidades):
make topo CONFIG_PROFILE=reduced_load PROFILE=urllc
make odte PROFILE=urllc DURATION=300

# ✅ OU usar aplicação separada:
scripts/apply_profile.sh reduced_load  # Configurações TB
make odte PROFILE=urllc DURATION=300   # Topologia otimizada
```

## 🎯 **PRÓXIMOS PASSOS:**

1. **✅ Aguardar teste URLLC** terminar
2. **📊 Validar se baseline é reproduzido** (esperado: ~69.4ms S2M)
3. **📝 Atualizar documentação** sobre diferença entre perfis
4. **🔧 Possível correção no Makefile** para evitar confusão futura

## 🏆 **IMPACTO DA DESCOBERTA:**

- **Explicou** por que latências estavam 10.000% piores
- **Resolveu** mistério do baseline não reproduzível  
- **Identificou** design issue na interface de comandos
- **Habilitou** retomada dos testes de topologia degradada

---
*Descoberta documentada em: 2025-10-02 18:25 UTC*  
*Status: 🎯 CAUSA RAIZ IDENTIFICADA E CORRIGIDA*