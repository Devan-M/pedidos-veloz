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
const productsTotal = new Counter({
  name: 'products_total',
  help: 'Total number of products',
});

const inventoryCheckTime = new Histogram({
  name: 'inventory_check_time_seconds',
  help: 'Inventory check time in seconds',
});

const stockLevel = new Gauge({
  name: 'stock_level',
  help: 'Current stock level',
  labelNames: ['product_id'],
});

// Injetar dependências
let pool, redisClient;

function setDependencies(deps) {
  pool = deps.pool;
  redisClient = deps.redisClient;
}

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'inventory-service' });
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

// Listar produtos
app.get('/inventory', async (req, res) => {
  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database unavailable' });
    }

    const result = await pool.query('SELECT * FROM products ORDER BY created_at DESC LIMIT 100');
    res.json(result.rows);
  } catch (error) {
    req.log.error(error);
    res.status(500).json({ error: error.message });
  }
});

// Criar produto
app.post('/inventory', async (req, res) => {
  const { name, sku, quantity, price } = req.body;

  if (!name || !sku || quantity === undefined || !price) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database unavailable' });
    }

    const productId = uuidv4();
    const query = `
      INSERT INTO products (id, name, sku, quantity, price, created_at)
      VALUES ($1, $2, $3, $4, $5, NOW())
      RETURNING *
    `;

    const result = await pool.query(query, [productId, name, sku, quantity, price]);

    // Cache no Redis
    if (redisClient) {
      await redisClient.setEx(`product:${productId}`, 3600, JSON.stringify(result.rows[0]));
    }

    productsTotal.inc();
    stockLevel.set({ product_id: productId }, quantity);

    res.status(201).json(result.rows[0]);
  } catch (error) {
    req.log.error(error);
    res.status(500).json({ error: error.message });
  }
});

// Obter produto específico
app.get('/inventory/:id', async (req, res) => {
  try {
    const { id } = req.params;

    if (!pool) {
      return res.status(503).json({ error: 'Database unavailable' });
    }

    // Tentar cache primeiro
    if (redisClient) {
      const cached = await redisClient.get(`product:${id}`);
      if (cached) {
        return res.json(JSON.parse(cached));
      }
    }

    const result = await pool.query('SELECT * FROM products WHERE id = $1', [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }

    // Cache o resultado
    if (redisClient) {
      await redisClient.setEx(`product:${id}`, 3600, JSON.stringify(result.rows[0]));
    }

    res.json(result.rows[0]);
  } catch (error) {
    req.log.error(error);
    res.status(500).json({ error: error.message });
  }
});

// Verificar disponibilidade
app.post('/inventory/check-availability', async (req, res) => {
  const start = Date.now();
  const { items } = req.body;

  if (!items || !Array.isArray(items)) {
    return res.status(400).json({ error: 'Invalid items format' });
  }

  try {
    if (!pool) {
      return res.status(503).json({ error: 'Database unavailable' });
    }

    const productIds = items.map(item => item.productId);
    const placeholders = productIds.map((_, i) => `$${i + 1}`).join(',');

    const result = await pool.query(
      `SELECT id, quantity FROM products WHERE id IN (${placeholders})`,
      productIds
    );

    const productMap = {};
    result.rows.forEach(row => {
      productMap[row.id] = row.quantity;
    });

    const availability = items.map(item => ({
      productId: item.productId,
      available: (productMap[item.productId] || 0) >= item.quantity,
      currentQuantity: productMap[item.productId] || 0,
    }));

    const allAvailable = availability.every(item => item.available);

    inventoryCheckTime.observe((Date.now() - start) / 1000);

    res.json({
      available: allAvailable,
      items: availability,
    });
  } catch (error) {
    req.log.error(error);
    res.status(500).json({ error: error.message });
  }
});

// Atualizar quantidade
app.patch('/inventory/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { quantity } = req.body;

    if (quantity === undefined) {
      return res.status(400).json({ error: 'Quantity is required' });
    }

    if (!pool) {
      return res.status(503).json({ error: 'Database unavailable' });
    }

    const result = await pool.query(
      'UPDATE products SET quantity = $1, updated_at = NOW() WHERE id = $2 RETURNING *',
      [quantity, id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }

    // Invalidar cache
    if (redisClient) {
      await redisClient.del(`product:${id}`);
    }

    stockLevel.set({ product_id: id }, quantity);

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