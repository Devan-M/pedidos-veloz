#!/bin/bash

set -e

echo "🚀 Iniciando setup do servidor Ubuntu..."
echo "==========================================="

# Cores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Função para imprimir com cor
print_step() {
    echo -e "${BLUE}→ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# 1. Atualizar sistema
print_step "Atualizando sistema..."
sudo apt-get update
sudo apt-get upgrade -y
print_success "Sistema atualizado"

# 2. Instalar dependências básicas
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
    software-properties-common
print_success "Dependências instaladas"

# 3. Remover docker-compose-v2 se existir (conflita com docker-compose-plugin)
print_step "Removendo conflitos de docker-compose..."
sudo apt-get remove -y docker-compose-v2 || true
print_success "Conflitos removidos"

# 4. Instalar Docker
print_step "Instalar Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER
print_success "Docker instalado"

# 5. Instalar Docker Compose (standalone)
print_step "Instalando Docker Compose standalone..."
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
print_success "Docker Compose instalado"

# 6. Verificar Docker
print_step "Verificando Docker..."
docker --version
docker-compose --version
print_success "Docker verificado"

# 7. Instalar Kubernetes (kubeadm, kubelet, kubectl)
print_step "Instalando Kubernetes..."
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
print_success "Kubernetes instalado"

# 8. Instalar Node.js 20
print_step "Instalando Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
print_success "Node.js $(node --version) instalado"

# 9. Python já está instalado
print_step "Verificando Python..."
PYTHON_VERSION=$(python3 --version)
print_success "Python $PYTHON_VERSION já instalado"

# 10. Instalar pip e venv
print_step "Instalando pip e venv..."
sudo apt-get install -y python3-pip python3-venv
print_success "pip e venv instalados"

# 11. Instalar Git
print_step "Configurando Git..."
git config --global user.name "GitHub Actions" || true
git config --global user.email "actions@github.com" || true
print_success "Git configurado"

# 12. Criar diretório para aplicação
print_step "Criando diretório da aplicação..."
sudo mkdir -p /opt/pedidos-veloz
sudo chown $USER:$USER /opt/pedidos-veloz
print_success "Diretório criado em /opt/pedidos-veloz"

# 13. Instalar GitHub Actions Runner
print_step "Instalando GitHub Actions Self-Hosted Runner..."
cd /opt/pedidos-veloz

# Criar diretório para runner
mkdir -p runner
cd runner

# Download latest runner
RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | grep tag_name | cut -d'"' -f4 | sed 's/v//')
print_step "Baixando runner versão $RUNNER_VERSION..."
wget https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

print_success "GitHub Actions Runner baixado"

# 14. Instalar dependências do runner
print_step "Instalando dependências do runner..."
sudo ./bin/installdependencies.sh
print_success "Dependências do runner instaladas"

# 15. Criar serviço systemd para o runner
print_step "Configurando runner como serviço..."
sudo tee /etc/systemd/system/actions-runner.service > /dev/null <<EOF
[Unit]
Description=GitHub Actions Runner
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/pedidos-veloz/runner
ExecStart=/opt/pedidos-veloz/runner/run.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
print_success "Serviço systemd configurado"

# 16. Criar docker-compose para infraestrutura
print_step "Criando docker-compose para infraestrutura..."
cat > /opt/pedidos-veloz/docker-compose.yml <<'DOCKER_EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: pedidos-postgres
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: pedidos_veloz
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - pedidos-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

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

  rabbitmq:
    image: rabbitmq:3.12-management-alpine
    container_name: pedidos-rabbitmq
    environment:
      RABBITMQ_DEFAULT_USER: guest
      RABBITMQ_DEFAULT_PASS: guest
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

volumes:
  postgres_data:
  redis_data:
  rabbitmq_data:

networks:
  pedidos-network:
    driver: bridge
DOCKER_EOF

print_success "docker-compose.yml criado"

# 17. Iniciar infraestrutura
print_step "Iniciando infraestrutura (PostgreSQL, Redis, RabbitMQ)..."
cd /opt/pedidos-veloz
docker-compose up -d
print_success "Infraestrutura iniciada"

# 18. Aguardar serviços ficarem prontos
print_step "Aguardando serviços ficarem prontos..."
sleep 10
docker-compose ps
print_success "Serviços prontos"

