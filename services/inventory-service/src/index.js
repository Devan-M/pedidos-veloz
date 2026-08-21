require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const redis = require('redis');
const pinoHttp = require('pino-http');
const { v4: uuidv4 } = require('uuid');
const { register, Counter, Histogram, Gauge } = require('prom-client');

const app = express();
const PORT = process.env.INVENTORY_SERVICE_PORT || 3003;

// Logging
const logger = pinoHttp({
  level: (process.env.LOG_LEVEL || 'info').toLowerCase(),
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
  socket: {
    host: process.env.REDIS_HOST || 'pedidos-redis',
    port: parseInt(process.env.REDIS_PORT) || 6379,
  },
  password: process.env.REDIS_PASSWORD,
});

redisClient.on('error', (err) => console.error('Redis error:', err));
redisClient.connect();

// Métricas Prometheus
const inventoryTotal = new Counter({
  name: 'inventory_operations_total',
  help: 'Total inventory operations',
  labelNames: ['operation', 'status'],
});

const inventoryQuantity = new Gauge({
  name: 'inventory_quantity',
  help: 'Current inventory quantity by product',
  labelNames: ['product_id'],
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'inventory-service' });
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

// Criar produto
app.post('/products', async (req, res) => {
  const { name, sku, quantity, price } = req.body;

  try {
    const productId = uuidv4();
    const query = `
      INSERT INTO products (id, name, sku, quantity, price, created_at)
      VALUES ($1, $2, $3, $4, $5, NOW())
      RETURNING *
    `;

    const result = await pool.query(query, [productId, name, sku, quantity, price]);

    // Cache no Redis
    await redisClient.setEx(
      `product:${productId}`,
      3600,
      JSON.stringify(result.rows[0])
    );

    inventoryTotal.inc({ operation: 'create', status: 'success' });
    inventoryQuantity.set({ product_id: productId }, quantity);

    res.status(201).json(result.rows[0]);
  } catch (error) {
    req.log.error(error);
    inventoryTotal.inc({ operation: 'create', status: 'error' });
    res.status(500).json({ error: error.message });
  }
});

// Listar produtos
app.get('/products', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM products ORDER BY created_at DESC');
    res.json(result.rows);
  } catch (error) {
    req.log.error(error);
    res.status(500).json({ error: error.message });
  }
});

// Obter produto específico
app.get('/products/:id', async (req, res) => {
  try {
    const { id } = req.params;

    // Tentar cache primeiro
    const cached = await redisClient.get(`product:${id}`);
    if (cached) {
      return res.json(JSON.parse(cached));
    }

    const result = await pool.query('SELECT * FROM products WHERE id = $1', [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }

    // Cache o resultado
    await redisClient.setEx(
      `product:${id}`,
      3600,
      JSON.stringify(result.rows[0])
    );

    res.json(result.rows[0]);
  } catch (error) {
    req.log.error(error);
    res.status(500).json({ error: error.message });
  }
});

// Atualizar quantidade
app.patch('/products/:id/quantity', async (req, res) => {
  try {
    const { id } = req.params;
    const { quantity } = req.body;

    const result = await pool.query(
      'UPDATE products SET quantity = $1, updated_at = NOW() WHERE id = $2 RETURNING *',
      [quantity, id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }

    // Invalidar cache
    await redisClient.del(`product:${id}`);

    inventoryTotal.inc({ operation: 'update', status: 'success' });
    inventoryQuantity.set({ product_id: id }, quantity);

    res.json(result.rows[0]);
  } catch (error) {
    req.log.error(error);
    inventoryTotal.inc({ operation: 'update', status: 'error' });
    res.status(500).json({ error: error.message });
  }
});

// Verificar disponibilidade
app.post('/products/check-availability', async (req, res) => {
  try {
    const { items } = req.body; // items: [{ productId, quantity }, ...]

    const results = await Promise.all(
      items.map(async (item) => {
        const result = await pool.query(
          'SELECT id, quantity FROM products WHERE id = $1',
          [item.productId]
        );

        if (result.rows.length === 0) {
          return { productId: item.productId, available: false };
        }

        const available = result.rows[0].quantity >= item.quantity;
        return { productId: item.productId, available, currentQuantity: result.rows[0].quantity };
      })
    );

    const allAvailable = results.every((r) => r.available);

    res.json({ available: allAvailable, items: results });
  } catch (error) {
    req.log.error(error);
    res.status(500).json({ error: error.message });
  }
});

// Inicializar banco de dados
const initDB = async () => {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS products (
        id UUID PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        sku VARCHAR(100) UNIQUE NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 0,
        price DECIMAL(10, 2) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

      CREATE INDEX IF NOT EXISTS idx_sku ON products(sku);
      CREATE INDEX IF NOT EXISTS idx_created_at ON products(created_at);
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
    console.log(`Inventory Service rodando na porta ${PORT}`);
  });
};

start();

module.exports = app;