#!/bin/bash

set -Eeuo pipefail

# ============================================================
# PEDIDOS VELOZ - SETUP SERVER 3.0
# Provisionamento idempotente de Ubuntu Server
#
# Responsabilidades:
#   - Preparar dependências do servidor
#   - Configurar Docker
#   - Configurar Docker Compose
#   - Configurar Node.js 20
#   - Configurar Python
#   - Configurar Git
#   - Configurar kubectl
#   - Instalar/validar K3D
#   - Criar/validar cluster K3D
#   - Preparar GitHub Actions Runner
#   - Validar ambiente final
#
# NÃO faz:
#   - Deploy da aplicação
#   - docker compose up
#   - kubectl apply da aplicação
#   - sobrescrita de manifests
#   - criação de secrets do Kubernetes
#   - instalação forçada de Ingress
#
# ============================================================

set +H

# ============================================================
# CORES
# ============================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# CONFIGURAÇÕES
# ============================================================

PROJECT_DIR="/pedidos-veloz"
RUNNER_DIR="${PROJECT_DIR}/runner"

GITHUB_REPOSITORY="https://github.com/Devan-M/pedidos-veloz"

RUNNER_LABEL="pedidos-veloz-test"
RUNNER_SERVICE="actions-runner.service"

K3D_CLUSTER_NAME="pedidos-veloz"

NODE_MAJOR_REQUIRED="20"
KUBECTL_VERSION="v1.35.5"

# ============================================================
# FUNÇÕES
# ============================================================

print_step() {
    echo
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}→ $1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

