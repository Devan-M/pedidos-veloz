#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

CLUSTER_NAME="${CLUSTER_NAME:-pedidos}"
NAMESPACE="${NAMESPACE:-pedidos-veloz}"
APP_VERSION="${APP_VERSION:-$(date +%Y%m%d-%H%M%S)}"
HTTP_PORT="${HTTP_PORT:-8080}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
RECREATE_CLUSTER="${RECREATE_CLUSTER:-false}"
INSTALL_TOOLS="${INSTALL_TOOLS:-true}"

SERVICES=(gateway orders payments inventory)

log() {
  printf '\n\033[1;34m==> %s\033[0m\n' "$*"
}

success() {
  printf '\033[1;32mOK: %s\033[0m\n' "$*"
}

warn() {
  printf '\033[1;33mAVISO: %s\033[0m\n' "$*"
}

die() {
  printf '\033[1;31mERRO: %s\033[0m\n' "$*" >&2
  exit 1
}

require_root_or_sudo() {
  if [[ "$EUID" -ne 0 ]] && ! sudo -n true >/dev/null 2>&1; then
    die "O usuário precisa ter sudo configurado."
  fi
}

install_package() {
  local package="$1"

  if dpkg -s "$package" >/dev/null 2>&1; then
    success "$package já instalado"
  else
    log "Instalando $package"
    sudo apt-get install -y "$package"
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    success "Docker já instalado"
    sudo systemctl enable --now docker >/dev/null 2>&1 || true
    return
  fi

  log "Instalando Docker"

  sudo apt-get update
  sudo apt-get install -y ca-certificates curl

  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc

  sudo chmod a+r /etc/apt/keyrings/docker.asc

  . /etc/os-release

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    ${VERSION_CODENAME} stable" |
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  sudo apt-get update

  sudo apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  sudo systemctl enable --now docker
  sudo usermod -aG docker "$USER" || true

  warn "O grupo Docker foi atualizado. Se docker ainda exigir sudo, encerre e abra a sessão novamente."
}

install_kubectl() {
  if command -v kubectl >/dev/null 2>&1; then
    success "kubectl já instalado"
    return
  fi

  log "Instalando kubectl"

  local version
  version="$(curl -L -s https://dl.k8s.io/release/stable.txt)"

  curl -LO "https://dl.k8s.io/release/${version}/bin/linux/amd64/kubectl"
  curl -LO "https://dl.k8s.io/release/${version}/bin/linux/amd64/kubectl.sha256"

  echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

  rm -f kubectl kubectl.sha256
}

install_k3d() {
  if command -v k3d >/dev/null 2>&1; then
    success "k3d já instalado"
    return
  fi

  log "Instalando k3d"

  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
}

verify_tools() {
  log "Validando ferramentas"

  command -v docker >/dev/null 2>&1 || die "Docker não está disponível"
  command -v kubectl >/dev/null 2>&1 || die "kubectl não está disponível"
  command -v k3d >/dev/null 2>&1 || die "k3d não está disponível"

  docker info >/dev/null 2>&1 || die "O daemon do Docker não está disponível"

  success "Ferramentas disponíveis"
}

create_cluster() {
  if k3d cluster list | awk 'NR > 1 {print $1}' | grep -qx "$CLUSTER_NAME"; then
    success "Cluster $CLUSTER_NAME já existe"

    if [[ "$RECREATE_CLUSTER" == "true" ]]; then
      warn "RECREATE_CLUSTER=true: o cluster será recriado"
      k3d cluster delete "$CLUSTER_NAME"

      k3d cluster create "$CLUSTER_NAME" \
        --agents 1 \
        -p "${HTTP_PORT}:30080@loadbalancer" \
        -p "${GRAFANA_PORT}:30300@loadbalancer" \
        -p "${PROMETHEUS_PORT}:30900@loadbalancer"
    fi
  else
    log "Criando cluster k3d $CLUSTER_NAME"

    k3d cluster create "$CLUSTER_NAME" \
      --agents 1 \
      -p "${HTTP_PORT}:30080@loadbalancer" \
      -p "${GRAFANA_PORT}:30300@loadbalancer" \
      -p "${PROMETHEUS_PORT}:30900@loadbalancer"
  fi

  kubectl config use-context "k3d-$CLUSTER_NAME" >/dev/null
  kubectl wait --for=condition=Ready nodes --all --timeout=180s
}

