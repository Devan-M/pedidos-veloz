#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(pwd)"
K8S_DIR="${PROJECT_DIR}/k8s"
SERVICES=(gateway inventory orders payments)
NAMESPACE="pedidos-veloz"

log() {
  printf '\n\033[1;32m==> %s\033[0m\n' "$*"
}

warn() {
  printf '\n\033[1;33m[AVISO] %s\033[0m\n' "$*" >&2
}

require_project_root() {
  [[ -d "$PROJECT_DIR/.git" ]] || {
    echo "Execute este script na raiz do repositório Git."
    exit 1
  }
}

create_gitignore() {
  log "Atualizando .gitignore"
  touch .gitignore
  entries=(".env" ".venv/" "__pycache__/" "*.py[cod]" ".pytest_cache/" ".terraform/" "*.tfstate" "*.tfstate.*" "terraform.tfvars" "crash.log")
  for entry in "${entries[@]}"; do
    grep -qxF "$entry" .gitignore || echo "$entry" >> .gitignore
  done
}

create_dockerignore() {
  log "Criando .dockerignore para os microsserviços"
  for service in "${SERVICES[@]}"; do
    local folder="${PROJECT_DIR}/services/${service}"
    mkdir -p "$folder"
    cat > "${folder}/.dockerignore" <<'EOF'
.git
.github
.venv
__pycache__
*.pyc
.pytest_cache
tests
.env
Dockerfile
docker-compose*.yml
EOF
  done
}

create_schema() {
  log "Criando schema inicial do PostgreSQL"
  local schema="${PROJECT_DIR}/services/orders/schema.sql"
  mkdir -p "$(dirname "$schema")"
  cat > "$schema" <<'EOF'
CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY,
    customer_id TEXT NOT NULL,
    product_id TEXT NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    amount NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
    status TEXT NOT NULL
);
EOF
}

create_k8s_manifests() {
  log "Gerando manifestos do Kubernetes (HPA e Network Policies)"
  mkdir -p "$K8S_DIR/autoscaling" "$K8S_DIR/security"

  # Criando arquivo único de HPAs para os serviços
  cat > "$K8S_DIR/autoscaling/hpa.yaml" <<EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: gateway
  namespace: ${NAMESPACE}
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: gateway }
  minReplicas: 2
  maxReplicas: 5
  metrics: [{ type: Resource, resource: { name: cpu, target: { type: Utilization, averageUtilization: 70 } } }]
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: orders
  namespace: ${NAMESPACE}
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: orders }
  minReplicas: 2
  maxReplicas: 5
  metrics: [{ type: Resource, resource: { name: cpu, target: { type: Utilization, averageUtilization: 70 } } }]
EOF

  # Criando arquivo de Políticas de Rede (Security)
  cat > "$K8S_DIR/security/network-policy.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: ${NAMESPACE}
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress: [{ from: [{ namespaceSelector: { matchLabels: { "kubernetes.io/metadata.name": "${NAMESPACE}" } } }] }]
EOF
}

install_monitoring() {
  log "Configurando Stack de Monitoramento no cluster 'pedidos' via Helm"
  
  kubectl config use-context k3d-pedidos >/dev/null 2>&1

  helm repo add prometheus-community https://github.io >/dev/null 2>&1
  helm repo update >/dev/null 2>&1

  # Instala a stack mapeando o Grafana fixamente para a porta 30080 do cluster k3d
  helm upgrade --install k8s-monitoring prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    --set grafana.enabled=true \
    --set alertmanager.enabled=true \
    --set grafana.service.type=NodePort \
    --set grafana.service.nodePort=30080 \
    --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
    --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

  log "Prometheus e Grafana instalados com sucesso no namespace 'monitoring'!"
}

main() {
  require_project_root
  create_gitignore
  create_dockerignore
  create_schema
  create_k8s_manifests
  install_monitoring
  
  log "Bootstrap de DevOps concluído com sucesso!"
  warn "\nPara capturar a senha do painel do Grafana (Usuário: admin), execute:"
  echo 'kubectl get secret --namespace monitoring k8s-monitoring-grafana -o jsonpath="{.data.admin-password}" | base64 --decode; echo'
  warn "\nSeu painel estará disponível sem comandos adicionais em:"
  echo "http://localhost:8080"
}

main "$@"
