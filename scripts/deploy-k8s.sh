#!/bin/bash

set -Eeuo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-pedidos}"
NAMESPACE="${NAMESPACE:-pedidos-veloz}"
APP_VERSION="${APP_VERSION:-$(date +%Y%m%d-%H%M%S)}"

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

# Check prerequisites
check_tools() {
  log "Verificando ferramentas..."

  command -v kubectl &> /dev/null || error "kubectl não está instalado"
  command -v docker &> /dev/null || error "Docker não está instalado"

  success "Ferramentas verificadas"
}

# Create cluster
create_cluster() {
  log "Criando cluster k3d..."

  if k3d cluster list | grep -q "^$CLUSTER_NAME"; then
    success "Cluster $CLUSTER_NAME já existe"
  else
    k3d cluster create "$CLUSTER_NAME" \
      --agents 2 \
      -p "8080:30080@loadbalancer" \
      -p "3000:30300@loadbalancer" \
      -p "9090:30900@loadbalancer"

    success "Cluster criado"
  fi

  kubectl config use-context "k3d-$CLUSTER_NAME"
}

# Build and import images
build_images() {
  log "Construindo e importando imagens..."

  for service in api-gateway orders-service inventory-service payments-service; do
    log "Construindo $service..."
    docker build -t "pedidos-veloz/$service:$APP_VERSION" "services/$service"

    log "Importando $service no cluster..."
    k3d image import "pedidos-veloz/$service:$APP_VERSION" --cluster "$CLUSTER_NAME"
  done

  success "Imagens construídas e importadas"
}

# Apply manifests
apply_manifests() {
  log "Aplicando manifests Kubernetes..."

  kubectl apply -f k8s/base/namespace.yaml
  kubectl apply -f k8s/base/configmap.yaml
  kubectl apply -f k8s/base/secret.yaml
  kubectl apply -f k8s/base/rbac.yaml

  kubectl apply -f k8s/base/postgres-deployment.yaml
  kubectl apply -f k8s/base/redis-deployment.yaml
  kubectl apply -f k8s/base/rabbitmq-deployment.yaml

  log "Aguardando infraestrutura ficar pronta..."
  kubectl wait --for=condition=ready pod -l app=postgres -n "$NAMESPACE" --timeout=300s || true
  kubectl wait --for=condition=ready pod -l app=redis -n "$NAMESPACE" --timeout=300s || true
  kubectl wait --for=condition=ready pod -l app=rabbitmq -n "$NAMESPACE" --timeout=300s || true

  kubectl apply -f k8s/security/network-policy.yaml

  kubectl apply -f k8s/base/api-gateway-deployment.yaml
  kubectl apply -f k8s/base/orders-service-deployment.yaml
  kubectl apply -f k8s/base/inventory-service-deployment.yaml
  kubectl apply -f k8s/base/payments-service-deployment.yaml

  kubectl apply -f k8s/monitoring/prometheus-deployment.yaml
  kubectl apply -f k8s/monitoring/grafana-deployment.yaml

  success "Manifests aplicados"
}

# Wait for deployments
wait_deployments() {
  log "Aguardando deployments ficarem prontos..."

  kubectl rollout status deployment/api-gateway -n "$NAMESPACE" --timeout=300s || true
  kubectl rollout status deployment/orders-service -n "$NAMESPACE" --timeout=300s || true
  kubectl rollout status deployment/inventory-service -n "$NAMESPACE" --timeout=300s || true
  kubectl rollout status deployment/payments-service -n "$NAMESPACE" --timeout=300s || true

  success "Deployments prontos"
}

# Print status
print_status() {
  log "Status do cluster:"

  echo ""
  echo "=== Nodes ==="
  kubectl get nodes

  echo ""
  echo "=== Deployments ==="
  kubectl get deployments -n "$NAMESPACE"

  echo ""
  echo "=== Pods ==="
  kubectl get pods -n "$NAMESPACE"

  echo ""
  echo "=== Services ==="
  kubectl get services -n "$NAMESPACE"

  success "Status exibido"
}

# Main
main() {
  echo ""
  echo "╔════════════════════════════════════════╗"
  echo "║   Pedidos Veloz - Deploy Kubernetes    ║"
  echo "╚════════════════════════════════════════╝"
  echo ""

  check_tools
  create_cluster
  build_images
  apply_manifests
  wait_deployments
  print_status

  echo ""
  success "Deploy Kubernetes concluído com sucesso! 🚀"
  echo ""
}

main "$@"