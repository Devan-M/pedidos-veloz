#!/usr/bin/env bash

set -euo pipefail

services=(
  gateway
  orders
  payments
  inventory
)

echo "==> Construindo imagens"
docker compose build "${services[@]}"

echo "==> Validando sintaxe"
python3 - <<'PY'
import ast
from pathlib import Path

files = sorted(Path("services").rglob("*.py"))

for path in files:
    ast.parse(path.read_text(encoding="utf-8"), filename=str(path))

print(f"Sintaxe válida: {len(files)} arquivos")
PY

for service in "${services[@]}"; do
  echo "==> Testando ${service}"

  docker run --rm \
    -v "$PWD/services/${service}:/app" \
    -w /app \
    "pedidos-veloz/${service}:0.1.0" \
    pytest -q
done

echo "==> Todos os testes passaram"
