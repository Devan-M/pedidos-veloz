# 🚀 Pedidos Veloz - Microservices Architecture

Sistema de gerenciamento de pedidos com arquitetura de microsserviços em Node.js e Python, deployado em Kubernetes com CI/CD automatizado.

## 📋 Índice

- [Arquitetura](#arquitetura)
- [Serviços](#serviços)
- [Pré-requisitos](#pré-requisitos)
- [Instalação Local](#instalação-local)
- [Testes](#testes)
- [CI/CD Pipeline](#cicd-pipeline)
- [Deployment](#deployment)
- [Documentação](#documentação)

## 🏗️ Arquitetura

\\\
┌─────────────────────────────────────────────────────────────┐
│                     API Gateway (Express)                    │
│                    Port: 3000                                │
└─────────────────────────────────────────────────────────────┘
           ↓              ↓              ↓
    ┌──────────┐  ┌──────────┐  ┌──────────┐
    │ Orders   │  │Inventory │  │ Payments │
    │Service   │  │ Service  │  │ Service  │
    │(Node.js) │  │(Node.js) │  │(Python)  │
    │3001      │  │3002      │  │3003      │
    └──────────┘  └──────────┘  └──────────┘
           ↓              ↓              ↓
    ┌─────────────────────────────────────────┐
    │    PostgreSQL | Redis | RabbitMQ        │
    └─────────────────────────────────────────┘
\\\

## 🎯 Serviços

### API Gateway
- **Linguagem**: Node.js (Express)
- **Porta**: 3000
- **Responsabilidade**: Roteamento, autenticação, rate limiting
- **Testes**: Jest + Supertest

### Orders Service
- **Linguagem**: Node.js (Express)
- **Porta**: 3001
- **Responsabilidade**: Gerenciamento de pedidos
- **Testes**: 4 testes unitários (47.87% coverage)
- **Cobertura**: Criar, listar, atualizar pedidos

### Inventory Service
- **Linguagem**: Node.js (Express)
- **Porta**: 3002
- **Responsabilidade**: Gerenciamento de estoque
- **Testes**: 5 testes unitários (53.5% coverage)
- **Cobertura**: Produtos, disponibilidade, quantidade

### Payments Service
- **Linguagem**: Python (Flask)
- **Porta**: 3003
- **Responsabilidade**: Processamento de pagamentos
- **Testes**: 10 testes unitários (74% coverage)
- **Cobertura**: Criar, processar, rastrear pagamentos

## 📦 Pré-requisitos

### Local Development
- **Node.js** 18+ ([Download](https://nodejs.org/))
- **Python** 3.9+ ([Download](https://www.python.org/))
- **Docker** e **Docker Compose** ([Download](https://www.docker.com/))
- **Git**

### Verificar instalação
\\\powershell
node --version
python --version
docker --version
git --version
\\\

## 🛠️ Instalação Local

### 1. Clonar repositório
\\\powershell
git clone https://github.com/Devan-M/pedidos-veloz.git
cd pedidos-veloz
\\\

### 2. Iniciar infraestrutura (Docker Compose)
\\\powershell
docker-compose up -d
\\\

Isso inicia:
- PostgreSQL (porta 5432)
- Redis (porta 6379)
- RabbitMQ (porta 5672, admin: 15672)

### 3. Instalar dependências

**Orders Service**
\\\powershell
cd services/orders-service
npm install
\\\

**Inventory Service**
\\\powershell
cd services/inventory-service
npm install
\\\

**Payments Service**
\\\powershell
cd services/payments-service
pip install -r requirements.txt
\\\

### 4. Configurar variáveis de ambiente

Crie \.env\ em cada serviço:

**services/orders-service/.env**
\\\
NODE_ENV=development
PORT=3001
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/pedidos_veloz
REDIS_URL=redis://localhost:6379
RABBITMQ_URL=amqp://guest:guest@localhost:5672
LOG_LEVEL=info
\\\

**services/inventory-service/.env**
\\\
NODE_ENV=development
INVENTORY_SERVICE_PORT=3002
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/pedidos_veloz
REDIS_URL=redis://localhost:6379
RABBITMQ_URL=amqp://guest:guest@localhost:5672
LOG_LEVEL=info
\\\

**services/payments-service/.env**
\\\
FLASK_ENV=development
PAYMENTS_SERVICE_PORT=3003
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/pedidos_veloz
REDIS_URL=redis://localhost:6379
RABBITMQ_URL=amqp://guest:guest@localhost:5672
LOG_LEVEL=info
\\\

### 5. Iniciar serviços

**Orders Service**
\\\powershell
cd services/orders-service
npm start
\\\

**Inventory Service** (novo terminal)
\\\powershell
cd services/inventory-service
npm start
\\\

**Payments Service** (novo terminal)
\\\powershell
cd services/payments-service
python -m flask run --port 3003
\\\

**API Gateway** (novo terminal)
\\\powershell
cd services/api-gateway
npm start
\\\

## 🧪 Testes

### Rodar todos os testes localmente

**Orders Service**
\\\powershell
cd services/orders-service
npm test
\\\

**Inventory Service**
\\\powershell
cd services/inventory-service
npm test
\\\

**Payments Service**
\\\powershell
cd services/payments-service
python -m pytest tests/ -v --cov=app
\\\

### Cobertura de testes

| Serviço | Testes | Coverage |
|---------|--------|----------|
| Orders | 4 ✅ | 47.87% |
| Inventory | 5 ✅ | 53.5% |
| Payments | 10 ✅ | 74% |
| **Total** | **19 ✅** | **~58%** |

### Rodar testes com watch mode (Node.js)
\\\powershell
npm test -- --watch
\\\

### Gerar relatório HTML de cobertura
\\\powershell
# Node.js
npm test -- --coverage

# Python
python -m pytest tests/ --cov=app --cov-report=html
\\\

## 🔄 CI/CD Pipeline

### GitHub Actions Workflows

Temos 3 workflows configurados:

#### 1. **test.yml** - Testes e Lint
- Roda em: \push\ e \pull_request\ nas branches \main\ e \develop\
- Executa:
  - Testes unitários (Jest + pytest)
  - Linting (ESLint + pylint)
  - Scan de segurança (Trivy)
  - Upload de cobertura (Codecov)

#### 2. **build.yml** - Build e Push de Docker
- Roda em: \push\ na branch \main\
- Constrói imagens Docker para:
  - api-gateway
  - orders-service
  - inventory-service
  - payments-service
- Faz push para GitHub Container Registry (GHCR)

#### 3. **deploy.yml** - Deploy em Kubernetes
- Roda em: \push\ na branch \main\ (com arquivos em \k8s/\)
- Deploya em cluster Kubernetes
- Requer \KUBE_CONFIG\ secret configurado

### Status do Pipeline

Veja o status em: https://github.com/Devan-M/pedidos-veloz/actions

### Badges

[![Tests](https://github.com/Devan-M/pedidos-veloz/actions/workflows/test.yml/badge.svg)](https://github.com/Devan-M/pedidos-veloz/actions/workflows/test.yml)
[![Build](https://github.com/Devan-M/pedidos-veloz/actions/workflows/build.yml/badge.svg)](https://github.com/Devan-M/pedidos-veloz/actions/workflows/build.yml)
[![Deploy](https://github.com/Devan-M/pedidos-veloz/actions/workflows/deploy.yml/badge.svg)](https://github.com/Devan-M/pedidos-veloz/actions/workflows/deploy.yml)

## 🚀 Deployment

### Kubernetes

\\\powershell
# Aplicar configurações
kubectl apply -f k8s/base/

# Verificar deployments
kubectl get deployments -n pedidos-veloz

# Ver logs
kubectl logs -f deployment/orders-service -n pedidos-veloz
\\\

### Docker Compose (Desenvolvimento)

\\\powershell
# Iniciar tudo
docker-compose up -d

# Parar
docker-compose down

# Ver logs
docker-compose logs -f orders-service
\\\

## 📚 Documentação

### Endpoints da API

#### Health Checks
\\\
GET /health - Status do serviço
GET /ready - Readiness probe
GET /metrics - Métricas Prometheus
\\\

#### Orders Service
\\\
GET    /orders - Listar pedidos
POST   /orders - Criar pedido
GET    /orders/:id - Obter pedido
PATCH  /orders/:id - Atualizar pedido
\\\

#### Inventory Service
\\\
GET    /inventory - Listar produtos
POST   /inventory - Criar produto
GET    /inventory/:id - Obter produto
PATCH  /inventory/:id - Atualizar quantidade
POST   /inventory/check-availability - Verificar disponibilidade
\\\

#### Payments Service
\\\
GET    /payments - Listar pagamentos
POST   /payments - Criar pagamento
GET    /payments/:id - Obter pagamento
PATCH  /payments/:id - Processar pagamento
\\\

### Variáveis de Ambiente

Veja \.env.example\ em cada serviço para todas as opções disponíveis.

### Estrutura do Projeto

\\\
pedidos-veloz/
├── .github/
│   └── workflows/
│       ├── test.yml
│       ├── build.yml
│       └── deploy.yml
├── services/
│   ├── api-gateway/
│   ├── orders-service/
│   │   ├── src/
│   │   ├── __tests__/
│   │   └── package.json
│   ├── inventory-service/
│   │   ├── src/
│   │   ├── __tests__/
│   │   └── package.json
│   └── payments-service/
│       ├── app.py
│       ├── tests/
│       └── requirements.txt
├── k8s/
│   ├── base/
│   ├── monitoring/
│   └── security/
├── docker-compose.yml
└── README.md
\\\

## 🤝 Contribuindo

1. Crie uma branch: \git checkout -b feature/minha-feature\
2. Faça commit: \git commit -m "feat: descrição"\
3. Rode testes: \
pm test\ ou \pytest tests/\
4. Faça push: \git push origin feature/minha-feature\
5. Abra um Pull Request

### Padrão de Commits

Usamos [Conventional Commits](https://www.conventionalcommits.org/):

\\\
feat: adicionar nova funcionalidade
fix: corrigir bug
test: adicionar testes
ci: atualizar CI/CD
docs: atualizar documentação
chore: tarefas de manutenção
\\\

## 📊 Monitoramento

### Prometheus
- URL: http://localhost:9090
- Métricas disponíveis em \/metrics\

### Grafana
- URL: http://localhost:3000
- Dashboards pré-configurados

### Logs
- ELK Stack (Elasticsearch, Logstash, Kibana)
- Visualizar em: http://localhost:5601

## 🔒 Segurança

- Network Policies configuradas
- Pod Security Policies ativadas
- Secrets gerenciados por Kubernetes
- Scan de vulnerabilidades (Trivy) no CI/CD
- RBAC configurado

## 📝 Licença

MIT License - veja [LICENSE](LICENSE) para detalhes

## 👨‍💻 Autor

**Devan M**
- GitHub: [@Devan-M](https://github.com/Devan-M)
- Repositório: [pedidos-veloz](https://github.com/Devan-M/pedidos-veloz)

## 📞 Suporte

Para dúvidas ou problemas:
1. Abra uma [Issue](https://github.com/Devan-M/pedidos-veloz/issues)
2. Verifique a documentação em \/docs\
3. Veja os logs: \docker-compose logs\

---

**Última atualização**: Agosto 2026
