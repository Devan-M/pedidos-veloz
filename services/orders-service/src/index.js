require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const redis = require('redis');
const amqp = require('amqplib');
const pinoHttp = require('pino-http');
const { v4: uuidv4 } = require('uuid');
const { register, Counter, Histogram, Gauge } = require('prom-client');

const app = express();
const PORT = process.env.ORDERS_SERVICE_PORT || 3001;

// Logging
const logger = pinoHttp({
  level: process.env.LOG_LEVEL || 'info',
});

app.use(logger);
app.use(express.json());

// Database connection
const pool = new Pool({
  user: process.env.POSTGRES_USER,
  password: process.env.POSTGRES_PASSWORD,
  host: process.env.POSTGRES_HOST || 'postgres',
  port: process.env.POSTGRES_PORT || 5432,
  database: process.env.POSTGRES_DB,
});

// Redis connection
const redisClient = redis.createClient({
  host: process.env.REDIS_HOST || 'redis',
  port: process.env.REDIS_PORT || 6379,
  password: process.env.REDIS_PASSWORD,
});

redisClient.on('error', (err) => console.error('Redis error:', err));
redisClient.connect();

// RabbitMQ connection
let channel;
const connectRabbitMQ = async () => {
  try {
    const connection = await amqp.connect(
      `amqp://${process.env.RABBITMQ_DEFAULT_USER}:${process.env.RABBITMQ_DEFAULT_PASS}@${process.env.RABBITMQ_HOST}:5672`
    );
    channel = await connection.createChannel();
    await channel.assertExchange('orders', 'topic', { durable: true });
    console.log('RabbitMQ connected');
  } catch (error) {
    console.error('RabbitMQ connection error:', error);
    setTimeout(connectRabbitMQ, 5000);
  }
};

connectRabbitMQ();

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

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'orders-service' });
});

// Readiness check
app.get('/ready', async (req, res) => {
  try {
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
  const { customerId, items, totalAmount } = req.body;

  try {
    const orderId = uuidv4();
    const query = `
      INSERT INTO orders (id, customer_id, items, total_amount, status, created_at)
      VALUES ($1, $2, $3, $4, $5, NOW())
      RETURNING *
    `;

    const result = await pool.query(query, [
      orderId,
      customerId,
      JSON.stringify(items),
      totalAmount,
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
            customerId,
            totalAmount,
            timestamp: new Date().toISOString(),
          })
        )
      );
    }

    // Cache no Redis
    await redisClient.setEx(`order:${orderId}`, 3600, JSON.stringify(result.rows[0]));

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

    // Tentar cache primeiro
    const cached = await redisClient.get(`order:${id}`);
    if (cached) {
      return res.json(JSON.parse(cached));
    }

    const result = await pool.query('SELECT * FROM orders WHERE id = $1', [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Order not found' });
    }

    // Cache o resultado
    await redisClient.setEx(`order:${id}`, 3600, JSON.stringify(result.rows[0]));

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

    const result = await pool.query(
      'UPDATE orders SET status = $1, updated_at = NOW() WHERE id = $2 RETURNING *',
      [status, id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Order not found' });
    }

    // Invalidar cache
    await redisClient.del(`order:${id}`);

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

// Inicializar banco de dados
const initDB = async () => {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS orders (
        id UUID PRIMARY KEY,
        customer_id VARCHAR(255) NOT NULL,
        items JSONB NOT NULL,
        total_amount DECIMAL(10, 2) NOT NULL,
        status VARCHAR(50) DEFAULT 'pending',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

      CREATE INDEX IF NOT EXISTS idx_customer_id ON orders(customer_id);
      CREATE INDEX IF NOT EXISTS idx_status ON orders(status);
      CREATE INDEX IF NOT EXISTS idx_created_at ON orders(created_at);
    `);
    console.log('Database initialized');
  } catch (error) {
    console.error('Database initialization error:', error);
    setTimeout(initDB, 5000);
  }
};

// Error handling
app.use((err, req, res, next) => {
  req.log.error(err);
  res.status(500).json({ error: 'Internal Server Error' });
});

// 404
app.use((req, res) => {
  res.status(404).json({ error: 'Not Found' });
});

// Start server
const start = async () => {
  await initDB();
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Orders Service rodando na porta ${PORT}`);
  });
};

start();

module.exports = app;