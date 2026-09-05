#!/usr/bin/env bash

set -Eeuo pipefail
set +H

# ============================================================
# Pedidos Veloz - GitHub Actions Self-Hosted Runner
# ============================================================

PROJECT_DIR="/pedidos-veloz"
RUNNER_DIR="${PROJECT_DIR}/runner"
RUNNER_LABEL="pedidos-veloz-test"

CURRENT_USER="$(id -un)"

print_info() {
    echo "ℹ️  $*"
}

print_success() {
    echo "✅ $*"
}

print_warning() {
    echo "⚠️  $*"
}

handle_error() {
    echo
    echo "❌ ERRO: $*"
    exit 1
}

echo
echo "============================================================================="
echo " PEDIDOS VELOZ - GITHUB ACTIONS RUNNER"
echo "============================================================================="
echo
echo "Usuário:           ${CURRENT_USER}"
echo "Projeto:           ${PROJECT_DIR}"
echo "Runner:            ${RUNNER_DIR}"
echo "Label:             ${RUNNER_LABEL}"
echo

# ============================================================
# Validações
# ============================================================

if [[ "${EUID}" -eq 0 ]]; then
    handle_error "Não execute este script como root."
fi

if [[ ! -d "${PROJECT_DIR}/.git" ]]; then
    handle_error "Repositório Git não encontrado em ${PROJECT_DIR}."
fi

if [[ ! -x "$(command -v git)" ]]; then
    handle_error "Git não está instalado."
fi

if ! command -v curl >/dev/null 2>&1; then
    handle_error "curl não está instalado."
fi

if ! command -v tar >/dev/null 2>&1; then
    handle_error "tar não está instalado."
fi

if ! command -v systemctl >/dev/null 2>&1; then
    handle_error "systemctl não está disponível."
fi

cd "${PROJECT_DIR}"

ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"

if [[ -z "${ORIGIN_URL}" ]]; then
    handle_error "Não foi possível descobrir o remote origin do Git."
fi

# Normaliza o remote Git para a URL HTTPS esperada pelo GitHub Actions Runner.
case "${ORIGIN_URL}" in
    https://github.com/*)
        REPOSITORY_URL="${ORIGIN_URL%.git}"
        ;;
    git@github.com:*|git@github.com-*:* )
        REPOSITORY_PATH="${ORIGIN_URL#*:}"
        REPOSITORY_PATH="${REPOSITORY_PATH%.git}"
        REPOSITORY_URL="https://github.com/${REPOSITORY_PATH}"
        ;;
    *)
        handle_error "Remote origin não é um repositório GitHub suportado: ${ORIGIN_URL}"
        ;;
esac

print_info "Remote Git detectado: ${ORIGIN_URL}"
print_info "Repositório GitHub: ${REPOSITORY_URL}"

# ============================================================
# Dependências do projeto
# ============================================================

for command in docker kubectl k3d; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        handle_error "${command} não está instalado. Execute primeiro ./setup-server.sh."
    fi
done

if ! docker info >/dev/null 2>&1; then
    handle_error "Docker não está acessível pelo usuário ${CURRENT_USER}."
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
    handle_error "Kubernetes não está acessível pelo kubectl."
fi

if ! k3d cluster list 2>/dev/null | grep -q "${PROJECT_DIR##*/}"; then
    print_warning "Cluster K3D '${PROJECT_DIR##*/}' não foi encontrado."
    print_warning "O runner será instalado mesmo assim, mas o CD não poderá funcionar até o cluster existir."
fi

# ============================================================
# Runner existente
# ============================================================

if [[ -f "${RUNNER_DIR}/.runner" ]]; then
    handle_error "Já existe um runner configurado em ${RUNNER_DIR}."
fi

sudo mkdir -p "${RUNNER_DIR}"
sudo chown -R "${CURRENT_USER}:${CURRENT_USER}" "${RUNNER_DIR}"

# ============================================================
# Arquitetura
# ============================================================

ARCH="$(uname -m)"

case "${ARCH}" in
    x86_64)
        RUNNER_ARCH="x64"
        ;;
    aarch64|arm64)
        RUNNER_ARCH="arm64"
        ;;
    *)
        handle_error "Arquitetura não suportada: ${ARCH}"
        ;;
