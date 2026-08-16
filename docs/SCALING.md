# Escalabilidade - Pedidos Veloz

Guia completo de estratégias de escalabilidade horizontal e vertical.

## Índice

- [Visão Geral](#visão-geral)
- [Escalabilidade Horizontal](#escalabilidade-horizontal)
- [Escalabilidade Vertical](#escalabilidade-vertical)
- [Otimizações de Performance](#otimizações-de-performance)
- [Testes de Carga](#testes-de-carga)
- [Monitoramento de Escalabilidade](#monitoramento-de-escalabilidade)

## Visão Geral

Pedidos Veloz é projetado para escalar em duas dimensões:

1. **Horizontal**: Adicionar mais réplicas de pods
2. **Vertical**: Aumentar CPU/memória de cada pod

## Escalabilidade Horizontal

### Horizontal Pod Autoscaler (HPA)

HPA ajusta automaticamente o número de réplicas baseado em métricas.

#### Configuração Atual

**API Gateway:**
```yaml
minReplicas: 3
maxReplicas: 10
targetCPUUtilizationPercentage: 70
targetMemoryUtilizationPercentage: 80
```

**Orders Service:**
```yaml
minReplicas: 2
maxReplicas: 8
targetCPUUtilizationPercentage: 70
targetMemoryUtilizationPercentage: 80
```

**Inventory Service:**
```yaml
minReplicas: 2
maxReplicas: 8
targetCPUUtilizationPercentage: 70
targetMemoryUtilizationPercentage: 80
```

**Payments Service:**
```yaml
minReplicas: 2
maxReplicas: 8
targetCPUUtilizationPercentage: 70
targetMemoryUtilizationPercentage: 80
```

#### Verificar HPA

```bash
# Ver status do HPA
kubectl get hpa -n pedidos-veloz

# Ver detalhes
kubectl describe hpa api-gateway-hpa -n pedidos-veloz

# Ver métricas
kubectl get hpa api-gateway-hpa -n pedidos-veloz -w
```

#### Ajustar HPA

```bash
# Aumentar max replicas
kubectl patch hpa api-gateway-hpa -n pedidos-veloz \
  -p '{"spec":{"maxReplicas":20}}'

# Alterar target CPU
kubectl patch hpa api-gateway-hpa -n pedidos-veloz \
  -p '{"spec":{"targetCPUUtilizationPercentage":60}}'
```

#### Comportamento de Scale-Up

```yaml
behavior:
  scaleUp:
    stabilizationWindowSeconds: 0
    policies:
    - type: Percent
      value: 100        # Dobrar a cada 30s
      periodSeconds: 30
    - type: Pods
      value: 2          # Ou adicionar 2 pods a cada 30s
      periodSeconds: 30
    selectPolicy: Max   # Usar a maior mudança
```

#### Comportamento de Scale-Down

```yaml
behavior:
  scaleDown:
    stabilizationWindowSeconds: 300  # Esperar 5min antes de reduzir
    policies:
    - type: Percent
      value: 50         # Reduzir 50% a cada 60s
      periodSeconds: 60
```

### Escalabilidade de Banco de Dados

#### PostgreSQL - Read Replicas

```bash
# Criar replica
kubectl exec -n pedidos-veloz postgres-0 -- \
  pg_basebackup -h postgres-0 -D /var/lib/postgresql/replica

# Configurar streaming replication
# Em postgresql.conf:
# wal_level = replica
# max_wal_senders = 10
# max_replication_slots = 10
```

#### Redis - Sentinel

```bash
# Instalar Sentinel
helm install redis-sentinel bitnami/redis-sentinel -n pedidos-veloz

# Configurar master-slave
# sentinel.conf:
# sentinel monitor mymaster 127.0.0.1 6379 1
# sentinel down-after-milliseconds mymaster 5000
# sentinel parallel-syncs mymaster 1
```

#### RabbitMQ - Clustering

```bash
# Criar cluster RabbitMQ
kubectl exec -n pedidos-veloz rabbitmq-0 -- \
  rabbitmqctl join_cluster rabbit@rabbitmq-1

# Ver status do cluster
kubectl exec -n pedidos-veloz rabbitmq-0 -- \
  rabbitmqctl cluster_status
```

## Escalabilidade Vertical

### Vertical Pod Autoscaler (VPA)

VPA recomenda ajustes de CPU/memória baseado em uso histórico.

#### Instalação

```bash
helm repo add fairwinds-stable https://charts.fairwinds.com/stable
helm install vpa fairwinds-stable/vpa -n pedidos-veloz
```

#### Configuração

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: api-gateway-vpa
  namespace: pedidos-veloz
spec:
  targetRef:
    apiVersion: "apps/v1"
    kind: Deployment
    name: api-gateway
  updatePolicy:
    updateMode: "Auto"  # Auto, Recreate, Initial, Off
  resourcePolicy:
    containerPolicies:
    - containerName: api-gateway
      minAllowed:
        cpu: 100m
        memory: 128Mi
      maxAllowed:
        cpu: 1000m
        memory: 1Gi
```

#### Modos de Operação

- **Off**: Desativado
- **Initial**: Recomenda apenas na criação
- **Recreate**: Aplica recomendações recriando pods
- **Auto**: Aplica quando possível (padrão)

#### Ver Recomendações

```bash
# Ver VPA
kubectl get vpa -n pedidos-veloz

# Ver recomendações
kubectl describe vpa api-gateway-vpa -n pedidos-veloz
```

### Resource Requests e Limits

#### Configuração Atual

**API Gateway:**
```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

**Orders Service:**
```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

#### Ajustar Resources

```bash
# Aumentar requests
kubectl set resources deployment/api-gateway \
  --requests=cpu=500m,memory=512Mi \
  -n pedidos-veloz

# Aumentar limits
kubectl set resources deployment/api-gateway \
  --limits=cpu=1000m,memory=1Gi \
  -n pedidos-veloz
```

## Otimizações de Performance

### 1. Cache com Redis

#### Implementação

```javascript
// Node.js - Cache-Aside Pattern
async function getProduct(productId) {
  // 1. Verificar cache
  const cached = await redis.get(`product:${productId}`);
  if (cached) return JSON.parse(cached);

  // 2. Se miss, consultar banco
  const product = await db.query(
    'SELECT * FROM products WHERE id = $1',
    [productId]
  );

  // 3. Armazenar em cache
  await redis.setex(
    `product:${productId}`,
    3600,  // TTL: 1 hora
    JSON.stringify(product)
  );

  return product;
}
```

#### Estratégias de Cache

- **Cache-Aside**: Aplicação gerencia cache
- **Write-Through**: Escrever em cache e banco simultaneamente
- **Write-Behind**: Escrever em cache, depois em banco

### 2. Connection Pooling

#### PostgreSQL

```javascript
const pool = new Pool({
  max: 20,              // Max conexões
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});
```

#### Redis

```javascript
const redis = redis.createClient({
  maxRetriesPerRequest: null,
  enableReadyCheck: false,
  enableOfflineQueue: true,
});
```

### 3. Compressão de Resposta

```javascript
const compression = require('compression');
app.use(compression());  // Gzip compression
```

### 4. Indexação de Banco de Dados

```sql
-- Índices criados
CREATE INDEX idx_customer_id ON orders(customer_id);
CREATE INDEX idx_status ON orders(status);
CREATE INDEX idx_created_at ON orders(created_at);
CREATE INDEX idx_sku ON products(sku);

-- Verificar índices
SELECT * FROM pg_indexes WHERE tablename = 'orders';
```

### 5. Paginação

```javascript
// API com paginação
app.get('/api/orders', (req, res) => {
  const page = req.query.page || 1;
  const limit = req.query.limit || 20;
  const offset = (page - 1) * limit;

  const orders = await db.query(
    'SELECT * FROM orders LIMIT $1 OFFSET $2',
    [limit, offset]
  );

  res.json({
    data: orders,
    page,
    limit,
    total: count
  });
});
```

### 6. Batch Processing

```javascript
// Processar múltiplos pagamentos em batch
async function processBatch(payments) {
  const values = payments
    .map((p, i) => `($${i*3+1}, $${i*3+2}, $${i*3+3})`)
    .join(',');

  const query = `
    INSERT INTO payments (id, order_id, amount)
    VALUES ${values}
  `;

  const flatValues = payments.flatMap(p => [p.id, p.orderId, p.amount]);
  await db.query(query, flatValues);
}
```

## Testes de Carga

### Ferramentas

#### Apache JMeter

```bash
# Instalar
brew install jmeter

# Executar teste
jmeter -n -t test-plan.jmx -l results.jtl -j jmeter.log
```

#### k6 (Recomendado)

```bash
# Instalar
brew install k6

# Executar teste
k6 run load-test.js
```

### Exemplo: Teste com k6

```javascript
// load-test.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 100 },   // Ramp-up
    { duration: '5m', target: 100 },   // Stay
    { duration: '2m', target: 0 },     // Ramp-down
  ],
};

export default function () {
  // Teste de criar pedido
  let response = http.post('http://localhost:8080/api/orders', {
    customerId: 'customer-123',
    items: [{ productId: 'prod-1', quantity: 2 }],
    totalAmount: 99.99,
  });

  check(response, {
    'status is 201': (r) => r.status === 201,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });

  sleep(1);

  // Teste de listar pedidos
  response = http.get('http://localhost:8080/api/orders');

  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 300ms': (r) => r.timings.duration < 300,
  });

  sleep(1);
}
```

### Executar Teste

```bash
# Teste básico
k6 run load-test.js

# Com resultados em arquivo
k6 run --out csv=results.csv load-test.js

# Com InfluxDB
k6 run --out influxdb=http://localhost:8086/k6 load-test.js
```

### Analisar Resultados
checks…………………….: 100.00% ✓ 1200 ✗ 0 data_received………………: 1.2 MB 120 kB/s data_sent…………………..: 600 kB 60 kB/s http_req_blocked…………….: avg=1.2ms min=0.8ms med=1.1ms max=5.2ms p(90)=1.5ms p(95)=1.8ms http_req_connecting………….: avg=0.5ms min=0.3ms med=0.4ms max=2.1ms p(90)=0.6ms p(95)=0.8ms http_req_duration……………: avg=45.2ms min=12.1ms med=42.3ms max=98.5ms p(90)=65.2ms p(95)=72.1ms http_req_receiving…………..: avg=2.1ms min=0.5ms med=1.8ms max=8.2ms p(90)=3.2ms p(95)=4.1ms http_req_sending…………….: avg=1.5ms min=0.8ms med=1.2ms max=4.2ms p(90)=2.1ms p(95)=2.8ms http_req_tls_handshaking……..: avg=0.0ms min=0.0ms med=0.0ms max=0.0ms p(90)=0.0ms p(95)=0.0ms http_req_waiting…………….: avg=41.6ms min=10.2ms med=39.1ms max=90.3ms p(90)=61.2ms p(95)=68.1ms http_reqs……………………: 1200 120/s iteration_duration…………..: avg=2.04s min=2.01s med=2.03s max=2.15s p(90)=2.08s p(95)=2.11s iterations…………………..: 1200 120/s vus……………………….: 100 min=0 max=100 vus_max……………………..: 100 min=100 max=100

## Monitoramento de Escalabilidade

### Métricas Importantes

#### HPA Metrics
# Taxa de scale-up
rate(karpenter_nodes_allocatable[5m])

# Pods pending
karpenter_pods_pending

# Utilização de recursos
sum(rate(container_cpu_usage_seconds_total[5m])) by (pod)
sum(container_memory_usage_bytes) by (pod)

#### Performance Metrics
# Latência durante scaling
histogram_quantile(0.95, http_request_duration_seconds)

# Taxa de erro durante scaling
rate(http_requests_total{status=~"5.."}[5m])

# Throughput
rate(http_requests_total[1m])

### Dashboard de Escalabilidade
# Grafana Dashboard
{
  "dashboard": {
    "title": "Scaling Metrics",
    "panels": [
      {
        "title": "Pod Count",
        "targets": [
          {
            "expr": "count(karpenter_nodes_allocatable)"
          }
        ]
      },
      {
        "title": "CPU Utilization",
        "targets": [
          {
            "expr": "sum(rate(container_cpu_usage_seconds_total[5m])) by (pod)"
          }
        ]
      },
      {
        "title": "Memory Utilization",
        "targets": [
          {
            "expr": "sum(container_memory_usage_bytes) by (pod)"
          }
        ]
      },
      {
        "title": "Request Latency",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, http_request_duration_seconds)"
          }
        ]
      }
    ]
  }
}

## Checklist de Escalabilidade

- [ ] HPA configurado para todos os serviços
- [ ] Resource requests e limits definidos
- [ ] VPA instalado e configurado
- [ ] Cache com Redis implementado
- [ ] Connection pooling configurado
- [ ] Índices de banco de dados otimizados
- [ ] Testes de carga executados
- [ ] Métricas de escalabilidade monitoradas
- [ ] Alertas de escalabilidade configurados
- [ ] Runbooks de scaling criados

## Referências

- [Kubernetes HPA Documentation](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Kubernetes VPA Documentation](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
- [k6 Load Testing](https://k6.io/)
- [PostgreSQL Performance Tuning](https://www.postgresql.org/docs/current/performance-tips.html)
- [Redis Optimization](https://redis.io/topics/optimization)

