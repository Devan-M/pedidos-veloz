#!/bin/bash

set -e

echo "🚀 Iniciando setup do servidor Ubuntu..."
echo "==========================================="

# ============================================================
# CORES
# ============================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ============================================================
# FUNÇÕES
# ============================================================

print_step() {
    echo -e "${BLUE}→ $1${NC}"
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

# ============================================================
# 1. ATUALIZAR SISTEMA
# ============================================================

print_step "Atualizando sistema..."

sudo apt-get update \
    || handle_error "Falha ao atualizar repositórios"

sudo apt-get upgrade -y \
    || handle_error "Falha ao fazer upgrade do sistema"

print_success "Sistema atualizado"

# ============================================================
# 2. DEPENDÊNCIAS BÁSICAS
# ============================================================

print_step "Instalando dependências básicas..."

sudo apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    libssl-dev \
    libffi-dev \
    python3-dev \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    net-tools \
    htop \
    python3-pip \
    python3-venv \
    || handle_error "Falha ao instalar dependências básicas"

print_success "Dependências instaladas"

# ============================================================
# 3. LIMPAR REPOSITÓRIOS ANTIGOS
# ============================================================

print_step "Limpando repositórios antigos..."

sudo rm -f /etc/apt/sources.list.d/docker.list
sudo rm -f /etc/apt/sources.list.d/kubernetes.list
sudo rm -f /etc/apt/sources.list.d/node*.list

sudo rm -f /usr/share/keyrings/docker-archive-keyring.gpg
sudo rm -f /usr/share/keyrings/kubernetes-archive-keyring.gpg
sudo rm -f /usr/share/keyrings/kubernetes-apt-keyring.gpg

print_success "Repositórios antigos removidos"

# ============================================================
# 4. DOCKER
# ============================================================

print_step "Instalando/configurando Docker..."

if ! command -v docker >/dev/null 2>&1; then

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
        || handle_error "Falha ao adicionar chave GPG do Docker"

    echo \
        "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null \
        || handle_error "Falha ao adicionar repositório Docker"

    sudo apt-get update \
        || handle_error "Falha ao atualizar repositórios do Docker"

    sudo apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-compose-plugin \
        || handle_error "Falha ao instalar Docker"

    print_success "Docker instalado"

else
    print_warning "Docker já está instalado: $(docker --version)"
fi

sudo usermod -aG docker "$USER" 2>/dev/null || true

# ============================================================
# 5. DOCKER COMPOSE
# ============================================================

print_step "Configurando Docker Compose..."

if ! command -v docker-compose >/dev/null 2>&1; then

    DOCKER_COMPOSE_VERSION=$(curl -s \
        https://api.github.com/repos/docker/compose/releases/latest \
        | grep '"tag_name"' \
        | cut -d'"' -f4)

    if [ -z "$DOCKER_COMPOSE_VERSION" ]; then
        handle_error "Não foi possível obter a versão do Docker Compose"
    fi

    sudo curl -L \
        "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose \
        || handle_error "Falha ao baixar Docker Compose"

    sudo chmod +x /usr/local/bin/docker-compose \
        || handle_error "Falha ao configurar permissão do Docker Compose"

    print_success "Docker Compose instalado"

else
    print_warning "Docker Compose já está instalado: $(docker-compose --version)"
fi

# ============================================================
# 6. VERIFICAR DOCKER
# ============================================================

print_step "Verificando Docker..."

docker --version \
    || handle_error "Docker não está funcionando"

if docker compose version >/dev/null 2>&1; then
    docker compose version
fi

if docker-compose --version >/dev/null 2>&1; then
    docker-compose --version
fi

print_success "Docker verificado"

# ============================================================
# 7. KUBERNETES
# ============================================================

print_step "Instalando/configurando Kubernetes..."

if ! command -v kubectl >/dev/null 2>&1; then

    curl -fsSL \
        https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key \
        | sudo gpg --dearmor -o /usr/share/keyrings/kubernetes-apt-keyring.gpg \
        || handle_error "Falha ao adicionar chave GPG do Kubernetes"

    echo \
        'deb [signed-by=/usr/share/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' \
        | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null \
        || handle_error "Falha ao adicionar repositório Kubernetes"

    sudo apt-get update \
        || handle_error "Falha ao atualizar repositórios Kubernetes"

    sudo apt-get install -y kubelet kubeadm kubectl \
        || handle_error "Falha ao instalar Kubernetes"

    sudo apt-mark hold kubelet kubeadm kubectl \
        || handle_error "Falha ao marcar pacotes Kubernetes"

    print_success "Kubernetes instalado"

else
    print_warning "kubectl já está instalado"
fi

# ============================================================
# 8. NODE.JS 20
# ============================================================

print_step "Instalando/configurando Node.js 20..."

if ! command -v node >/dev/null 2>&1; then

    curl -fsSL https://deb.nodesource.com/setup_20.x \
        | sudo -E bash - \
        || handle_error "Falha ao configurar Node.js"

    sudo apt-get install -y nodejs \
        || handle_error "Falha ao instalar Node.js"

    print_success "Node.js $(node --version) instalado"

else
    print_warning "Node.js já instalado: $(node --version)"
fi

# ============================================================
# 9. PYTHON
# ============================================================

print_step "Verificando Python..."

PYTHON_VERSION=$(python3 --version 2>&1)

print_success "Python $PYTHON_VERSION disponível"

# ============================================================
# 10. GIT
# ============================================================

print_step "Configurando Git..."

git config --global user.name "GitHub Actions" 2>/dev/null || true
git config --global user.email "actions@github.com" 2>/dev/null || true

print_success "Git configurado"

# ============================================================
# 11. DIRETÓRIO DA APLICAÇÃO
# ============================================================

print_step "Criando diretório da aplicação..."

sudo mkdir -p /pedidos-veloz \
    || handle_error "Falha ao criar diretório"

sudo chown "$USER:$USER" /pedidos-veloz \
    || handle_error "Falha ao alterar proprietário do diretório"

print_success "Diretório criado em /pedidos-veloz"

# ============================================================
# 12. GITHUB ACTIONS RUNNER
# ============================================================

print_step "Configurando GitHub Actions Self-Hosted Runner..."

cd /pedidos-veloz

mkdir -p runner
cd runner

print_step "Obtendo versão mais recente do runner..."

RUNNER_VERSION=$(curl -s \
    https://api.github.com/repos/actions/runner/releases/latest \
    | grep '"tag_name"' \
    | cut -d'"' -f4 \
    | sed 's/^v//' \
    | head -1)

if [ -z "$RUNNER_VERSION" ]; then
    handle_error "Falha ao obter versão do GitHub Actions Runner"
fi

print_step "Baixando runner versão $RUNNER_VERSION..."

wget \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
    || handle_error "Falha ao baixar runner"

tar xzf \
    "actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
    || handle_error "Falha ao extrair runner"

rm -f \
    "actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"

print_success "GitHub Actions Runner baixado"

# ============================================================
# 13. DEPENDÊNCIAS DO RUNNER
# ============================================================

print_step "Instalando dependências do runner..."

sudo ./bin/installdependencies.sh \
    || handle_error "Falha ao instalar dependências do runner"

print_success "Dependências do runner instaladas"

# ============================================================
# 14. SERVIÇO SYSTEMD DO RUNNER
# ============================================================

print_step "Configurando runner como serviço..."

sudo tee /etc/systemd/system/actions-runner.service > /dev/null <<EOF
[Unit]
Description=GitHub Actions Runner
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=$USER
WorkingDirectory=/pedidos-veloz/runner
ExecStart=/pedidos-veloz/runner/run.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload \
    || handle_error "Falha ao recarregar systemd"

print_success "Serviço systemd configurado"

# ============================================================
# 15. ARQUIVO .ENV
# ============================================================

print_step "Configurando arquivo .env..."

if [ -f /pedidos-veloz/.env ]; then

    print_warning "Arquivo .env já existe. Credenciais existentes serão preservadas."

    chmod 600 /pedidos-veloz/.env

else

    print_step "Gerando credenciais seguras para o ambiente Docker..."

    POSTGRES_USER="pedidos_user"
    POSTGRES_PASSWORD="$(openssl rand -hex 32)"
    POSTGRES_DB="pedidos_veloz"

    RABBITMQ_DEFAULT_USER="pedidos_user"
    RABBITMQ_DEFAULT_PASS="$(openssl rand -hex 32)"

    cat > /pedidos-veloz/.env <<ENV_EOF
NODE_ENV=production
FLASK_ENV=production

# Database
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}
DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_URL=redis://redis:6379

