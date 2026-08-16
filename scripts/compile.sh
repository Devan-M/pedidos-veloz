#!/usr/bin/env bash

set -euo pipefail

docker run --rm \
  -v "$PWD:/workspace:ro" \
  -w /workspace \
  pedidos-veloz/orders:0.1.0 \
  python scripts/compile.py
