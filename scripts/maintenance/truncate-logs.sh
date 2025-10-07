#!/bin/sh
set -e
echo "[truncate-logs] Truncando logs grandes em deploy/logs para liberar espaço imediato (requer sudo)"
for f in deploy/logs/*.log; do
  if [ -f "$$f" ]; then
    echo "[truncate] truncating $$f to 0 bytes"
    sudo truncate -s 0 "$$f" || echo "[WARN] failed to truncate $$f"
  fi
done
echo "[truncate-logs] Truncation attempted on matching logs."
