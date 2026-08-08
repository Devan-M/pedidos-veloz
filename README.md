# Pedidos Veloz

Plataforma distribuída de pedidos baseada em microsserviços.

## Serviços

- `gateway`: entrada HTTP da aplicação
- `orders`: criação e listagem de pedidos
- `payments`: processamento de pagamentos
- `inventory`: reserva de estoque

## Infraestrutura local

- Docker Compose
- PostgreSQL
- RabbitMQ
- Métricas Prometheus em `/metrics`

## Execução local

```bash
docker compose up -d --build
```

Gateway:

```text
http://localhost:8000
```

Health check:

```bash
curl http://localhost:8000/health
```

Parar os serviços:

```bash
docker compose down
```
