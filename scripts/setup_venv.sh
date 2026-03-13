#!/bin/bash
# Cria o ambiente virtual .venv-reports e instala dependências para pós-processamento.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"

python3 -m venv "$ROOT/.venv-reports"
"$ROOT/.venv-reports/bin/pip" install --quiet --upgrade pip
"$ROOT/.venv-reports/bin/pip" install --quiet -r "$ROOT/requirements/local.txt"
echo "[OK] .venv-reports pronto."