# RabbitMQ
RABBITMQ_HOST=rabbitmq
RABBITMQ_PORT=5672
RABBITMQ_DEFAULT_USER=${RABBITMQ_DEFAULT_USER}
RABBITMQ_DEFAULT_PASS=${RABBITMQ_DEFAULT_PASS}
RABBITMQ_USER=${RABBITMQ_DEFAULT_USER}
RABBITMQ_PASSWORD=${RABBITMQ_DEFAULT_PASS}
RABBITMQ_URL=amqp://${RABBITMQ_DEFAULT_USER}:${RABBITMQ_DEFAULT_PASS}@rabbitmq:5672

# Services
API_GATEWAY_PORT=8080
ORDERS_SERVICE_PORT=3001
INVENTORY_SERVICE_PORT=3003
PAYMENTS_SERVICE_PORT=3002

# Logging
LOG_LEVEL=info
ENV_EOF

    chmod 600 /pedidos-veloz/.env

    print_success "Arquivo .env criado com credenciais aleatórias"

fi

print_success "Arquivo .env criado"


# ============================================================
# 15.1. SECRETS DO KUBERNETES
# ============================================================

print_step "Configurando secrets do Kubernetes..."

if [ -f /pedidos-veloz/k8s/base/secret.env ]; then

    print_warning "Arquivo k8s/base/secret.env já existe. Credenciais existentes serão preservadas."

    chmod 600 /pedidos-veloz/k8s/base/secret.env

