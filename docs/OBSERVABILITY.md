# Observabilidade - Pedidos Veloz

Guia completo de observabilidade: métricas, logs, tracing distribuído e alertas.

## Índice

- [Visão Geral](#visão-geral)
- [Métricas (Prometheus)](#métricas-prometheus)
- [Dashboards (Grafana)](#dashboards-grafana)
- [Logs](#logs)
- [Tracing Distribuído (Jaeger)](#tracing-distribuído-jaeger)
- [Alertas](#alertas)

## Visão Geral

Observabilidade em Pedidos Veloz é baseada em 3 pilares:

1. **Métricas** (Prometheus): O quê está acontecendo
2. **Logs** (ELK/Loki): Por quê está acontecendo
3. **Tracing** (Jaeger): Como está acontecendo

## Métricas (Prometheus)

### Acessar Prometheus
URL: http://localhost:9090

### Métricas Disponíveis

#### API Gateway
http_requests_total{service="api-gateway"} http_request_duration_seconds{service="api-gateway"} http_request_size_bytes{service="api-gateway"} http_response_size_bytes{service="api-gateway"}

#### Orders Service
orders_total{status="created|pending|completed|failed"} orders_processing_time_seconds orders_amount_total active_orders

#### Inventory Service
inventory_operations_total{operation="create|update|read"} inventory_quantity{product_id="…"}

#### Payments Service
payments_total{status="created|processed|failed"} payments_amount_total payment_processing_time_seconds active_payments

### Queries Úteis

#### Requisições por segundo (RPS)
rate(http_requests_total[5m])

#### Latência p95
histogram_quantile(0.95, http_request_duration_seconds)

#### Taxa de erro
rate(http_requests_total{status=~"5.."}[5m])

#### Uso de CPU
container_cpu_usage_seconds_total

#### Uso de Memória
container_memory_usage_bytes

#### Pedidos por minuto
rate(orders_total[1m])

#### Valor total de pagamentos
increase(payments_amount_total[1h])



## Dashboards (Grafana)

### Acessar Grafana
URL: http://localhost:3000 User: admin Password: CHANGE_ME

### Dashboards Pré-configurados

#### 1. API Gateway Metrics

**Visualizações**:
- RPS (Requisições por segundo)
- Latência (p50, p95, p99)
- Taxa de erro
- Distribuição de métodos HTTP
- Distribuição de status codes

**Alertas**:
- RPS > 1000
- Latência p95 > 500ms
- Taxa de erro > 1%

#### 2. Orders Service Metrics

**Visualizações**:
- Pedidos por minuto
- Status dos pedidos (pie chart)
- Tempo de processamento
- Valor total de pedidos
- Top clientes

**Alertas**:
- Pedidos falhos > 5%
- Tempo de processamento > 2s

#### 3. Inventory Service Metrics

**Visualizações**:
- Operações por minuto
- Quantidade de produtos
- Produtos com baixo estoque
- Taxa de rotação

**Alertas**:
- Produtos com estoque < 10
- Taxa de erro > 1%

#### 4. Payments Service Metrics

**Visualizações**:
- Pagamentos por minuto
- Valor total processado
- Taxa de sucesso
- Métodos de pagamento (pie chart)

**Alertas**:
- Taxa de falha > 2%
- Tempo de processamento > 3s

#### 5. System Resources

**Visualizações**:
- CPU por pod
- Memória por pod
- Disco por volume
- Network I/O

**Alertas**:
- CPU > 80%
- Memória > 85%
- Disco > 90%

### Criar Dashboard Customizado

1. Acesse http://localhost:3000
2. Clique em "+" > "Dashboard"
3. Clique em "Add panel"
4. Selecione datasource "Prometheus"
5. Escreva query PromQL
6. Configure visualização
7. Salve dashboard

### Exemplo: Dashboard de Performance
{
  "dashboard": {
    "title": "Performance Overview",
    "panels": [
      {
        "title": "RPS",
        "targets": [
          {
            "expr": "rate(http_requests_total[5m])"
          }
        ]
      },
      {
        "title": "Latência p95",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, http_request_duration_seconds)"
          }
        ]
      },
      {
        "title": "Taxa de Erro",
        "targets": [
          {
            "expr": "rate(http_requests_total{status=~\"5..\"}[5m])"
          }
        ]
      }
    ]
  }
}

## Logs

### Estrutura de Logs

#### Node.js (Pino)
{
  "level": 30,
  "time": 1692115200000,
  "pid": 1234,
  "hostname": "api-gateway-pod",
  "req": {
    "id": "req-123",
    "method": "POST",
    "url": "/api/orders",
    "remoteAddress": "10.0.0.1"
  },
  "res": {
    "statusCode": 201,
    "responseTime": 123
  },
  "msg": "Order created successfully"
}

#### Python (logging)
{
  "timestamp": "2026-08-16T00:51:00Z",
  "level": "INFO",
  "logger": "payments-service",
  "message": "Payment processed",
  "payment_id": "pay-123",
  "order_id": "order-456",
  "amount": 99.99,
  "status": "processed"
}


### Acessar Logs

#### Docker Compose
# Todos os logs
docker-compose logs -f

# Logs de um serviço
docker-compose logs -f orders-service

# Últimas 100 linhas
docker-compose logs --tail=100 orders-service

#### Kubernetes
# Logs de um pod
kubectl logs -f deployment/api-gateway -n pedidos-veloz

# Logs de um container específico
kubectl logs -f pod/api-gateway-xyz -n pedidos-veloz

# Logs anteriores (crash)
kubectl logs -p pod/api-gateway-xyz -n pedidos-veloz

# Logs de múltiplos pods
kubectl logs -f -l app=orders-service -n pedidos-veloz

### ELK Stack (Elasticsearch, Logstash, Kibana)

#### Instalação
# Adicionar Elasticsearch
helm repo add elastic https://helm.elastic.co
helm install elasticsearch elastic/elasticsearch -n pedidos-veloz

# Adicionar Logstash
helm install logstash elastic/logstash -n pedidos-veloz

# Adicionar Kibana
helm install kibana elastic/kibana -n pedidos-veloz

#### Acessar Kibana
URL: http://localhost:5601

#### Criar Index Pattern

1. Acesse Kibana
2. Management > Index Patterns
3. Create Index Pattern
4. Pattern: `logstash-*`
5. Time field: `@timestamp`

#### Queries Úteis
Erros nos últimos 5 minutos
level: "ERROR" AND @timestamp: [now-5m TO now]

Latência alta
response_time: [1000 TO *]

Falhas de pagamento
service: "payments-service" AND status: "failed"

## Tracing Distribuído (Jaeger)

### Instalação
# Helm
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm install jaeger jaegertracing/jaeger -n pedidos-veloz

### Acessar Jaeger
URL: http://localhost:16686

# Helm
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm install jaeger jaegertracing/jaeger -n pedidos-veloz

