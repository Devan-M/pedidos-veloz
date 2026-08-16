# Pedidos Veloz 🚀

Sistema de Gerenciamento de Pedidos com Arquitetura de Microserviços, Orquestração de Containers e DevOps.

**Projeto Acadêmico**: Demonstração prática de containerização, Kubernetes, CI/CD, observabilidade e escalabilidade.

## 📋 Índice

- [Visão Geral](#visão-geral)
- [Requisitos](#requisitos)
- [Início Rápido](#início-rápido)
- [Arquitetura](#arquitetura)
- [Documentação](#documentação)
- [CI/CD](#cicd-pipeline)
- [Segurança](#segurança)
- [Observabilidade](#observabilidade)
- [Escalabilidade](#escalabilidade)

## 🎯 Visão Geral

**Pedidos Veloz** é um sistema de e-commerce que demonstra as melhores práticas de:

- ✅ **Microserviços**: 4 serviços independentes (API Gateway, Orders, Inventory, Payments)
- ✅ **Containerização**: Docker com multi-stage builds e boas práticas de segurança
- ✅ **Orquestração**: Kubernetes com deployments, services, HPA, VPA
- ✅ **CI/CD**: GitHub Actions com build, testes, lint e deploy automático
- ✅ **Observabilidade**: Prometheus, Grafana, ELK Stack, Jaeger
- ✅ **Escalabilidade**: HPA baseado em CPU/memória, VPA para otimização
- ✅ **Segurança**: Pod Security Admission, Network Policies, RBAC, secrets management

## 🛠️ Requisitos

### Para Ambiente Local (Docker Compose)

- Docker >= 20.10
- Docker Compose >= 2.0
- Git >= 2.30
- curl (para testes de API)

### Para Kubernetes

- kubectl >= 1.28
- k3d >= 5.0 (para cluster local)
- Docker >= 20.10

### Tecnologias

- Backend: Node.js 20 (Gateway, Orders, Inventory) + Python 3.11 (Payments)
- Banco de Dados: PostgreSQL 16
- Cache: Redis 7
- Message Queue: RabbitMQ 3.12
- Observabilidade: Prometheus, Grafana, ELK Stack, Jaeger

## 🚀 Início Rápido

### 1. Clone o Repositório

```bash
git clone https://github.com/Devan-M/pedidos-veloz.git
cd pedidos-veloz
```

### 2. Configure Variáveis de Ambiente

```bash
cp .env.example .env
# Edite .env se necessário (valores padrão funcionam para desenvolvimento)
```

### 3. Deploy Local (Docker Compose)

**Opção A: Com Script**

```bash
chmod +x scripts/deploy-local.sh
./scripts/deploy-local.sh
```

**Opção B: Manualmente**

```bash
docker-compose up -d
```

### 4. Acesse os Serviços

| Serviço | URL | Credenciais |
|---------|-----|-------------|
| API Gateway | http://localhost:8080 | - |
| Orders Service | http://localhost:3001 | - |
| Inventory Service | http://localhost:3003 | - |
| Payments Service | http://localhost:3002 | - |
| Prometheus | http://localhost:9090 | - |
| Grafana | http://localhost:3000 | admin / admin123 |
| RabbitMQ | http://localhost:15672 | guest / guest |
| PostgreSQL | localhost:5432 | pedidos_user / secure_password_123 |

### 5. Teste a API

```bash
# Health check
curl http://localhost:8080/health

# Criar pedido
curl -X POST http://localhost:8080/api/orders \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "customer-123",
    "items": [{"productId": "prod-1", "quantity": 2}],
    "totalAmount": 99.99
  }'

# Listar pedidos
curl http://localhost:8080/api/orders

# Criar produto
curl -X POST http://localhost:8080/api/inventory/products \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Produto Teste",
    "sku": "SKU-001",
    "quantity": 100,
    "price": 49.99
  }'
```

## 🏗️ Arquitetura

### Estrutura de Pastas
pedidos-veloz/ ├── services/ │ ├── api-gateway/ # Node.js - Gateway (porta 8080) │ │ ├── Dockerfile │ │ ├── package.json │ │ ├── src/ │ │ │ └── index.js │ │ └── .dockerignore │ ├── orders-service/ # Node.js - Pedidos (porta 3001) │ │ ├── Dockerfile │ │ ├── package.json │ │ ├── src/ │ │ │ └── index.js │ │ └── .dockerignore │ ├── inventory-service/ # Node.js - Inventário (porta 3003) │ │ ├── Dockerfile │ │ ├── package.json │ │ ├── src/ │ │ │ └── index.js │ │ └── .dockerignore │ └── payments-service/ # Python - Pagamentos (porta 3002) │ ├── Dockerfile │ ├── requirements.txt │ ├── src/ │ │ └── app.py │ └── .dockerignore ├── k8s/ # Kubernetes │ ├── base/ │ │ ├── namespace.yaml │ │ ├── configmap.yaml │ │ ├── secret.yaml │ │ ├── rbac.yaml │ │ ├── postgres-deployment.yaml │ │ ├── redis-deployment.yaml │ │ ├── rabbitmq-deployment.yaml │ │ ├── api-gateway-deployment.yaml │ │ ├── orders-service-deployment.yaml │ │ ├── inventory-service-deployment.yaml │ │ └── payments-service-deployment.yaml │ ├── monitoring/ │ │ ├── prometheus.yml │ │ ├── prometheus-deployment.yaml │ │ └── grafana-deployment.yaml │ └── security/ │ ├── pod-security-policy.yaml │ └── network-policy.yaml ├── .github/workflows/ # CI/CD │ ├── build.yml │ ├── test.yml │ └── deploy.yml ├── scripts/ │ ├── deploy-local.sh │ └── deploy-k8s.sh ├── docs/ # Documentação │ ├── ARCHITECTURE.md │ ├── DEPLOYMENT.md │ ├── OBSERVABILITY.md │ └── SCALING.md ├── docker-compose.yml ├── .env.example └── README.md

### Diagrama de Componentes
┌─────────────────────────────────────────────────────────┐ │ Cliente/Browser │ └────────────────────────┬────────────────────────────────┘ │ ▼ ┌─────────────────────────────────────────────────────────┐ │ API Gateway (Node.js) │ │ ├─ Rate Limiting │ │ ├─ Authentication │ │ └─ Request Routing │ └────────────────┬────────────────┬──────────────┬────────┘ │ │ │ ┌────────▼──────┐ ┌──────▼────────┐ ┌─▼──────────┐ │ Orders Service│ │Inventory Svc │ │Payments Svc│ │ (Node.js) │ │ (Node.js) │ │ (Python) │ └────────┬──────┘ └──────┬────────┘ └─┬──────────┘ │ │ │ ┌────────▼────────────────▼──────────────▼────────┐ │ PostgreSQL (Banco de Dados) │ └──────────────────────────────────────────────────┘ │ ┌────────────────┼────────────────┐ │ │ │ ┌───▼───┐ ┌───▼────┐ ┌───▼──────┐ │ Redis │ │RabbitMQ│ │Prometheus│ │(Cache)│ │ (Queue)│ │(Métricas)│ └───────┘ └────────┘ └──────────┘ │ ┌────▼─────┐ │ Grafana │ │(Dashbrd) │ └──────────┘

## 📚 Documentação

Consulte os arquivos de documentação para mais detalhes:

- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Detalhes técnicos da arquitetura
- **[DEPLOYMENT.md](docs/DEPLOYMENT.md)** - Guias de deploy (local e Kubernetes)
- **[OBSERVABILITY.md](docs/OBSERVABILITY.md)** - Métricas, logs e tracing
- **[SCALING.md](docs/SCALING.md)** - Estratégias de escalabilidade (HPA, VPA)

## 🔄 CI/CD Pipeline

O projeto usa **GitHub Actions** para automação:

### Workflows Disponíveis

1. **build.yml** - Build e push de imagens Docker
   - Triggered: Push em main/develop
   - Ações: Build, tag, push para registry

2. **test.yml** - Testes e lint
   - Triggered: Push em main/develop
   - Ações: Lint, testes unitários, security scan

3. **deploy.yml** - Deploy automático em Kubernetes
   - Triggered: Push em main
   - Ações: Apply manifests, wait for rollout

### Secrets Necessários

Configure no GitHub (Settings > Secrets and variables > Actions):
KUBE_CONFIG # Base64 encoded kubeconfig REGISTRY_USERNAME # Docker registry username REGISTRY_PASSWORD # Docker registry password

## 🔒 Segurança

### Boas Práticas Implementadas

- ✅ **Usuários não-root**: Todos os containers rodam com usuários não-root
- ✅ **Read-only filesystem**: Quando possível
- ✅ **Network Policies**: Restrição de tráfego entre pods
- ✅ **Pod Security Admission**: Políticas de segurança de pods
- ✅ **Secrets Management**: Uso de Kubernetes Secrets
- ✅ **RBAC**: Role-based access control
- ✅ **Resource Limits**: CPU e memória definidos
- ✅ **Capability Dropping**: Capacidades Linux removidas

### Scan de Vulnerabilidades

# Trivy scan
trivy fs .

# Docker scan
docker scan pedidos-veloz/api-gateway:latest

# Snyk scan
snyk test

## 📊 Observabilidade

### Métricas (Prometheus)

Acesse em: http://localhost:9090

**Métricas disponíveis:**
- `http_requests_total` - Total de requisições
- `http_request_duration_seconds` - Latência de requisições
- `orders_total` - Total de pedidos
- `payments_total` - Total de pagamentos
- `inventory_operations_total` - Operações de inventário

### Dashboards (Grafana)

Acesse em: http://localhost:3000 (user: admin, pass: admin123)

**Dashboards pré-configurados:**
- API Gateway Metrics
- Orders Service Metrics
- Payments Service Metrics
- System Resources

### Logs

Estruturados com Pino (Node.js) e logging (Python)

### Tracing Distribuído (Jaeger)

Instrumentação documentada em [OBSERVABILITY.md](docs/OBSERVABILITY.md)

## 📈 Escalabilidade

### Horizontal Pod Autoscaler (HPA)

Configurado para cada serviço:

minReplicas: 2
maxReplicas: 10
targetCPUUtilizationPercentage: 70
targetMemoryUtilizationPercentage: 80

### Vertical Pod Autoscaler (VPA)

Recomendações documentadas em [SCALING.md](docs/SCALING.md)

### Estratégias de Deploy

- **Rolling Update**: Deploy padrão com zero downtime
- **Blue-Green**: Documentado em [DEPLOYMENT.md](docs/DEPLOYMENT.md)
- **Canary**: Documentado em [DEPLOYMENT.md](docs/DEPLOYMENT.md)

## 🚀 Deploy em Produção

### Kubernetes (k3s/EKS/GKE)

# Com script
chmod +x scripts/deploy-k8s.sh
./scripts/deploy-k8s.sh

# Ou manualmente
kubectl apply -f k8s/base/namespace.yaml
kubectl apply -f k8s/base/configmap.yaml
kubectl apply -f k8s/base/secret.yaml
kubectl apply -f k8s/base/rbac.yaml
kubectl apply -f k8s/base/*.yaml
kubectl apply -f k8s/monitoring/*.yaml
kubectl apply -f k8s/security/*.yaml

### Variáveis de Ambiente

Edite `k8s/base/secret.yaml` com valores seguros:

POSTGRES_PASSWORD: seu_password_seguro
REDIS_PASSWORD: seu_redis_password
JWT_SECRET: seu_jwt_secret
GRAFANA_ADMIN_PASSWORD: seu_grafana_password

## 🧪 Testes

### Testes Locais (Node.js)

cd services/api-gateway
npm install
npm test

### Testes Python

cd services/payments-service
pip install -r requirements.txt
python -m pytest

## 📝 Parar os Serviços

# Docker Compose
docker-compose down

# Kubernetes
kubectl delete namespace pedidos-veloz


## 🤝 Contribuindo

1. Fork o projeto
2. Crie uma branch para sua feature (`git checkout -b feature/AmazingFeature`)
3. Commit suas mudanças (`git commit -m 'Add some AmazingFeature'`)
4. Push para a branch (`git push origin feature/AmazingFeature`)
5. Abra um Pull Request

## 📝 Licença

Este projeto é licenciado sob a MIT License - veja o arquivo [LICENSE](LICENSE) para detalhes.

## 👨‍💻 Autor

**Devan M.**

- GitHub: [@Devan-M](https://github.com/Devan-M)
- Projeto: [pedidos-veloz](https://github.com/Devan-M/pedidos-veloz)

## 📞 Suporte

Para dúvidas ou problemas:

1. Consulte a [documentação](docs/)
2. Abra uma [issue](https://github.com/Devan-M/pedidos-veloz/issues)
3. Verifique os [logs](#observabilidade)

---

**Última atualização**: 2026-08-16  
**Versão**: 1.0.0  
**Status**: ✅ Funcional