esac

print_info "Arquitetura detectada: ${RUNNER_ARCH}"

# ============================================================
# Versão do Runner
# ============================================================

print_info "Consultando versão atual do GitHub Actions Runner..."

if ! command -v jq >/dev/null 2>&1; then
    handle_error "jq não está instalado. Execute primeiro ./setup-server.sh."
fi

RUNNER_VERSION="$(
    curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        https://api.github.com/repos/actions/runner/releases/latest |
        jq -r '.tag_name // empty' |
        sed 's/^v//'
)"

if [[ -z "${RUNNER_VERSION}" ]]; then
    handle_error "Não foi possível determinar a versão do GitHub Actions Runner."
fi

RUNNER_FILE="actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_FILE}"

print_info "Runner: v${RUNNER_VERSION}"

# ============================================================
# Download
# ============================================================

cd "${RUNNER_DIR}"

if [[ ! -f "${RUNNER_FILE}" ]]; then
    print_info "Baixando GitHub Actions Runner..."
    curl -fL --retry 3 -o "${RUNNER_FILE}" "${RUNNER_URL}"
else
    print_info "Pacote do runner já existe."
fi

print_info "Extraindo runner..."

tar -xzf "${RUNNER_FILE}"

rm -f "${RUNNER_FILE}"

print_success "Runner instalado em ${RUNNER_DIR}"

# ============================================================
# Token
# ============================================================

echo
echo "============================================================================="
echo " REGISTRO DO RUNNER"
echo "============================================================================="
echo
echo "Abra no GitHub:"
echo
echo "  ${REPOSITORY_URL}"
echo
echo "Depois acesse:"
echo
echo "  Settings → Actions → Runners → New self-hosted runner"
echo
echo "Cole abaixo o token temporário fornecido pelo GitHub."
echo
echo "⚠️  O token não será salvo pelo script."
echo

read -r -s -p "Token do GitHub: " RUNNER_TOKEN
echo

if [[ -z "${RUNNER_TOKEN}" ]]; then
    handle_error "Token não informado."
fi

# ============================================================
# Nome do Runner
# ============================================================

DEFAULT_RUNNER_NAME="$(hostname -s)"

echo
read -r -p "Nome do runner [${DEFAULT_RUNNER_NAME}]: " RUNNER_NAME
RUNNER_NAME="${RUNNER_NAME:-${DEFAULT_RUNNER_NAME}}"

# ============================================================
# Configuração
# ============================================================

cd "${RUNNER_DIR}"

print_info "Registrando runner no GitHub..."

./config.sh \
    --unattended \
    --url "${REPOSITORY_URL}" \
    --token "${RUNNER_TOKEN}" \
    --name "${RUNNER_NAME}" \
    --labels "${RUNNER_LABEL}" \
    --work "_work"

unset RUNNER_TOKEN

print_success "Runner registrado."

# ============================================================
# Serviço systemd
# ============================================================

print_info "Instalando serviço systemd do runner..."

sudo ./svc.sh install "${CURRENT_USER}"
sudo ./svc.sh start

print_success "Serviço do runner iniciado."

# ============================================================
# Validação final
# ============================================================

echo
echo "============================================================================="
echo " VALIDAÇÃO FINAL"
echo "============================================================================="

echo
echo "----------------------------- RUNNER ---------------------------------------"

if sudo ./svc.sh status; then
    print_success "GitHub Actions Runner está ativo."
else
    print_warning "Não foi possível confirmar o estado do GitHub Actions Runner."
fi

echo
echo "----------------------------- CONFIGURAÇÃO ---------------------------------"

echo "Runner name:       ${RUNNER_NAME}"
echo "Runner label:      ${RUNNER_LABEL}"
echo "Runner directory:  ${RUNNER_DIR}"
echo "Service:           gerenciado pelo svc.sh"
echo "Repository:        ${REPOSITORY_URL}"

echo
echo "============================================================================="
echo "✅ GITHUB ACTIONS RUNNER CONFIGURADO"
echo "============================================================================="
echo
echo "No GitHub, confirme em:"
echo "  Settings → Actions → Runners"
echo
echo "O runner deve aparecer como:"
echo "  ${RUNNER_NAME}   ● Idle"
echo
