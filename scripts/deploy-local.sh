#!/bin/bash

set -Eeuo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# Functions
log() {
  printf "${BLUE}==>${NC} %s\n" "$*"
}

success() {
  printf "${GREEN}✓${NC} %s\n" "$*"
}

warn() {
  printf "${YELLOW}⚠${NC} %s\n" "$*"
}

error() {
  printf "${RED}✗${NC} %s\n" "$*" >&2
  exit 1
}

# Check if Docker is running
check_docker() {
  log "Verificando Docker..."
  if ! command -v docker &> /dev/null; then
    error "Docker não está instalado"
  fi

  if ! docker info &> /dev/null; then
    error "Docker daemon não está rodando"
  fi

  success "Docker está funcionando"
}

# Load environment variables
load_env() {
  log "Carregando variáveis de ambiente..."

  if [ ! -f .env ]; then
    warn ".env não encontrado, criando a partir de .env.example"
    cp .env.example .env
  fi

  set -a
  source .env
  set +a

  success "Variáveis de ambiente carregadas"
}

# Build images
build_images() {
  log "Construindo imagens Docker..."

  docker-compose build --no-cache

  success "Imagens construídas com sucesso"
}

# Start services
start_services() {
  log "Iniciando serviços..."

  docker-compose up -d

  success "Serviços iniciados"
}

# Wait for services
wait_services() {
  log "Aguardando serviços ficarem prontos..."

  local max_attempts=30
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    if curl -sf http://localhost:${API_GATEWAY_PORT}/health > /dev/null 2>&1; then
      success "API Gateway está pronto"
      break
    fi

    attempt=$((attempt + 1))
    echo -n "."
    sleep 2
  done

  if [ $attempt -eq $max_attempts ]; then
    error "Timeout aguardando API Gateway"
  fi
}

# Validate system
validate() {
  log "Validando sistema..."

  echo ""
  echo "=== API Gateway ==="
  curl -s http://localhost:${API_GATEWAY_PORT}/health | jq . || echo "Indisponível"

  echo ""
  echo "=== Orders Service ==="
  curl -s http://localhost:${ORDERS_SERVICE_PORT}/health | jq . || echo "Indisponível"

  echo ""
  echo "=== Inventory Service ==="
  curl -s http://localhost:${INVENTORY_SERVICE_PORT}/health | jq . || echo "Indisponível"

  echo ""
  echo "=== Payments Service ==="
  curl -s http://localhost:${PAYMENTS_SERVICE_PORT}/health | jq . || echo "Indisponível"

  echo ""
  echo "=== PostgreSQL ==="
  docker exec pedidos-postgres pg_isready -U ${POSTGRES_USER} || echo "Indisponível"

  echo ""
  echo "=== Redis ==="
  docker exec pedidos-redis redis-cli ping || echo "Indisponível"

  echo ""
  echo "=== RabbitMQ ==="
  curl -s http://guest:guest@localhost:15672/api/overview | jq .rabbitmq_version || echo "Indisponível"

  success "Validação concluída"
}

# Print endpoints
print_endpoints() {
  log "Endpoints disponíveis:"

  local server_ip=$(hostname -I | awk '{print $1}')

  echo ""
  echo "📡 API Gateway:"
  echo "   Local:  http://127.0.0.1:${API_GATEWAY_PORT}"
  echo "   Rede:   http://${server_ip}:${API_GATEWAY_PORT}"
  echo ""
  echo "📊 Prometheus:"
  echo "   Local:  http://127.0.0.1:${PROMETHEUS_PORT}"
  echo "   Rede:   http://${server_ip}:${PROMETHEUS_PORT}"
  echo ""
  echo "📈 Grafana:"
  echo "   Local:  http://127.0.0.1:${GRAFANA_PORT}"
  echo "   Rede:   http://${server_ip}:${GRAFANA_PORT}"
  echo "   User:   admin"
  echo "   Pass:   ${GRAFANA_ADMIN_PASSWORD}"
  echo ""
  echo "🐰 RabbitMQ Management:"
  echo "   Local:  http://127.0.0.1:${RABBITMQ_MANAGEMENT_PORT}"
  echo "   Rede:   http://${server_ip}:${RABBITMQ_MANAGEMENT_PORT}"
  echo ""
}

# Main
main() {
  echo ""
  echo "╔════════════════════════════════════════╗"
  echo "║   Pedidos Veloz - Deploy Local         ║"
  echo "╚════════════════════════════════════════╝"
  echo ""

  check_docker
  load_env
  build_images
  start_services
  wait_services
  validate
  print_endpoints

  echo ""
  success "Deploy local concluído com sucesso! 🚀"
  echo ""
}

main "$@"