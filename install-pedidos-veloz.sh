#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/pedidos-veloz}"
CLUSTER_NAME="${CLUSTER_NAME:-pedidos}"
NAMESPACE="${NAMESPACE:-pedidos-veloz}"
GRAFANA_HOST="${GRAFANA_HOST:-grafana.dvn-server}"
HTTP_PORT="${HTTP_PORT:-80}"
HTTPS_PORT="${HTTPS_PORT:-443}"
K3D_API_PORT="${K3D_API_PORT:-6550}"
K3D_APP_PORT="${K3D_APP_PORT:-8080}"
KSM_VERSION="${KSM_VERSION:-v2.16.0}"

log() {
    printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

fail() {
    echo
    echo "ERRO: $*" >&2
    exit 1
}

require_root_or_sudo() {
    command -v sudo >/dev/null 2>&1 || fail "sudo não está instalado."
}

run_as_user() {
    sudo -u "$TARGET_USER" env \
        HOME="$TARGET_HOME" \
        USER="$TARGET_USER" \
        PATH="$TARGET_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" \
        "$@"
}

detect_target_user() {
    TARGET_USER="${SUDO_USER:-$USER}"
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    [ -n "$TARGET_HOME" ] || fail "Não foi possível detectar o usuário alvo."
}

detect_lan_ip() {
    LAN_IP="$(
        ip -4 route get 1.1.1.1 2>/dev/null |
        awk '{
            for (i = 1; i <= NF; i++) {
                if ($i == "src") {
                    print $(i+1);
                    exit
                }
            }
        }'
    )"

    [ -n "${LAN_IP:-}" ] || fail "Não foi possível detectar o IP da rede local."

    log "IP detectado: ${LAN_IP}"
}

check_os() {
    [ -f /etc/os-release ] || fail "Sistema operacional não identificado."

    . /etc/os-release

    case "${ID:-}" in
        ubuntu|debian)
            log "Sistema detectado: ${PRETTY_NAME}"
            ;;
        *)
            fail "Este script suporta Ubuntu e Debian."
            ;;
    esac
}

install_base_packages() {
    log "Instalando pacotes básicos..."

    sudo apt-get update

    sudo apt-get install -y \
        ca-certificates \
        curl \
        git \
        gnupg \
        jq \
        netcat-openbsd \
        python3 \
        python3-pip \
        unzip \
        apt-transport-https
}

install_docker() {
    if command -v docker >/dev/null 2>&1; then
        log "Docker já está instalado."
    else
        log "Instalando Docker..."

        curl -fsSL https://get.docker.com | sudo sh

        sudo systemctl enable --now docker
    fi

    sudo usermod -aG docker "$TARGET_USER"

    if ! sudo docker info >/dev/null 2>&1; then
        fail "Docker não está funcionando."
    fi

    log "Docker OK."
}

install_kubectl() {
    if command -v kubectl >/dev/null 2>&1; then
        log "kubectl já está instalado."
        return
    fi

    log "Instalando kubectl..."

    local version
    version="$(curl -L -s https://dl.k8s.io/release/stable.txt)"

    curl -LO "https://dl.k8s.io/release/${version}/bin/linux/amd64/kubectl"

    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

    rm -f kubectl
}

install_k3d() {
    if command -v k3d >/dev/null 2>&1; then
        log "k3d já está instalado."
        return
    fi

    log "Instalando k3d..."

    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
}

configure_docker_permissions() {
    if id -nG "$TARGET_USER" | grep -qw docker; then
        log "Usuário já pertence ao grupo docker."
    else
        sudo usermod -aG docker "$TARGET_USER"
        log "Usuário adicionado ao grupo docker."
        log "O acesso sem sudo ao Docker só estará disponível após novo login."
    fi
}

create_cluster() {
    if sudo -u "$TARGET_USER" \
        env HOME="$TARGET_HOME" \
        PATH="$TARGET_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" \
        k3d cluster list 2>/dev/null |
        awk 'NR > 1 {print $1}' |
        grep -qx "$CLUSTER_NAME"; then

        log "Cluster k3d '${CLUSTER_NAME}' já existe."
        return
    fi

    log "Criando cluster k3d '${CLUSTER_NAME}'..."

    run_as_user k3d cluster create "$CLUSTER_NAME" \
        --servers 1 \
        --agents 1 \
        --port "${HTTP_PORT}:80@loadbalancer" \
        --port "${HTTPS_PORT}:443@loadbalancer" \
        --port "${K3D_API_PORT}:6443@server:0" \
        --port "${K3D_APP_PORT}:30080@loadbalancer" \
        --wait
}

wait_for_nodes() {
    log "Aguardando os Nodes ficarem Ready..."

    run_as_user kubectl wait \
        --for=condition=Ready \
        nodes \
        --all \
        --timeout=180s
}

start_compose_services() {
    local compose_file=""

    for candidate in \
        "$PROJECT_DIR/docker-compose.yml" \
        "$PROJECT_DIR/docker-compose.yaml" \
        "$PROJECT_DIR/compose.yml" \
        "$PROJECT_DIR/compose.yaml"
    do
        if [ -f "$candidate" ]; then
            compose_file="$candidate"
            break
        fi
    done

    if [ -z "$compose_file" ]; then
        log "Nenhum arquivo Docker Compose encontrado; etapa ignorada."
        return
    fi

    log "Iniciando serviços Docker Compose..."

    (
        cd "$PROJECT_DIR"
        sudo docker compose -f "$compose_file" up -d
    )
}

apply_project_manifests() {
    local manifest_dir=""

    for candidate in \
        "$PROJECT_DIR/k8s" \
        "$PROJECT_DIR/kubernetes" \
        "$PROJECT_DIR/manifests"
    do
        if [ -d "$candidate" ]; then
            manifest_dir="$candidate"
            break
        fi
    done

    if [ -z "$manifest_dir" ]; then
        log "Diretório de manifests Kubernetes não encontrado; etapa ignorada."
        return
    fi

    log "Aplicando manifests Kubernetes de: $manifest_dir"

    run_as_user kubectl apply -f "$manifest_dir"
}

install_kube_state_metrics() {
    log "Instalando kube-state-metrics ${KSM_VERSION}..."

    local base
    base="https://raw.githubusercontent.com/kubernetes/kube-state-metrics/${KSM_VERSION}/examples/standard"

    for manifest in \
        cluster-role-binding.yaml \
        cluster-role.yaml \
        service-account.yaml \
        deployment.yaml \
        service.yaml
    do
        run_as_user kubectl apply -f "${base}/${manifest}"
    done

    run_as_user kubectl rollout status \
        deployment/kube-state-metrics \
        -n kube-system \
        --timeout=180s
}

show_summary() {
    cat <<EOF

============================================================
Instalação concluída
============================================================

Cluster:       ${CLUSTER_NAME}
IP do servidor: ${LAN_IP}
Grafana:       http://${GRAFANA_HOST}

Entrada para o arquivo hosts do Windows:

${LAN_IP} ${GRAFANA_HOST}

Teste local:

curl -I -H 'Host: ${GRAFANA_HOST}' http://${LAN_IP}/

Comandos úteis:

kubectl get nodes -o wide
kubectl get pods -A
kubectl get ingress -A
docker ps

============================================================
EOF
}

main() {
    require_root_or_sudo
    detect_target_user
    check_os
    detect_lan_ip
    install_base_packages
    install_docker
    install_kubectl
    install_k3d
    configure_docker_permissions
    create_cluster
    wait_for_nodes
    start_compose_services
    apply_project_manifests
    install_kube_state_metrics
    show_summary
}

main "$@"
