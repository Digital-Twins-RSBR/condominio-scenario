# Report generator (offline) for Influx CSV exports

Este diretório contém o gerador offline que processa CSVs exportados do Influx (formato gerado pelo `influx export`/UI) e produz relatórios de latência, ECDF, janelas de disponibilidade e ODTE.

- Arquivo principal: `generate_reports_from_export.py`

Resumo rápido
- O gerador lê o CSV exportado do Influx (com blocos de cabeçalho repetidos), agrupa por sensor e direção e emparelha eventos "sent" ↔ "recv" para calcular latências.
- Por padrão o emparelhamento usa a estratégia 1:1 (cada "sent" casa com no máximo um "recv" subsequente). Isso evita artefatos em que a confiabilidade (R) aparece maior que 1 quando o middleware registra múltiplos receives próximos.
- O gerador calcula T (timeliness dentro de DEADLINE_S), R (reliability), A (availability por janelas) e ODTE = T * R * A. Também gera métricas por direção (middts→sim e sim→middts).

Campos importantes gerados
- `R_*_capped`: versão de R limitada a 1.0 para evitar ODTE > 1 por artefatos de pareamento.
- `ODTE_*_capped`: ODTE calculado usando R_*_capped.

Como executar
1. Coloque o CSV de export do Influx em `results/` (ex.: `results/urllc_20250928T123258Z.csv`).
2. Execute o gerador (Python 3.8+):

```sh
python3 scripts/report_generators/generate_reports_from_export.py results/urllc_20250928T123258Z.csv
```

Saídas
- Os CSVs resultantes são escritos em `results/generated_reports/` com timestamp no nome. Exemplos:
  - `urllc_odte_<ts>.csv`
  - `urllc_latencia_stats_middts_to_simulator_<ts>.csv`
  - `urllc_ecdf_rtt_<ts>.csv`
  - `urllc_windows_*_<ts>.csv`

Notas
- Se quiser experimentar outras estratégias de pareamento (por exemplo, o par mais recente `latest<=recv` ou uma janela temporal), recomendo tornar isso uma flag CLI no script; está em backlog.
- DEADLINE_S e AVAIL_INTERVAL estão definidos no topo do script; ajuste conforme seu experimento.

Contato
- Mantenha este README curto — detalhes e resultados dos diagnósticos (snippets de logs, duplicações) ficam em `results/generated_reports/`.
