const express = require('express');
const pinoHttp = require('pino-http');
const { v4: uuidv4 } = require('uuid');
const { register, Counter, Histogram, Gauge } = require('prom-client');

const app = express();

// Logging
const logger = pinoHttp({
  level: (process.env.LOG_LEVEL || 'info').toLowerCase(),
});

app.use(logger);
app.use(express.json());

// Métricas Prometheus
const ordersTotal = new Counter({
  name: 'orders_total',
  help: 'Total number of orders',
  labelNames: ['status'],
});

const ordersProcessingTime = new Histogram({
  name: 'orders_processing_time_seconds',
  help: 'Order processing time in seconds',
});

const activeOrders = new Gauge({
  name: 'active_orders',
  help: 'Number of active orders',
});

// Injetar dependências
let pool, redisClient, channel;

function setDependencies(deps) {
  pool = deps.pool;
  redisClient = deps.redisClient;
  channel = deps.channel;
}

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'orders-service' });
});

// Readiness check
app.get('/ready', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ ready: false, error: 'Database not initialized' });
    }
    await pool.query('SELECT 1');
    res.json({ ready: true });
  } catch (error) {
    res.status(503).json({ ready: false, error: error.message });
  }
});

// Métricas
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Criar pedido
app.post('/orders', async (req, res) => {
  const start = Date.now();
  const { customer_id, items, total_amount } = req.body;

  if (!customer_id || !items || !total_amount) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database unavailable' });
    }

    const orderId = uuidv4();
    const query = `
      INSERT INTO orders (id, customer_id, items, total_amount, status, created_at)
      VALUES ($1, $2, $3, $4, $5, NOW())
      RETURNING *
    `;

    const result = await pool.query(query, [
      orderId,
      customer_id,
      JSON.stringify(items),
      total_amount,
      'pending',
    ]);

    // Publicar evento no RabbitMQ
    if (channel) {
      channel.publish(
        'orders',
        'order.created',
        Buffer.from(
          JSON.stringify({
            orderId,
            customer_id,
            total_amount,
            timestamp: new Date().toISOString(),
          })
        )
      );
    }

    // Cache no Redis
    if (redisClient) {
      await redisClient.setEx(`order:${orderId}`, 3600, JSON.stringify(result.rows[0]));
    }

    ordersTotal.inc({ status: 'created' });
    ordersProcessingTime.observe((Date.now() - start) / 1000);

    res.status(201).json(result.rows[0]);
  } catch (error) {
    req.log.error(error);
    ordersTotal.inc({ status: 'error' });
    res.status(500).json({ error: error.message });
  }
});

// Listar pedidos
app.get('/orders', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database unavailable' });
    }

    const result = await pool.query('SELECT * FROM orders ORDER BY created_at DESC LIMIT 100');
    res.json(result.rows);
  } catch (error) {
    req.log.error(error);
    res.status(500).json({ error: error.message });
  }
});

// Obter pedido específico
app.get('/orders/:id', async (req, res) => {
  try {
    const { id } = req.params;

    if (!pool) {
      return res.status(503).json({ error: 'Database unavailable' });
    }

    // Tentar cache primeiro
    if (redisClient) {
      const cached = await redisClient.get(`order:${id}`);
      if (cached) {
        return res.json(JSON.parse(cached));
      }
    }

    const result = await pool.query('SELECT * FROM orders WHERE id = $1', [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Order not found' });
    }

    // Cache o resultado
    if (redisClient) {
      await redisClient.setEx(`order:${id}`, 3600, JSON.stringify(result.rows[0]));
    }

    res.json(result.rows[0]);
  } catch (error) {
    req.log.error(error);
    res.status(500).json({ error: error.message });
  }
});

// Atualizar status do pedido
app.patch('/orders/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { status } = req.body;

    if (!pool) {
      return res.status(503).json({ error: 'Database unavailable' });
    }

    const result = await pool.query(
      'UPDATE orders SET status = $1, updated_at = NOW() WHERE id = $2 RETURNING *',
      [status, id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Order not found' });
    }

    // Invalidar cache
    if (redisClient) {
      await redisClient.del(`order:${id}`);
    }

    // Publicar evento
    if (channel) {
      channel.publish(
        'orders',
        'order.updated',
        Buffer.from(
          JSON.stringify({
            orderId: id,
            status,
            timestamp: new Date().toISOString(),
          })
        )
      );
    }

    res.json(result.rows[0]);
  } catch (error) {
    req.log.error(error);
    res.status(500).json({ error: error.message });
  }
});

// Error handling
app.use((err, req, res, next) => {
  req.log.error(err);
  res.status(500).json({ error: 'Internal Server Error' });
});

// 404
app.use((req, res) => {
  res.status(404).json({ error: 'Not Found' });
});

module.exports = { app, setDependencies };