handle_error() {
    print_error "$1"
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

version_ge() {
    # Retorna 0 quando $1 >= $2
    dpkg --compare-versions "$1" ge "$2"
}

# ============================================================
# TRATAMENTO DE ERROS
# ============================================================

trap 'print_error "Falha na linha $LINENO. Comando: $BASH_COMMAND"' ERR

# ============================================================
# 0. VERIFICAÇÕES INICIAIS
# ============================================================

print_step "Verificando ambiente inicial"

if [ "${EUID}" -eq 0 ]; then
    handle_error "Não execute este script como root. Execute como o usuário normal."
fi

if ! command_exists sudo; then
    handle_error "sudo não está instalado."
fi

if ! sudo -v; then
    handle_error "Não foi possível validar sudo."
fi

CURRENT_USER="${USER}"

print_info "Usuário: ${CURRENT_USER}"
print_info "Hostname: $(hostname)"
print_info "Sistema: $(. /etc/os-release && echo "${PRETTY_NAME}")"
print_info "Arquitetura: $(uname -m)"

if [ "$(uname -m)" != "x86_64" ]; then
    print_warning "Este setup foi preparado/testado para x86_64."
fi

# ============================================================
# 1. ATUALIZAÇÃO DO SISTEMA
# ============================================================

print_step "Atualizando sistema"

sudo apt-get update

sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

print_success "Sistema atualizado"

# ============================================================
# 2. DEPENDÊNCIAS BÁSICAS
# ============================================================

print_step "Instalando dependências básicas"

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    wget \
    git \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    build-essential \
    libssl-dev \
    libffi-dev \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    openssl \
    jq \
    unzip \
    tar \
    gzip \
    net-tools \
    htop \
    procps \
    file

print_success "Dependências básicas disponíveis"

# ============================================================
# 3. CONFIGURAÇÃO DE LIMITES / INOTIFY
# ============================================================

print_step "Verificando limites do sistema"

SYSCTL_FILE="/etc/sysctl.d/99-pedidos-veloz.conf"

sudo tee "${SYSCTL_FILE}" > /dev/null <<'SYSCTL_EOF'
# Pedidos Veloz
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=1024
SYSCTL_EOF

sudo sysctl --system >/dev/null

print_info "inotify watches: $(cat /proc/sys/fs/inotify/max_user_watches)"
print_info "inotify instances: $(cat /proc/sys/fs/inotify/max_user_instances)"

print_success "Limites de inotify configurados"

# ============================================================
# 4. DOCKER
# ============================================================

print_step "Verificando Docker"

if command_exists docker; then

    print_info "Docker já instalado: $(docker --version)"

else

    print_info "Docker não encontrado. Instalando pelo repositório oficial."

    sudo install -m 0755 -d /etc/apt/keyrings

    if [ ! -f /etc/apt/keyrings/docker.asc ]; then
        sudo curl -fsSL \
            https://download.docker.com/linux/ubuntu/gpg \
            -o /etc/apt/keyrings/docker.asc

        sudo chmod a+r /etc/apt/keyrings/docker.asc
    fi

    . /etc/os-release

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update

    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    print_success "Docker instalado"

fi

# ============================================================
# 5. SERVIÇO DOCKER
# ============================================================

print_step "Configurando serviço Docker"

sudo systemctl enable docker
sudo systemctl start docker

if ! sudo systemctl is-active --quiet docker; then
    handle_error "Docker não está ativo."
fi

print_success "Docker ativo"

# ============================================================
# 6. GRUPO DOCKER
# ============================================================

print_step "Configurando usuário no grupo docker"

if ! getent group docker >/dev/null 2>&1; then
    sudo groupadd docker
fi

sudo usermod -aG docker "${CURRENT_USER}"

print_success "Usuário ${CURRENT_USER} adicionado ao grupo docker"

if id -nG "${CURRENT_USER}" | tr ' ' '\n' | grep -qx docker; then
    print_info "Grupo docker já está disponível na sessão atual."
else
    print_warning "O grupo docker será aplicado à próxima sessão/login."
fi

# ============================================================
# 7. DOCKER COMPOSE
# ============================================================

print_step "Verificando Docker Compose"

if docker compose version >/dev/null 2>&1; then

    COMPOSE_VERSION="$(docker compose version --short 2>/dev/null || true)"
    print_success "Docker Compose disponível: ${COMPOSE_VERSION}"

else

    print_error "docker compose não está disponível."

    print_info "Tentando instalar o plugin oficial."

    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        docker-compose-plugin

    if ! docker compose version >/dev/null 2>&1; then
        handle_error "Não foi possível instalar docker compose."
    fi

    print_success "Docker Compose instalado"

fi

# ============================================================
# 8. PYTHON
# ============================================================

print_step "Verificando Python"

if ! command_exists python3; then
    handle_error "python3 não está disponível."
fi

PYTHON_VERSION="$(python3 --version 2>&1)"

print_info "${PYTHON_VERSION}"

if ! python3 -m pip --version >/dev/null 2>&1; then
    print_warning "pip não está disponível para python3."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip
fi

if ! python3 -m venv --help >/dev/null 2>&1; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3-venv
fi

print_success "Python e ferramentas básicas disponíveis"

# ============================================================
# 9. NODE.JS 20
# ============================================================

print_step "Verificando Node.js 20"

NODE_OK=false

if command_exists node; then

    NODE_VERSION="$(node --version | sed 's/^v//')"
    NODE_MAJOR="$(echo "${NODE_VERSION}" | cut -d. -f1)"

    print_info "Node.js encontrado: v${NODE_VERSION}"

    if [ "${NODE_MAJOR}" = "${NODE_MAJOR_REQUIRED}" ]; then
        NODE_OK=true
        print_success "Node.js 20 já está instalado"

    else
        print_warning "Node.js ${NODE_MAJOR} encontrado, mas o projeto exige Node.js ${NODE_MAJOR_REQUIRED}."
    fi

fi

if [ "${NODE_OK}" = false ]; then

    print_info "Configurando NodeSource para Node.js 20"

    curl -fsSL https://deb.nodesource.com/setup_20.x \
        | sudo -E bash -

    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs

fi

if ! command_exists node; then
    handle_error "Node.js não foi instalado."
fi

NODE_VERSION="$(node --version)"
NODE_MAJOR="$(echo "${NODE_VERSION#v}" | cut -d. -f1)"

if [ "${NODE_MAJOR}" != "${NODE_MAJOR_REQUIRED}" ]; then
    handle_error "Versão incorreta do Node.js: ${NODE_VERSION}. Esperado Node.js 20.x."
fi

if ! command_exists npm; then
    handle_error "npm não está disponível."
fi

print_success "Node.js: ${NODE_VERSION}"
print_success "npm: $(npm --version)"

# ============================================================
# 10. GIT
# ============================================================

print_step "Verificando Git"

if ! command_exists git; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git
fi

print_success "Git: $(git --version)"

# Não alteramos user.name/user.email globalmente.
# A identidade do repositório deve ser configurada pelo projeto/usuário.

# ============================================================
# 11. KUBECTL
# ============================================================

print_step "Verificando kubectl"

KUBECTL_OK=false

if command_exists kubectl; then

    CURRENT_KUBECTL="$(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion' 2>/dev/null || true)"

    if [ -n "${CURRENT_KUBECTL}" ] && [ "${CURRENT_KUBECTL}" = "${KUBECTL_VERSION}" ]; then
        KUBECTL_OK=true
        print_success "kubectl ${CURRENT_KUBECTL} já está instalado"
    else
        print_info "kubectl atual: ${CURRENT_KUBECTL:-desconhecido}"
        print_info "Versão esperada para este ambiente: ${KUBECTL_VERSION}"
    fi

fi

if [ "${KUBECTL_OK}" = false ]; then

    print_info "Instalando kubectl ${KUBECTL_VERSION}"

    ARCH="$(dpkg --print-architecture)"

    case "${ARCH}" in
        amd64)
            KUBECTL_ARCH="amd64"
            ;;
        arm64)
            KUBECTL_ARCH="arm64"
            ;;
        *)
            handle_error "Arquitetura não suportada para kubectl: ${ARCH}"
            ;;
    esac

    curl -fsSL \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl" \
        -o /tmp/kubectl

    curl -fsSL \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl.sha256" \
        -o /tmp/kubectl.sha256

    echo "$(cat /tmp/kubectl.sha256)  /tmp/kubectl" \
        | sha256sum --check -

    sudo install -o root -g root -m 0755 \
        /tmp/kubectl \
        /usr/local/bin/kubectl

    rm -f /tmp/kubectl /tmp/kubectl.sha256

