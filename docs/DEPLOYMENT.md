# Deployment - Pedidos Veloz

Guias completos de deployment para diferentes ambientes.

## Índice

- [Deploy Local (Docker Compose)](#deploy-local-docker-compose)
- [Deploy em Kubernetes](#deploy-em-kubernetes)
- [Deploy em Produção](#deploy-em-produção)
- [Troubleshooting](#troubleshooting)

## Deploy Local (Docker Compose)

### Pré-requisitos

- Docker >= 20.10
- Docker Compose >= 2.0
- Git >= 2.30
- 4GB RAM disponível
- 20GB espaço em disco

### Passo 1: Clone o Repositório

```bash
git clone https://github.com/Devan-M/pedidos-veloz.git
cd pedidos-veloz
```

### Passo 2: Configure Variáveis de Ambiente

```bash
cp .env.example .env
```

**Arquivo `.env` padrão:**
ENVIRONMENT=development LOG_LEVEL=info APP_VERSION=1.0.0

POSTGRES_USER=pedidos_user POSTGRES_PASSWORD=secure_password_123 POSTGRES_HOST=postgres POSTGRES_PORT=5432 POSTGRES_DB=pedidos_veloz

REDIS_HOST=redis REDIS_PORT=6379 REDIS_PASSWORD=redis_password_123

RABBITMQ_DEFAULT_USER=guest RABBITMQ_DEFAULT_PASS=guest RABBITMQ_HOST=rabbitmq RABBITMQ_PORT=5672 RABBITMQ_MANAGEMENT_PORT=15672

API_GATEWAY_PORT=8080 ORDERS_SERVICE_PORT=3001 INVENTORY_SERVICE_PORT=3003 PAYMENTS_SERVICE_PORT=3002

PROMETHEUS_PORT=9090 GRAFANA_PORT=3000 GRAFANA_ADMIN_PASSWORD=admin123

### Passo 3: Build das Imagens
docker-compose build


**Ou com script:**
chmod +x scripts/deploy-local.sh
./scripts/deploy-local.sh


### Passo 4: Inicie os Serviços
docker-compose up -d

### Passo 5: Verifique o Status
# Ver logs
docker-compose logs -f

# Ver containers rodando
docker-compose ps

# Health check
curl http://localhost:8080/health

### Passo 6: Acesse os Serviços

| Serviço | URL |
|---------|-----|
| API Gateway | http://localhost:8080 |
| Prometheus | http://localhost:9090 |
| Grafana | http://localhost:3000 |
| RabbitMQ | http://localhost:15672 |

### Parar os Serviços
docker-compose down

# Com volumes (limpa dados)
docker-compose down -v


## Deploy em Kubernetes

### Pré-requisitos

- kubectl >= 1.28
- k3d >= 5.0 (para cluster local)
- Docker >= 20.10
- 8GB RAM disponível
- 30GB espaço em disco

### Opção 1: Cluster Local com k3d

#### Criar Cluster
k3d cluster create pedidos \
  --agents 2 \
  -p "8080:30080@loadbalancer" \
  -p "3000:30300@loadbalancer" \
  -p "9090:30900@loadbalancer"

  #### Usar Script de Deploy
chmod +x scripts/deploy-k8s.sh
./scripts/deploy-k8s.sh

#### Ou Deploy Manual
# 1. Criar namespace
kubectl create namespace pedidos-veloz

# 2. Aplicar ConfigMaps e Secrets
kubectl apply -f k8s/base/configmap.yaml
kubectl apply -f k8s/base/secret.yaml

# 3. Aplicar RBAC
kubectl apply -f k8s/base/rbac.yaml

# 4. Aplicar infraestrutura
kubectl apply -f k8s/base/postgres-deployment.yaml
kubectl apply -f k8s/base/redis-deployment.yaml
kubectl apply -f k8s/base/rabbitmq-deployment.yaml

# 5. Aguardar infraestrutura
kubectl wait --for=condition=ready pod -l app=postgres -n pedidos-veloz --timeout=300s

# 6. Aplicar security policies
kubectl apply -f k8s/security/network-policy.yaml

# 7. Aplicar microserviços
kubectl apply -f k8s/base/api-gateway-deployment.yaml
kubectl apply -f k8s/base/orders-service-deployment.yaml
kubectl apply -f k8s/base/inventory-service-deployment.yaml
kubectl apply -f k8s/base/payments-service-deployment.yaml

# 8. Aplicar monitoramento
kubectl apply -f k8s/monitoring/prometheus-deployment.yaml
kubectl apply -f k8s/monitoring/grafana-deployment.yaml

# 9. Verificar status
kubectl get pods -n pedidos-veloz

#### Acessar Serviços
# Port forward para API Gateway
kubectl port-forward -n pedidos-veloz svc/api-gateway-service 8080:80

# Port forward para Grafana
kubectl port-forward -n pedidos-veloz svc/grafana-service 3000:3000

# Port forward para Prometheus
kubectl port-forward -n pedidos-veloz svc/prometheus-service 9090:9090

#### Deletar Cluster
k3d cluster delete pedidos

### Opção 2: EKS (AWS)

#### Pré-requisitos

- AWS CLI configurado
- eksctl instalado
- IAM permissions apropriadas

#### Criar Cluster
eksctl create cluster \
  --name pedidos-veloz \
  --region us-east-1 \
  --nodegroup-name workers \
  --node-type t3.medium \
  --nodes 3 \
  --nodes-min 2 \
  --nodes-max 10

#### Deploy
# Configurar kubeconfig
aws eks update-kubeconfig --name pedidos-veloz --region us-east-1

# Deploy (mesmo processo que k3d)
./scripts/deploy-k8s.sh

### Opção 3: GKE (Google Cloud)

#### Pré-requisitos

- Google Cloud SDK configurado
- gcloud CLI instalado
- Projeto GCP criado

#### Criar Cluster
gcloud container clusters create pedidos-veloz \
  --zone us-central1-a \
  --num-nodes 3 \
  --machine-type n1-standard-2 \
  --enable-autoscaling \
  --min-nodes 2 \
  --max-nodes 10

#### Deploy
# Configurar kubeconfig
gcloud container clusters get-credentials pedidos-veloz --zone us-central1-a

# Deploy
./scripts/deploy-k8s.sh

## Deploy em Produção

### Checklist Pré-Deploy

- [ ] Secrets configurados com valores seguros
- [ ] Resource limits ajustados
- [ ] HPA configurado
- [ ] Monitoring ativado
- [ ] Backups configurados
- [ ] Disaster recovery testado
- [ ] Load balancer configurado
- [ ] SSL/TLS ativado
- [ ] Network policies aplicadas
- [ ] Pod security policies aplicadas

### Variáveis de Ambiente Seguras

**Editar `k8s/base/secret.yaml`:**

apiVersion: v1
kind: Secret
metadata:
  name: pedidos-secrets
  namespace: pedidos-veloz
type: Opaque
stringData:
  POSTGRES_USER: seu_usuario_seguro
  POSTGRES_PASSWORD: SenhaForte123!@#
  REDIS_PASSWORD: SenhaRedis123!@#
  RABBITMQ_DEFAULT_USER: seu_usuario
  RABBITMQ_DEFAULT_PASS: SenhaRabbit123!@#
  JWT_SECRET: SeuJWTSecretMuitoLongo123!@#
  API_KEY: SeuAPIKeySeguro123!@#
  GRAFANA_ADMIN_PASSWORD: SenhaGrafana123!@#

### Estratégias de Deploy

#### Rolling Update (Padrão)
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0



**Vantagens**: Zero downtime, rollback automático
**Desvantagens**: Requer 2x recursos

#### Blue-Green Deploy
# Deploy versão nova (green)
kubectl set image deployment/api-gateway \
  api-gateway=pedidos-veloz/api-gateway:v2.0.0 \
  -n pedidos-veloz

# Testar green
kubectl port-forward -n pedidos-veloz svc/api-gateway-service 8080:80

# Se OK, fazer rollout
kubectl rollout status deployment/api-gateway -n pedidos-veloz

# Se erro, rollback
kubectl rollout undo deployment/api-gateway -n pedidos-veloz

#### Canary Deploy
# Deploy 10% do tráfego para versão nova
kubectl set image deployment/api-gateway \
  api-gateway=pedidos-veloz/api-gateway:v2.0.0 \
  -n pedidos-veloz

# Monitorar métricas
kubectl top pods -n pedidos-veloz

# Se OK, aumentar para 50%
kubectl scale deployment api-gateway --replicas=5 -n pedidos-veloz

# Se OK, aumentar para 100%
kubectl scale deployment api-gateway --replicas=10 -n pedidos-veloz

### Backup e Restore

#### PostgreSQL Backup
# Backup
kubectl exec -n pedidos-veloz postgres-0 -- \
  pg_dump -U pedidos_user pedidos_veloz > backup.sql

# Restore
kubectl exec -n pedidos-veloz postgres-0 -- \
  psql -U pedidos_user pedidos_veloz < backup.sql

# Backup
kubectl exec -n pedidos-veloz redis-0 -- \
  redis-cli BGSAVE

# Copiar arquivo
kubectl cp pedidos-veloz/redis-0:/data/dump.rdb ./redis-backup.rdb

### Monitoramento de Deploy
# Ver status de rollout
kubectl rollout status deployment/api-gateway -n pedidos-veloz

# Ver histórico de deployments
kubectl rollout history deployment/api-gateway -n pedidos-veloz

# Ver eventos
kubectl get events -n pedidos-veloz --sort-by='.lastTimestamp'

# Ver logs
kubectl logs -f deployment/api-gateway -n pedidos-veloz

## Troubleshooting

### Pod não inicia
# Ver logs
kubectl logs <pod-name> -n pedidos-veloz

# Ver descrição
kubectl describe pod <pod-name> -n pedidos-veloz

# Ver eventos
kubectl get events -n pedidos-veloz

### Serviço não responde
# Verificar conectividade
kubectl exec -it <pod-name> -n pedidos-veloz -- \
  curl http://orders-service:3001/health

# Verificar DNS
kubectl exec -it <pod-name> -n pedidos-veloz -- \
  nslookup orders-service

### Erro de conexão com banco de dados
# Verificar se PostgreSQL está rodando
kubectl get pods -l app=postgres -n pedidos-veloz

# Verificar logs do PostgreSQL
kubectl logs -f deployment/postgres -n pedidos-veloz

# Testar conexão
kubectl exec -it postgres-0 -n pedidos-veloz -- \
  psql -U pedidos_user -d pedidos_veloz -c "SELECT 1"

### Alto uso de CPU/Memória
# Ver recursos
kubectl top pods -n pedidos-veloz
kubectl top nodes

# Aumentar limits
kubectl set resources deployment/api-gateway \
  --limits=cpu=1000m,memory=1Gi \
  -n pedidos-veloz

### Problemas com PersistentVolume
# Ver PVCs
kubectl get pvc -n pedidos-veloz

# Ver PVs
kubectl get pv

# Descrever PVC
kubectl describe pvc postgres-pvc -n pedidos-veloz

docker-compose build

