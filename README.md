\# Pedidos Veloz 🚀



Sistema de gerenciamento de pedidos com arquitetura de microsserviços.



\## 🏗️ Arquitetura



\- \*\*API Gateway\*\* (Node.js) - Port 8080

\- \*\*Orders Service\*\* (Node.js) - Port 3001

\- \*\*Payments Service\*\* (Python/Flask) - Port 3002

\- \*\*Inventory Service\*\* (Node.js) - Port 3003

\- \*\*PostgreSQL\*\* - Database

\- \*\*Redis\*\* - Cache

\- \*\*RabbitMQ\*\* - Message Queue

\- \*\*Prometheus\*\* - Monitoring



\## 🚀 Quick Start



```bash

docker-compose up --build

```



\## 📡 API Endpoints



\### Orders

\- GET /api/orders - Listar pedidos

\- POST /api/orders - Criar pedido



\### Inventory

\- GET /api/inventory - Listar produtos

\- POST /api/inventory - Criar produto

\- POST /api/inventory/check-availability - Verificar disponibilidade



\### Payments

\- GET /api/payments - Listar pagamentos

\- POST /api/payments - Criar pagamento



\## 🏥 Health Checks



\- API Gateway: http://localhost:8080/health

\- Orders: http://localhost:3001/health

\- Payments: http://localhost:3002/health

\- Inventory: http://localhost:3003/health



\## 📊 Monitoring



\- Prometheus: http://localhost:9090

\- Metrics: http://localhost:8080/metrics