else

    print_step "Gerando credenciais seguras para o Kubernetes..."

    K8S_POSTGRES_USER="pedidos_user"
    K8S_POSTGRES_PASSWORD="$(openssl rand -hex 32)"
    K8S_REDIS_PASSWORD="$(openssl rand -hex 32)"
    K8S_RABBITMQ_DEFAULT_USER="pedidos_user"
    K8S_RABBITMQ_DEFAULT_PASS="$(openssl rand -hex 32)"
    K8S_JWT_SECRET="$(openssl rand -hex 32)"
    K8S_API_KEY="$(openssl rand -hex 32)"
    K8S_GRAFANA_ADMIN_PASSWORD="$(openssl rand -hex 32)"

    cat > /pedidos-veloz/k8s/base/secret.env <<K8S_SECRET_EOF
POSTGRES_USER=${K8S_POSTGRES_USER}
POSTGRES_PASSWORD=${K8S_POSTGRES_PASSWORD}
REDIS_PASSWORD=${K8S_REDIS_PASSWORD}
RABBITMQ_DEFAULT_USER=${K8S_RABBITMQ_DEFAULT_USER}
RABBITMQ_DEFAULT_PASS=${K8S_RABBITMQ_DEFAULT_PASS}
JWT_SECRET=${K8S_JWT_SECRET}
API_KEY=${K8S_API_KEY}
GRAFANA_ADMIN_PASSWORD=${K8S_GRAFANA_ADMIN_PASSWORD}
K8S_SECRET_EOF

    chmod 600 /pedidos-veloz/k8s/base/secret.env

    print_success "Secrets do Kubernetes criados com credenciais aleatórias"

fi




