require('dotenv').config();
const { Pool } = require('pg');
const redis = require('redis');
const amqp = require('amqplib');
const { app, setDependencies } = require('./app');

const PORT = process.env.ORDERS_SERVICE_PORT || 3001;

// Database connection
const pool = new Pool({
  user: process.env.POSTGRES_USER,
  password: process.env.POSTGRES_PASSWORD,
  host: process.env.POSTGRES_HOST || 'pedidos-postgres',
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
redisClient.connect().catch(err => console.error('Redis connection failed:', err));

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

// Injetar dependências
setDependencies({ pool, redisClient, channel });

// Start server
const start = async () => {
  await initDB();
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Orders Service rodando na porta ${PORT}`);
  });
};

start();

module.exports = app;