fi

if ! command_exists kubectl; then
    handle_error "kubectl não está disponível."
fi

KUBECTL_INSTALLED="$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')"

print_success "kubectl ${KUBECTL_INSTALLED}"

# ============================================================
# 12. K3D
# ============================================================

print_step "Verificando K3D"

if command_exists k3d; then

    print_success "K3D já instalado: $(k3d version | head -1)"

else

    print_info "K3D não encontrado. Instalando versão oficial mais recente."

    curl -s \
        https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh \
        | bash

fi

if ! command_exists k3d; then
    handle_error "K3D não foi instalado."
fi

print_success "K3D disponível: $(k3d version | head -1)"

# ============================================================
# 13. DIRETÓRIO DO PROJETO
# ============================================================

print_step "Verificando diretório do projeto"

sudo mkdir -p "${PROJECT_DIR}"

sudo chown "${CURRENT_USER}:${CURRENT_USER}" "${PROJECT_DIR}"

print_success "Diretório ${PROJECT_DIR} disponível"

# ============================================================
# 14. REPOSITÓRIO GIT
# ============================================================

print_step "Verificando repositório Git"

cd "${PROJECT_DIR}"

if [ -d "${PROJECT_DIR}/.git" ]; then

    print_success "Repositório Git já existe em ${PROJECT_DIR}"

    REMOTE_URL="$(git config --get remote.origin.url || true)"

    if [ -n "${REMOTE_URL}" ]; then
        print_info "origin: ${REMOTE_URL}"
    fi

else

    print_warning "Nenhum repositório Git encontrado em ${PROJECT_DIR}."

    print_info "O setup não fará clone automático."
    print_info "Isso evita substituir arquivos do ambiente de teste."

fi

# ============================================================
# 15. KUBECONFIG
# ============================================================

print_step "Verificando kubeconfig"

export KUBECONFIG="${HOME}/.kube/config"

mkdir -p "${HOME}/.kube"

chmod 700 "${HOME}/.kube"

if [ -f "${HOME}/.kube/config" ]; then
    chmod 600 "${HOME}/.kube/config"
fi

# ============================================================
# 16. K3D CLUSTER
# ============================================================

print_step "Verificando cluster K3D ${K3D_CLUSTER_NAME}"

if k3d cluster list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -qx "${K3D_CLUSTER_NAME}"; then

    print_success "Cluster ${K3D_CLUSTER_NAME} já existe"

else

    print_warning "Cluster ${K3D_CLUSTER_NAME} não existe."

    print_info "Criando cluster K3D..."

    k3d cluster create "${K3D_CLUSTER_NAME}" \
        --servers 1 \
        --agents 1 \
        --wait \
        --timeout 120s

    print_success "Cluster ${K3D_CLUSTER_NAME} criado"