# ============================================================
# 16. DOCKER COMPOSE DA INFRAESTRUTURA
# ============================================================

print_step "Criando docker-compose.yml..."

cat > /pedidos-veloz/docker-compose.yml <<'DOCKER_EOF'
services:

  # ============================================================
  # PostgreSQL
  # ============================================================

  postgres:
    image: postgres:15-alpine
    container_name: pedidos-postgres

    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}

    ports:
      - "5432:5432"

    volumes:
      - postgres_data:/var/lib/postgresql/data

    networks:
      - pedidos-network

    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

    restart: unless-stopped

  # ============================================================
  # Redis
  # ============================================================

  redis:
    image: redis:7-alpine
    container_name: pedidos-redis

    ports:
      - "6379:6379"

    volumes:
      - redis_data:/data

    networks:
      - pedidos-network

    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

    restart: unless-stopped

  # ============================================================
  # RabbitMQ
  # ============================================================

  rabbitmq:
    image: rabbitmq:3.12-management-alpine
    container_name: pedidos-rabbitmq

    environment:
      RABBITMQ_DEFAULT_USER: ${RABBITMQ_DEFAULT_USER}
      RABBITMQ_DEFAULT_PASS: ${RABBITMQ_DEFAULT_PASS}

    ports:
      - "5672:5672"
      - "15672:15672"

    volumes:
      - rabbitmq_data:/var/lib/rabbitmq

    networks:
      - pedidos-network

    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

    restart: unless-stopped

  # ============================================================
  # API Gateway
  # ============================================================

  api-gateway:
    build:
      context: ./services/api-gateway
      dockerfile: Dockerfile

    container_name: pedidos-api-gateway

    ports:
      - "8080:8080"

    environment:
      NODE_ENV: production

      ORDERS_SERVICE_URL: http://orders-service:3001
      INVENTORY_SERVICE_URL: http://inventory-service:3003
      PAYMENTS_SERVICE_URL: http://payments-service:3002

      REDIS_HOST: redis
      REDIS_PORT: "6379"
      REDIS_URL: redis://redis:6379

      RABBITMQ_HOST: rabbitmq
      RABBITMQ_PORT: "5672"
      RABBITMQ_DEFAULT_USER: ${RABBITMQ_DEFAULT_USER}
      RABBITMQ_DEFAULT_PASS: ${RABBITMQ_DEFAULT_PASS}
      RABBITMQ_URL: amqp://${RABBITMQ_DEFAULT_USER}:${RABBITMQ_DEFAULT_PASS}@rabbitmq:5672

      LOG_LEVEL: info

    depends_on:
      redis:
        condition: service_healthy

      rabbitmq:
        condition: service_healthy

      orders-service:
        condition: service_started

      inventory-service:
        condition: service_started

      payments-service:
        condition: service_started

    networks:
      - pedidos-network

    restart: unless-stopped

  # ============================================================
  # Orders Service
  # ============================================================

  orders-service:
    build:
      context: ./services/orders-service
      dockerfile: Dockerfile

    container_name: pedidos-orders-service

    ports:
      - "3001:3001"

    environment:
      NODE_ENV: production

      POSTGRES_HOST: postgres
      POSTGRES_PORT: "5432"
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      DATABASE_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}

      REDIS_HOST: redis
      REDIS_PORT: "6379"
      REDIS_URL: redis://redis:6379

      RABBITMQ_HOST: rabbitmq
      RABBITMQ_PORT: "5672"
      RABBITMQ_DEFAULT_USER: ${RABBITMQ_DEFAULT_USER}
      RABBITMQ_DEFAULT_PASS: ${RABBITMQ_DEFAULT_PASS}
      RABBITMQ_USER: ${RABBITMQ_DEFAULT_USER}
      RABBITMQ_PASSWORD: ${RABBITMQ_DEFAULT_PASS}
      RABBITMQ_URL: amqp://${RABBITMQ_DEFAULT_USER}:${RABBITMQ_DEFAULT_PASS}@rabbitmq:5672

      LOG_LEVEL: info

    depends_on:
      postgres:
        condition: service_healthy

      redis:
        condition: service_healthy

      rabbitmq:
        condition: service_healthy

    networks:
      - pedidos-network

    restart: unless-stopped

  # ============================================================
  # Inventory Service
  # ============================================================

  inventory-service:
    build:
      context: ./services/inventory-service
      dockerfile: Dockerfile

    container_name: pedidos-inventory-service

    ports:
      - "3003:3003"

    environment:
      NODE_ENV: production

      POSTGRES_HOST: postgres
      POSTGRES_PORT: "5432"
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      DATABASE_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}

      REDIS_HOST: redis
      REDIS_PORT: "6379"
      REDIS_URL: redis://redis:6379

      RABBITMQ_HOST: rabbitmq
      RABBITMQ_PORT: "5672"
      RABBITMQ_DEFAULT_USER: ${RABBITMQ_DEFAULT_USER}
      RABBITMQ_DEFAULT_PASS: ${RABBITMQ_DEFAULT_PASS}
      RABBITMQ_USER: ${RABBITMQ_DEFAULT_USER}
      RABBITMQ_PASSWORD: ${RABBITMQ_DEFAULT_PASS}
      RABBITMQ_URL: amqp://${RABBITMQ_DEFAULT_USER}:${RABBITMQ_DEFAULT_PASS}@rabbitmq:5672

      LOG_LEVEL: info

    depends_on:
      postgres:
        condition: service_healthy

      redis:
        condition: service_healthy

      rabbitmq:
        condition: service_healthy

    networks:
      - pedidos-network

    restart: unless-stopped

  # ============================================================
  # Payments Service
  # ============================================================

  payments-service:
    build:
      context: ./services/payments-service
      dockerfile: Dockerfile

    container_name: pedidos-payments-service

    ports:
      - "3002:3002"

    environment:
      FLASK_ENV: production
      FLASK_APP: app.py

      POSTGRES_HOST: postgres
      POSTGRES_PORT: "5432"
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      DATABASE_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}

      REDIS_HOST: redis
      REDIS_PORT: "6379"
      REDIS_URL: redis://redis:6379

      RABBITMQ_HOST: rabbitmq
      RABBITMQ_PORT: "5672"
      RABBITMQ_DEFAULT_USER: ${RABBITMQ_DEFAULT_USER}
      RABBITMQ_DEFAULT_PASS: ${RABBITMQ_DEFAULT_PASS}
      RABBITMQ_USER: ${RABBITMQ_DEFAULT_USER}
      RABBITMQ_PASSWORD: ${RABBITMQ_DEFAULT_PASS}
      RABBITMQ_URL: amqp://${RABBITMQ_DEFAULT_USER}:${RABBITMQ_DEFAULT_PASS}@rabbitmq:5672

      LOG_LEVEL: INFO

    depends_on:
      postgres:
        condition: service_healthy

      redis:
        condition: service_healthy

      rabbitmq:
        condition: service_healthy

    networks:
      - pedidos-network

    restart: unless-stopped