# 19. Instalar NGINX Ingress Controller
print_step "Instalando NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml

# Aguardar NGINX Ingress Controller ficar pronto
print_step "Aguardando NGINX Ingress Controller ficar pronto..."
sleep 30
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s || print_warning "NGINX Ingress Controller ainda está sendo iniciado, continue monitorando"

print_success "NGINX Ingress Controller instalado"

# 20. Criar script de deploy
print_step "Criando script de deploy..."
cat > /opt/pedidos-veloz/deploy.sh <<'DEPLOY_EOF'
#!/bin/bash

set -e

echo "🚀 Iniciando deploy..."

cd /opt/pedidos-veloz

# Clonar/atualizar repositório
if [ -d "pedidos-veloz" ]; then
    echo "📦 Atualizando repositório..."
    cd pedidos-veloz
    git pull origin main
    cd ..
else
    echo "📦 Clonando repositório..."
    git clone https://github.com/Devan-M/pedidos-veloz.git
fi

# Deploy com Kustomize
echo "🚀 Deployando aplicação no Kubernetes..."
kubectl apply -k pedidos-veloz/k8s/base/

echo "✅ Deploy concluído!"
echo ""
echo "📋 Verificar status:"
echo "   kubectl get pods -n pedidos-veloz"
echo "   kubectl get svc -n pedidos-veloz"
echo "   kubectl get ingress -n pedidos-veloz"
DEPLOY_EOF

chmod +x /opt/pedidos-veloz/deploy.sh
print_success "Script de deploy criado"

# 21. Criar arquivo de configuração
print_step "Criando arquivo de configuração..."
cat > /opt/pedidos-veloz/.env <<'ENV_EOF'
NODE_ENV=production
FLASK_ENV=production

# Database
DATABASE_URL=postgresql://postgres:postgres@postgres:5432/pedidos_veloz

# Redis
REDIS_URL=redis://redis:6379

# RabbitMQ
RABBITMQ_URL=amqp://guest:guest@rabbitmq:5672

# Services
API_GATEWAY_PORT=3000
ORDERS_SERVICE_PORT=3001
INVENTORY_SERVICE_PORT=3002
PAYMENTS_SERVICE_PORT=3003

# Logging
LOG_LEVEL=info
ENV_EOF

print_success "Arquivo .env criado"

# 22. Resumo final
echo ""
echo "==========================================="
print_success "Setup concluído com sucesso!"
echo "==========================================="
echo ""
echo "📋 Próximos passos:"
echo ""
echo "1️⃣  Registrar o runner no GitHub:"
echo "   cd /opt/pedidos-veloz/runner"
echo "   ./config.sh --url https://github.com/Devan-M/pedidos-veloz --token <SEU_TOKEN>"
echo ""
echo "2️⃣  Iniciar o runner como serviço:"
echo "   sudo systemctl enable actions-runner"
echo "   sudo systemctl start actions-runner"
echo ""
echo "3️⃣  Verificar status:"
echo "   sudo systemctl status actions-runner"
echo "   docker-compose -f /opt/pedidos-veloz/docker-compose.yml ps"
echo "   kubectl get pods -n ingress-nginx"
echo ""
echo "4️⃣  Obter IP do Ingress:"
echo "   kubectl get svc -n ingress-nginx ingress-nginx-controller"
echo ""
echo "5️⃣  Configurar /etc/hosts (adicione a linha com o IP do Ingress):"
echo "   <IP_DO_INGRESS> api.pedidos-veloz.local"
echo "   <IP_DO_INGRESS> grafana.pedidos-veloz.local"
echo "   <IP_DO_INGRESS> prometheus.pedidos-veloz.local"
echo ""
echo "6️⃣  Fazer deploy da aplicação:"
echo "   /opt/pedidos-veloz/deploy.sh"
echo ""
echo "7️⃣  Acessar RabbitMQ Management:"
echo "   http://192.168.1.2:15672 (guest/guest)"
echo ""
echo "📁 Diretórios importantes:"
echo "   - Aplicação: /opt/pedidos-veloz"
echo "   - Runner: /opt/pedidos-veloz/runner"
echo "   - Repositório: /opt/pedidos-veloz/pedidos-veloz"
echo ""