fi

# ============================================================
# 17. KUBECONFIG DO K3D
# ============================================================

print_step "Configurando acesso ao cluster"

k3d kubeconfig merge "${K3D_CLUSTER_NAME}" \
    --kubeconfig-switch-context

chmod 600 "${HOME}/.kube/config"

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"

print_info "Contexto atual: ${CURRENT_CONTEXT:-nenhum}"

# ============================================================
# 18. VALIDAR CLUSTER
# ============================================================

print_step "Validando cluster Kubernetes"

if ! kubectl cluster-info >/dev/null 2>&1; then
    handle_error "kubectl não conseguiu acessar o cluster ${K3D_CLUSTER_NAME}."
fi

kubectl get nodes -o wide

READY_NODES="$(kubectl get nodes \
    --no-headers \
    2>/dev/null \
    | awk '$2 == "Ready" {count++} END {print count+0}')"

TOTAL_NODES="$(kubectl get nodes \
    --no-headers \
    2>/dev/null \
    | wc -l)"

print_info "Nós totais: ${TOTAL_NODES}"
print_info "Nós Ready: ${READY_NODES}"

if [ "${READY_NODES}" -lt 2 ]; then
    print_warning "Esperados pelo menos 2 nós Ready no cluster de teste."
fi

print_success "Cluster Kubernetes acessível"

# ============================================================
# 19. NAMESPACE
# ============================================================

print_step "Verificando namespace da aplicação"

if kubectl get namespace pedidos-veloz >/dev/null 2>&1; then

    print_success "Namespace pedidos-veloz já existe"

else

    print_info "Namespace pedidos-veloz ainda não existe."
    print_info "Ele será criado pelo workflow de deploy."

fi

# ============================================================
# 20. GITHUB ACTIONS RUNNER
# ============================================================

print_step "Verificando GitHub Actions Self-Hosted Runner"

mkdir -p "${RUNNER_DIR}"

if [ -f "${RUNNER_DIR}/.runner" ]; then

    print_success "Runner já está configurado."

    RUNNER_AGENT_NAME="$(jq -r '.agentName // empty' "${RUNNER_DIR}/.runner" 2>/dev/null || true)"
    RUNNER_REPO="$(jq -r '.gitHubUrl // empty' "${RUNNER_DIR}/.runner" 2>/dev/null || true)"

    print_info "Runner: ${RUNNER_AGENT_NAME:-desconhecido}"
    print_info "Repository: ${RUNNER_REPO:-desconhecido}"

    if grep -Rqs "${RUNNER_LABEL}" \
        "${RUNNER_DIR}/.runner" \
        "${RUNNER_DIR}/.credentials" \
        "${RUNNER_DIR}/.credentials_rsaparams" \
        2>/dev/null; then

        print_success "Label ${RUNNER_LABEL} encontrada na configuração do runner."

    else

        print_warning "Não foi possível confirmar a label ${RUNNER_LABEL} nos arquivos locais."
        print_info "A label será validada pelo próprio GitHub Actions."

    fi

else

    print_warning "Runner ainda não foi registrado neste servidor."

    print_info "O setup não tentará registrar automaticamente."
    print_info "O registro exige um token temporário do GitHub."

fi

# ============================================================
# 21. DEPENDÊNCIAS DO RUNNER
# ============================================================

if [ -f "${RUNNER_DIR}/bin/installdependencies.sh" ]; then

    print_step "Verificando dependências do GitHub Actions Runner"

    sudo "${RUNNER_DIR}/bin/installdependencies.sh"

    print_success "Dependências do runner verificadas"

else

    print_info "Arquivos do runner ainda não existem."
    print_info "Essa etapa será necessária somente durante o registro do runner."

fi

# ============================================================
# 22. SERVIÇO SYSTEMD DO RUNNER
# ============================================================

print_step "Verificando serviço do GitHub Actions Runner"

