# Arquitetura - Pedidos Veloz

Documentação técnica detalhada da arquitetura do sistema.

## Índice

- [Visão Geral](#visão-geral)
- [Componentes](#componentes)
- [Fluxo de Dados](#fluxo-de-dados)
- [Padrões de Design](#padrões-de-design)
- [Tecnologias](#tecnologias)

## Visão Geral

Pedidos Veloz é um sistema de e-commerce baseado em **arquitetura de microserviços** com os seguintes princípios:

- **Independência**: Cada serviço é independente e pode ser deployado isoladamente
- **Escalabilidade**: Cada serviço pode ser escalado conforme necessário
- **Resiliência**: Falha em um serviço não derruba o sistema inteiro
- **Observabilidade**: Métricas, logs e tracing distribuído em todos os serviços

## Componentes

### 1. API Gateway (Node.js + Express)

**Responsabilidade**: Ponto de entrada único para todas as requisições

**Funcionalidades**:
- Rate limiting (100 req/15min por IP)
- Roteamento de requisições
- Validação de entrada
- Autenticação/Autorização
- Agregação de respostas
- Health checks

**Porta**: 8080

**Dependências**:
- Orders Service
- Inventory Service
- Payments Service

**Endpoints**:

GET /health - Health check GET /ready - Readiness check GET /metrics - Prometheus metrics POST /api/orders - Criar pedido GET /api/orders - Listar pedidos GET /api/orders/:id - Obter pedido PATCH /api/orders/:id - Atualizar pedido POST /api/inventory/products - Criar produto GET /api/inventory/products - Listar produtos GET /api/inventory/products/:id - Obter produto POST /api/payments - Criar pagamento GET /api/payments - Listar pagamentos

### 2. Orders Service (Node.js + Express)

**Responsabilidade**: Gerenciamento de pedidos

**Funcionalidades**:
- Criar pedidos
- Listar pedidos
- Atualizar status de pedidos
- Persistência em PostgreSQL
- Cache em Redis
- Publicação de eventos em RabbitMQ

**Porta**: 3001

**Dependências**:
- PostgreSQL (dados)
- Redis (cache)
- RabbitMQ (eventos)

**Banco de Dados**:

CREATE TABLE orders (
  id UUID PRIMARY KEY,
  customer_id VARCHAR(255) NOT NULL,
  items JSONB NOT NULL,
  total_amount DECIMAL(10, 2) NOT NULL,
  status VARCHAR(50) DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_customer_id ON orders(customer_id);
CREATE INDEX idx_status ON orders(status);
CREATE INDEX idx_created_at ON orders(created_at);

**Eventos Publicados**:
- `order.created` - Quando um pedido é criado
- `order.updated` - Quando um pedido é atualizado

### 3. Inventory Service (Node.js + Express)

**Responsabilidade**: Gerenciamento de inventário

**Funcionalidades**:
- Criar produtos
- Listar produtos
- Atualizar quantidade
- Verificar disponibilidade
- Persistência em PostgreSQL
- Cache em Redis

**Porta**: 3003

**Dependências**:
- PostgreSQL (dados)
- Redis (cache)

**Banco de Dados**:
CREATE TABLE products (
  id UUID PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  sku VARCHAR(100) UNIQUE NOT NULL,
  quantity INTEGER NOT NULL DEFAULT 0,
  price DECIMAL(10, 2) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sku ON products(sku);
CREATE INDEX idx_created_at ON products(created_at);


**Endpoints**:
POST /products - Criar produto GET /products - Listar produtos GET /products/:id - Obter produto PATCH /products/:id/quantity - Atualizar quantidade POST /products/check-availability - Verificar disponibilidade

### 4. Payments Service (Python + Flask)

**Responsabilidade**: Processamento de pagamentos

**Funcionalidades**:
- Criar pagamentos
- Listar pagamentos
- Processar pagamentos
- Persistência em PostgreSQL
- Cache em Redis
- Publicação de eventos em RabbitMQ

**Porta**: 3002

**Dependências**:
- PostgreSQL (dados)
- Redis (cache)
- RabbitMQ (eventos)

**Banco de Dados**:

CREATE TABLE payments (
  id UUID PRIMARY KEY,
  order_id UUID NOT NULL,
  amount DECIMAL(10, 2) NOT NULL,
  payment_method VARCHAR(50) NOT NULL,
  status VARCHAR(50) DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_order_id ON payments(order_id);
CREATE INDEX idx_status ON payments(status);
CREATE INDEX idx_created_at ON payments(created_at);




**Eventos Publicados**:
- `payment.created` - Quando um pagamento é criado
- `payment.processed` - Quando um pagamento é processado

### 5. PostgreSQL

**Responsabilidade**: Banco de dados principal

**Configuração**:
- Versão: 16-alpine
- Usuário: pedidos_user
- Banco: pedidos_veloz
- Porta: 5432

**Persistência**: Volume `postgres_data`

### 6. Redis

**Responsabilidade**: Cache distribuído

**Configuração**:
- Versão: 7-alpine
- Porta: 6379
- Autenticação: Sim (senha configurável)

**Uso**:
- Cache de pedidos
- Cache de produtos
- Cache de pagamentos
- TTL: 3600 segundos (1 hora)

### 7. RabbitMQ

**Responsabilidade**: Message Queue para eventos assíncronos

**Configuração**:
- Versão: 3.12-management-alpine
- Porta AMQP: 5672
- Porta Management: 15672
- Usuário: guest

**Exchanges**:
- `orders` (topic) - Eventos de pedidos
- `payments` (topic) - Eventos de pagamentos

**Routing Keys**:
- `order.created`
- `order.updated`
- `payment.created`
- `payment.processed`

### 8. Prometheus

**Responsabilidade**: Coleta de métricas

**Configuração**:
- Versão: latest
- Porta: 9090
- Retenção: 30 dias

**Scrape Interval**: 15 segundos

### 9. Grafana

**Responsabilidade**: Visualização de métricas

**Configuração**:
- Versão: latest
- Porta: 3000
- Usuário: admin
- Senha: admin123

## Fluxo de Dados

### Criar Pedido
Cliente envia POST /api/orders ao API Gateway
API Gateway valida e roteia para Orders Service
Orders Service:
Valida dados
Insere em PostgreSQL
Invalida cache (se existia)
Publica evento order.created em RabbitMQ
Retorna pedido criado
API Gateway retorna resposta ao cliente
### Processar Pagamento
Cliente envia POST /api/payments ao API Gateway
API Gateway roteia para Payments Service
Payments Service:
Valida dados
Insere em PostgreSQL
Publica evento payment.created em RabbitMQ
Retorna pagamento criado
RabbitMQ notifica Orders Service (se inscrito)
Orders Service atualiza status do pedido
### Verificar Disponibilidade
Cliente envia POST /api/inventory/products/check-availability
API Gateway roteia para Inventory Service
Inventory Service:
Verifica cache em Redis
Se não encontrado, consulta PostgreSQL
Retorna disponibilidade
## Padrões de Design

### 1. API Gateway Pattern

O API Gateway centraliza:
- Autenticação
- Rate limiting
- Roteamento
- Transformação de requisições

### 2. Database per Service

Cada serviço tem seu próprio banco de dados:
- Orders Service: Tabela `orders`
- Inventory Service: Tabela `products`
- Payments Service: Tabela `payments`

Isso garante independência e escalabilidade.

### 3. Event-Driven Architecture

Serviços se comunicam através de eventos:
- Orders Service publica eventos
- Payments Service publica eventos
- RabbitMQ gerencia a fila

### 4. Cache-Aside Pattern
Verificar cache
Se hit, retornar
Se miss:
Consultar banco
Armazenar em cache
Retornar
### 5. Circuit Breaker

Implementado em chamadas HTTP entre serviços para evitar cascata de falhas.

### 6. Health Checks

Cada serviço expõe:
- `/health` - Liveness probe
- `/ready` - Readiness probe

## Tecnologias

### Backend

- **Node.js 20**: API Gateway, Orders Service, Inventory Service
- **Express 4.18**: Framework web
- **Python 3.11**: Payments Service
- **Flask 3.0**: Framework web Python

### Banco de Dados

- **PostgreSQL 16**: Banco de dados principal
- **Redis 7**: Cache distribuído

### Message Queue

- **RabbitMQ 3.12**: Event streaming

### Observabilidade

- **Prometheus**: Coleta de métricas
- **Grafana**: Visualização
- **Pino**: Logging (Node.js)
- **Python logging**: Logging (Python)

### Containerização

- **Docker**: Containerização
- **Docker Compose**: Orquestração local

### Orquestração

- **Kubernetes**: Orquestração em produção
- **k3d**: Cluster local para testes

### CI/CD

- **GitHub Actions**: Automação de build, test, deploy

## Segurança

### Boas Práticas

- Usuários não-root em containers
- Read-only filesystem quando possível
- Network Policies para restrição de tráfego
- RBAC para controle de acesso
- Secrets Management com Kubernetes Secrets
- Resource Limits (CPU e memória)

### Comunicação

- HTTPS em produção
- TLS entre serviços
- Validação de entrada em todos os endpoints

## Performance

### Otimizações

- Cache em Redis (TTL: 1 hora)
- Índices em PostgreSQL
- Connection pooling
- Gzip compression
- CDN para assets estáticos

### Métricas

- Latência p50, p95, p99
- Taxa de erro
- Throughput
- Uso de CPU/memória

## Escalabilidade

### Horizontal

- HPA configurado para cada serviço
- Min replicas: 2
- Max replicas: 10
- Target CPU: 70%
- Target Memory: 80%

### Vertical

- VPA para recomendações de recursos
- Ajuste automático de requests/limits

## Disaster Recovery

### Backup

- PostgreSQL: Snapshots diários
- Redis: Persistência RDB
- Código: Git com múltiplos remotes

### Replicação

- PostgreSQL: Replicação para standby
- Redis: Sentinel para alta disponibilidade

### Failover

- Automático para Kubernetes
- Manual para bancos de dados

