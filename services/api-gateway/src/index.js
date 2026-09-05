require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const pinoHttp = require('pino-http');
const axios = require('axios');
const { register, Counter, Histogram } = require('prom-client');

const app = express();
const PORT = process.env.API_GATEWAY_PORT || 8080;

// Logging
const logger = pinoHttp({
  level: (process.env.LOG_LEVEL || 'info').toLowerCase(),
});

app.use(logger);

// Segurança
app.use(helmet());
app.use(cors());

// Middleware
app.use(express.json());

// Métricas Prometheus
const httpRequestDuration = new Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
});

const httpRequestTotal = new Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
});

// Middleware de métricas
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestDuration.observe(
      { method: req.method, route: req.route?.path || req.path, status_code: res.statusCode },
      duration
    );
    httpRequestTotal.inc({
      method: req.method,
      route: req.route?.path || req.path,
      status_code: res.statusCode,
    });
  });
  next();
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Readiness check
app.get('/ready', async (req, res) => {
  try {
    // Verificar se os serviços essenciais estão prontos
    const [ordersResponse, inventoryResponse] = await Promise.all([
      axios.get('http://orders-service:3001/ready', { timeout: 2000 }),
      axios.get('http://inventory-service:3003/ready', { timeout: 2000 }),
    ]);

    if (ordersResponse.status !== 200 || inventoryResponse.status !== 200) {
      return res.status(503).json({
        ready: false,
        error: 'Dependency not ready',
      });
    }

    res.json({ ready: true });
  } catch (error) {
    res.status(503).json({
      ready: false,
      error: error.message,
    });
  }
});

// Métricas
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Rate limiting
// Aplicado somente às rotas da API, mantendo health/readiness/metrics
// disponíveis para Kubernetes e Prometheus.
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutos
  max: 100, // Limite de 100 requisições por IP
});

app.use('/api', limiter);

// Proxy para Orders Service
app.use('/api/orders', (req, res) => {
  const path = req.url === '/' ? '' : req.url;
  axios({
    method: req.method,
    url: `http://orders-service:3001/orders${path}`,
    data: req.body,
    headers: { 'Content-Type': 'application/json' },
    timeout: 10000,
  })
    .then(response => res.status(response.status).json(response.data))
    .catch(error => {
      res.status(error.response?.status || 500).json({
        error: 'Erro ao acessar Orders Service',
        message: error.message,
      });
    });
});

// Proxy para Inventory Service
app.use('/api/inventory', (req, res) => {
  const path = req.url === '/' ? '' : req.url;
  axios({
    method: req.method,
    url: `http://inventory-service:3003/products${path}`,
    data: req.body,
    headers: { 'Content-Type': 'application/json' },
    timeout: 10000,
  })
    .then(response => res.status(response.status).json(response.data))
    .catch(error => {
      res.status(error.response?.status || 500).json({
        error: 'Erro ao acessar Inventory Service',
        message: error.message,
      });
    });
});

// Proxy para Payments Service
app.use('/api/payments', (req, res) => {
  const path = req.url === '/' ? '' : req.url;
  axios({
    method: req.method,
    url: `http://payments-service:3002/payments${path}`,
    data: req.body,
    headers: { 'Content-Type': 'application/json' },
    timeout: 10000,
  })
    .then(response => res.status(response.status).json(response.data))
    .catch(error => {
      res.status(error.response?.status || 500).json({
        error: 'Erro ao acessar Payments Service',
        message: error.message,
      });
    });
});

// Rota raiz
app.get('/', (req, res) => {
  res.json({
    service: 'API Gateway',
    version: process.env.APP_VERSION || '1.0.0',
    status: 'running',
  });
});

// Error handling
app.use((err, req, res, next) => {
  req.log.error(err);
  res.status(500).json({
    error: 'Internal Server Error',
    message: err.message,
  });
});

// 404
app.use((req, res) => {
  res.status(404).json({ error: 'Not Found' });
});

// Start server
if (require.main === module) {
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`API Gateway rodando na porta ${PORT}`);
  });
}

module.exports = app;