if [ -f "/etc/systemd/system/${RUNNER_SERVICE}" ]; then

    print_success "Serviço ${RUNNER_SERVICE} já existe"

    sudo systemctl daemon-reload

    if sudo systemctl is-enabled --quiet "${RUNNER_SERVICE}" 2>/dev/null; then
        print_success "Runner configurado para iniciar com o sistema"
    else
        print_warning "Runner existe, mas não está habilitado."
    fi

    if sudo systemctl is-active --quiet "${RUNNER_SERVICE}"; then
        print_success "Runner está ativo"
    else
        print_warning "Runner não está ativo."
    fi

else

    if [ -x "${RUNNER_DIR}/run.sh" ]; then

        print_info "Runner encontrado, mas serviço systemd não existe."

        sudo tee "/etc/systemd/system/${RUNNER_SERVICE}" > /dev/null <<SERVICE_EOF
[Unit]
Description=GitHub Actions Runner - Pedidos Veloz
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=simple
User=${CURRENT_USER}
WorkingDirectory=${RUNNER_DIR}
ExecStart=${RUNNER_DIR}/run.sh
Restart=always
RestartSec=10
KillMode=process
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
SERVICE_EOF

        sudo systemctl daemon-reload
        sudo systemctl enable "${RUNNER_SERVICE}"

        print_success "Serviço ${RUNNER_SERVICE} criado e habilitado"

        if sudo systemctl is-active --quiet "${RUNNER_SERVICE}"; then
            print_success "Runner está ativo"
        else
            print_warning "Serviço criado, mas o runner não está ativo."
            print_info "Verifique: sudo systemctl status ${RUNNER_SERVICE}"
        fi

    else

        print_info "Runner ainda não está instalado/configurado."
        print_info "Nenhum serviço foi criado."

    fi

fi

# ============================================================
# 23. PERMISSÕES
# ============================================================

print_step "Verificando permissões do projeto"

sudo chown -R "${CURRENT_USER}:${CURRENT_USER}" \
    "${PROJECT_DIR}"

chmod 700 "${PROJECT_DIR}"

if [ -d "${RUNNER_DIR}" ]; then
    chmod 700 "${RUNNER_DIR}"
fi

if [ -f "${HOME}/.ssh/config" ]; then
    chmod 600 "${HOME}/.ssh/config" || true
fi

print_success "Permissões verificadas"

# ============================================================
# 24. CONECTIVIDADE DOCKER
# ============================================================

print_step "Testando Docker"

if ! docker info >/dev/null 2>&1; then

    if id -nG "${CURRENT_USER}" | tr ' ' '\n' | grep -qx docker; then
        print_warning "A sessão atual ainda não reconhece o grupo docker."
        print_info "Tentando executar através de sudo para validar o daemon."

        sudo docker info >/dev/null \
            || handle_error "Daemon Docker não está funcionando."

    else

        sudo docker info >/dev/null \
            || handle_error "Daemon Docker não está funcionando."

    fi

fi

print_success "Docker respondendo"

# ============================================================
# 25. TESTE DOCKER COMPOSE
# ============================================================

print_step "Testando Docker Compose"

docker compose version >/dev/null 2>&1 \
    || sudo docker compose version >/dev/null 2>&1 \
    || handle_error "Docker Compose não está funcionando."

print_success "Docker Compose funcionando"

# ============================================================
# 26. VALIDAÇÃO NODE
# ============================================================

print_step "Validando Node.js e npm"

node --version
npm --version

NODE_MAJOR="$(node --version | sed 's/^v//' | cut -d. -f1)"

if [ "${NODE_MAJOR}" != "${NODE_MAJOR_REQUIRED}" ]; then
    handle_error "Node.js ${NODE_MAJOR_REQUIRED}.x é obrigatório. Detectado: $(node --version)"
fi

print_success "Node.js 20 validado"

# ============================================================
# 27. VALIDAÇÃO PYTHON
# ============================================================

print_step "Validando Python"

python3 --version
python3 -m pip --version

print_success "Python validado"

# ============================================================
# 28. VALIDAÇÃO GIT + GITHUB
# ============================================================

print_step "Validando Git e acesso ao GitHub"

git --version

if command_exists ssh; then

    if ssh -T -o BatchMode=yes -o ConnectTimeout=10 git@github.com 2>&1 \
        | grep -q "successfully authenticated"; then

        print_success "Autenticação SSH com GitHub funcionando"

    else

        print_warning "Não foi possível confirmar autenticação SSH com GitHub."
        print_info "Isso não impede o provisionamento do servidor."

    fi

fi