build_and_import_images() {
  log "Construindo e importando imagens da versão $APP_VERSION"

  for service in "${SERVICES[@]}"; do
    local image="pedidos-veloz/${service}:${APP_VERSION}"

    [[ -d "services/$service" ]] ||
      die "Diretório não encontrado: services/$service"

    log "Construindo $image"

    docker build \
      --tag "$image" \
      "services/$service"

    log "Importando $image no k3d"

    k3d image import "$image" \
      --cluster "$CLUSTER_NAME"
  done
}

apply_manifests() {
  log "Aplicando manifestos Kubernetes"

  [[ -f k8s/namespace.yaml ]] ||
    die "Arquivo ausente: k8s/namespace.yaml"

  kubectl apply -f k8s/namespace.yaml

  [[ -f k8s/infrastructure.yaml ]] &&
    kubectl apply -f k8s/infrastructure.yaml

  [[ -f k8s/services.yaml ]] ||
    die "Arquivo ausente: k8s/services.yaml"

  kubectl apply -f k8s/services.yaml
}

update_deployments() {
  log "Atualizando Deployments para a versão $APP_VERSION"

  for service in "${SERVICES[@]}"; do
    if kubectl -n "$NAMESPACE" get deployment "$service" >/dev/null 2>&1; then
      kubectl -n "$NAMESPACE" set image \
        "deployment/$service" \
        "$service=pedidos-veloz/$service:$APP_VERSION"

      kubectl -n "$NAMESPACE" patch deployment "$service" \
        --type='merge' \
        -p '{"spec":{"template":{"spec":{"containers":[{"name":"'"$service"'","imagePullPolicy":"IfNotPresent"}]}}}}' \
        >/dev/null
    else
      warn "Deployment não encontrado: $service"
    fi
  done
}

wait_for_apps() {
  log "Aguardando aplicações"

  for service in "${SERVICES[@]}"; do
    if kubectl -n "$NAMESPACE" get deployment "$service" >/dev/null 2>&1; then
      kubectl -n "$NAMESPACE" rollout status \
        "deployment/$service" \
        --timeout=180s
    fi
  done
}

install_monitoring() {
  log "Instalando monitoramento"

  kubectl apply -f k8s/monitoring.yaml

  kubectl -n "$NAMESPACE" rollout status \
    deployment/prometheus \
    --timeout=180s

  kubectl -n "$NAMESPACE" rollout status \
    deployment/grafana \
    --timeout=180s
}

validate_system() {
  log "Validando sistema"

  local gateway_url="http://127.0.0.1:${HTTP_PORT}"
  local server_ip

  server_ip="$(hostname -I | awk '{print $1}')"

  if command -v curl >/dev/null 2>&1; then
    curl --fail --silent --show-error \
      "$gateway_url/health" >/dev/null ||
      die "Gateway não respondeu em $gateway_url/health"

    success "Gateway saudável"
  fi

  printf '\n'
  printf '\033[1;32mImplantação concluída.\033[0m\n'
  printf 'Versão:              %s\n' "$APP_VERSION"
  printf 'API local:           http://127.0.0.1:%s\n' "$HTTP_PORT"
  printf 'API na rede:         http://%s:%s\n' "$server_ip" "$HTTP_PORT"
  printf 'Grafana local:       http://127.0.0.1:%s\n' "$GRAFANA_PORT"
  printf 'Grafana na rede:     http://%s:%s\n' "$server_ip" "$GRAFANA_PORT"
  printf 'Prometheus local:    http://127.0.0.1:%s\n' "$PROMETHEUS_PORT"
  printf 'Prometheus na rede:  http://%s:%s\n' "$server_ip" "$PROMETHEUS_PORT"

  kubectl get pods -n "$NAMESPACE"
  kubectl get services -n "$NAMESPACE"
}

main() {
  require_root_or_sudo

  if [[ "$INSTALL_TOOLS" == "true" ]]; then
    log "Atualizando índice de pacotes"
    sudo apt-get update

    install_package curl
    install_package ca-certificates
    install_package jq

    install_docker
    install_kubectl
    install_k3d
  fi

  verify_tools
  create_cluster
  build_and_import_images
  apply_manifests
  update_deployments
  wait_for_apps
  install_monitoring
  validate_system
}

main "$@"