# ============================================================
# VOLUMES
# ============================================================

volumes:
  postgres_data:
  redis_data:
  rabbitmq_data:

# ============================================================
# NETWORK
# ============================================================

networks:
  pedidos-network:
    driver: bridge
DOCKER_EOF

print_success "docker-compose.yml criado"

# ============================================================
# 17. INICIAR INFRAESTRUTURA
# ============================================================

print_step "Iniciando infraestrutura..."

cd /pedidos-veloz

docker compose up -d \
    || handle_error "Falha ao iniciar infraestrutura"

print_success "Infraestrutura iniciada"

# ============================================================
# 18. AGUARDAR POSTGRESQL
# ============================================================

print_step "Aguardando PostgreSQL..."

for i in {1..30}; do

    if docker exec pedidos-postgres \
        pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
        >/dev/null 2>&1; then

        print_success "PostgreSQL pronto"
        break
    fi

    if [ "$i" -eq 30 ]; then
        handle_error "PostgreSQL não ficou pronto"
    fi

    sleep 2

done

# ============================================================
# 19. VERIFICAR INFRAESTRUTURA
# ============================================================

print_step "Verificando infraestrutura..."

docker compose ps

print_success "Infraestrutura verificada"

# ============================================================
# 20. NGINX INGRESS CONTROLLER
# ============================================================