# ============================================================
# 29. VALIDAÇÃO KUBECTL
# ============================================================

print_step "Validando kubectl"

kubectl version --client

kubectl cluster-info >/dev/null

print_success "kubectl funcionando contra o cluster"

# ============================================================
# 30. VALIDAÇÃO K3D
# ============================================================

print_step "Validando K3D"

k3d cluster list

if k3d cluster list 2>/dev/null \
    | awk 'NR > 1 {print $1}' \
    | grep -qx "${K3D_CLUSTER_NAME}"; then

    print_success "Cluster K3D ${K3D_CLUSTER_NAME} encontrado"

else

    handle_error "Cluster K3D ${K3D_CLUSTER_NAME} não foi encontrado."
fi

# ============================================================
# 31. VALIDAÇÃO FINAL DO RUNNER
# ============================================================

print_step "Validação final do Runner"

if [ -f "${RUNNER_DIR}/.runner" ]; then

    print_success "Runner registrado"

    if sudo systemctl is-active --quiet "${RUNNER_SERVICE}" 2>/dev/null; then
        print_success "Runner systemd ativo"
    else
        print_warning "Runner registrado, mas serviço não está ativo."
    fi

else

    print_warning "Runner ainda não registrado."
    print_info "Será necessário registrar o runner antes do primeiro deploy automático."

fi

# ============================================================
# 32. RESUMO FINAL
# ============================================================

echo
echo
echo "============================================================================="
echo " PEDIDOS VELOZ - SETUP 3.0"
echo "============================================================================="
echo

echo "Hostname:          $(hostname)"
echo "Usuário:           ${CURRENT_USER}"
echo "Projeto:           ${PROJECT_DIR}"
echo "Cluster:           ${K3D_CLUSTER_NAME}"
echo "Runner label:      ${RUNNER_LABEL}"
echo

echo "----------------------------- VERSÕES --------------------------------------"

echo "Docker:            $(docker --version 2>/dev/null || sudo docker --version)"
echo "Docker Compose:    $(docker compose version --short 2>/dev/null || sudo docker compose version --short)"
echo "Node.js:           $(node --version)"
echo "npm:               $(npm --version)"
echo "Python:            $(python3 --version)"
echo "Git:               $(git --version)"
echo "kubectl:           $(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')"
echo "K3D:               $(k3d version | head -1)"
echo

echo "----------------------------- CLUSTER --------------------------------------"

kubectl get nodes -o wide

echo

echo "----------------------------- RUNNER ---------------------------------------"

if [ -f "${RUNNER_DIR}/.runner" ]; then
    echo "Runner:            CONFIGURADO"
else
    echo "Runner:            NÃO REGISTRADO"
fi

if sudo systemctl is-active --quiet "${RUNNER_SERVICE}" 2>/dev/null; then
    echo "Runner service:    ATIVO"
else
    echo "Runner service:    INATIVO/NÃO CONFIGURADO"
fi

echo

echo "----------------------------- PROJETO --------------------------------------"

if [ -d "${PROJECT_DIR}/.git" ]; then
    echo "Git repository:    OK"
else
    echo "Git repository:    NÃO ENCONTRADO"
fi

echo

echo "============================================================================="
print_success "PROVISIONAMENTO CONCLUÍDO"
echo "============================================================================="
echo

print_info "Este script NÃO fez deploy da aplicação."
print_info "O deploy Kubernetes continua sendo responsabilidade do GitHub Actions."

echo

if [ ! -f "${RUNNER_DIR}/.runner" ]; then

    print_warning "AÇÃO PENDENTE:"
    echo
    echo "Registrar o GitHub Actions Runner em:"
    echo "  ${RUNNER_DIR}"
    echo
    echo "Depois validar:"
    echo "  sudo systemctl status ${RUNNER_SERVICE}"
    echo "  sudo journalctl -u ${RUNNER_SERVICE} -f"
    echo

fi

echo "Comandos úteis:"
echo
echo "  docker --version"
echo "  docker compose version"
echo "  node --version"
echo "  npm --version"
echo "  python3 --version"
echo "  kubectl version --client"
echo "  k3d cluster list"
echo "  kubectl get nodes -o wide"
echo "  sudo systemctl status ${RUNNER_SERVICE}"
echo "  sudo journalctl -u ${RUNNER_SERVICE} -f"
echo
