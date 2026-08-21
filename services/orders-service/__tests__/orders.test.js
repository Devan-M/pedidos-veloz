const request = require('supertest');
const { app, setDependencies } = require('../src/app');

// Mock das dependências
const mockPool = {
  query: jest.fn(),
};

const mockRedisClient = {
  get: jest.fn(),
  setEx: jest.fn(),
  del: jest.fn(),
};

const mockChannel = {
  publish: jest.fn(),
};

beforeAll(() => {
  setDependencies({
    pool: mockPool,
    redisClient: mockRedisClient,
    channel: mockChannel,
  });
});

beforeEach(() => {
  jest.clearAllMocks();
});

describe('Orders Service', () => {
  describe('GET /orders', () => {
    it('should return an empty array initially', async () => {
      mockPool.query.mockResolvedValueOnce({ rows: [] });

      const res = await request(app).get('/orders');
      expect(res.status).toBe(200);
      expect(Array.isArray(res.body)).toBe(true);
    });
  });

  describe('POST /orders', () => {
    it('should create a new order', async () => {
      const orderData = {
        customer_id: 'cust-test-123',
        items: [
          {
            product_id: 'prod-123',
            quantity: 2,
            price: 99.99,
          },
        ],
        total_amount: 199.98,
      };

      const mockOrder = {
        id: 'order-123',
        ...orderData,
        status: 'pending',
        created_at: new Date(),
      };

      mockPool.query.mockResolvedValueOnce({ rows: [mockOrder] });

      const res = await request(app)
        .post('/orders')
        .send(orderData);

      expect(res.status).toBe(201);
      expect(res.body).toHaveProperty('id');
      expect(res.body.customer_id).toBe('cust-test-123');
      expect(res.body.status).toBe('pending');
    });

    it('should return 400 for missing fields', async () => {
      const res = await request(app)
        .post('/orders')
        .send({ customer_id: 'cust-123' });

      expect(res.status).toBe(400);
    });
  });

  describe('GET /health', () => {
    it('should return health status', async () => {
      const res = await request(app).get('/health');
      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('status');
    });
  });
});