print_step "Instalando NGINX Ingress Controller..."

kubectl apply \
    -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml \
    || handle_error "Falha ao instalar NGINX Ingress Controller"

print_step "Aguardando NGINX Ingress Controller..."

kubectl wait \
    --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=300s \
    || print_warning "NGINX ainda está inicializando"

print_success "NGINX Ingress Controller instalado"

# ============================================================
# 21. SCRIPT DE DEPLOY
# ============================================================

print_step "Criando script de deploy..."

cat > /pedidos-veloz/deploy.sh <<'DEPLOY_EOF'
#!/bin/bash

set -e

echo "🚀 Iniciando deploy..."

cd /pedidos-veloz

if [ -d "pedidos-veloz/.git" ]; then

    echo "📦 Atualizando repositório..."

    cd pedidos-veloz

    git fetch origin
    git reset --hard origin/main

    cd ..

else

    echo "📦 Clonando repositório..."

    rm -rf pedidos-veloz

    git clone https://github.com/Devan-M/pedidos-veloz.git

fi

echo "🚀 Deployando aplicação no Kubernetes..."

kubectl apply -k pedidos-veloz/k8s/base/

echo ""
echo "✅ Deploy concluído!"
echo ""
echo "📋 Verificar status:"
echo "   kubectl get pods -n pedidos-veloz"
echo "   kubectl get svc -n pedidos-veloz"
echo "   kubectl get ingress -n pedidos-veloz"

DEPLOY_EOF

chmod +x /pedidos-veloz/deploy.sh

print_success "Script de deploy criado"

# ============================================================
# 22. RESUMO FINAL
# ============================================================

echo ""
echo "==========================================="
print_success "Setup concluído com sucesso!"
echo "==========================================="
echo ""

echo "📋 Próximos passos:"
echo ""

echo "1️⃣ Registrar o runner no GitHub:"
echo "   cd /pedidos-veloz/runner"
echo "   ./config.sh --url https://github.com/Devan-M/pedidos-veloz --token <SEU_TOKEN>"
echo ""

echo "2️⃣ Iniciar o runner:"
echo "   sudo systemctl enable actions-runner"
echo "   sudo systemctl start actions-runner"
echo ""

echo "3️⃣ Verificar status:"
echo "   sudo systemctl status actions-runner"
echo "   docker compose -f /pedidos-veloz/docker-compose.yml ps"
echo "   kubectl get pods -n ingress-nginx"
echo ""

echo "4️⃣ Verificar PostgreSQL:"
echo "   docker exec pedidos-postgres psql -U pedidos_user -d pedidos_veloz -c '\du'"
echo ""

echo "5️⃣ Obter IP do Ingress:"
echo "   kubectl get svc -n ingress-nginx ingress-nginx-controller"
echo ""

echo "6️⃣ Fazer deploy:"
echo "   /pedidos-veloz/deploy.sh"
echo ""

echo "7️⃣ RabbitMQ Management:"
echo "   http://<IP_DO_SERVIDOR>:15672"
echo "   usuário: guest"
echo "   senha: guest"
echo ""

echo "📁 Diretórios:"
echo "   - Aplicação: /pedidos-veloz"
echo "   - Runner: /pedidos-veloz/runner"
echo "   - Repositório: /pedidos-veloz/pedidos-veloz"
echo ""

echo "🔍 Troubleshooting:"
echo "   journalctl -u actions-runner -f"
echo "   docker compose logs -f"
echo "   kubectl get pods -A"
echo ""
