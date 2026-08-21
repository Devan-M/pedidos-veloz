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

beforeAll(() => {
  setDependencies({
    pool: mockPool,
    redisClient: mockRedisClient,
  });
});

beforeEach(() => {
  jest.clearAllMocks();
});

describe('Inventory Service', () => {
  describe('GET /inventory', () => {
    it('should return all products', async () => {
      const mockProducts = [
        {
          id: 'prod-1',
          name: 'Notebook',
          sku: 'NB-001',
          quantity: 50,
          price: '4999.99',
        },
      ];

      mockPool.query.mockResolvedValueOnce({ rows: mockProducts });

      const res = await request(app).get('/inventory');
      expect(res.status).toBe(200);
      expect(Array.isArray(res.body)).toBe(true);
    });
  });

  describe('POST /inventory', () => {
    it('should create a new product', async () => {
      const productData = {
        name: 'Notebook Dell',
        sku: 'DELL-XPS-13',
        quantity: 50,
        price: 4999.99,
      };

      const mockProduct = {
        id: 'prod-123',
        ...productData,
        created_at: new Date(),
      };

      mockPool.query.mockResolvedValueOnce({ rows: [mockProduct] });

      const res = await request(app)
        .post('/inventory')
        .send(productData);

      expect(res.status).toBe(201);
      expect(res.body).toHaveProperty('id');
      expect(res.body.name).toBe('Notebook Dell');
    });

    it('should return 400 for missing fields', async () => {
      const res = await request(app)
        .post('/inventory')
        .send({ name: 'Notebook' });

      expect(res.status).toBe(400);
    });
  });

  describe('POST /inventory/check-availability', () => {
    it('should check product availability', async () => {
      const checkData = {
        items: [
          {
            productId: 'prod-1',
            quantity: 2,
          },
        ],
      };

      mockPool.query.mockResolvedValueOnce({
        rows: [{ id: 'prod-1', quantity: 50 }],
      });

      const res = await request(app)
        .post('/inventory/check-availability')
        .send(checkData);

      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('available');
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