const request = require('supertest');
const axios = require('axios');

jest.mock('axios');

const app = require('../src/index');

describe('API Gateway - Health and Readiness', () => {
  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('GET /health', () => {
    test('returns 200 when gateway is alive', async () => {
      const response = await request(app).get('/health');

      expect(response.status).toBe(200);
      expect(response.body.status).toBe('ok');
      expect(response.body.timestamp).toBeDefined();
    });
  });

  describe('GET /ready', () => {
    test('returns 200 when Orders and Inventory are ready', async () => {
      axios.get
        .mockResolvedValueOnce({ status: 200, data: { ready: true } })
        .mockResolvedValueOnce({ status: 200, data: { ready: true } });

      const response = await request(app).get('/ready');

      expect(response.status).toBe(200);
      expect(response.body).toEqual({ ready: true });

      expect(axios.get).toHaveBeenCalledTimes(2);
      expect(axios.get).toHaveBeenNthCalledWith(
        1,
        'http://orders-service:3001/ready',
        expect.objectContaining({ timeout: 2000 })
      );
      expect(axios.get).toHaveBeenNthCalledWith(
        2,
        'http://inventory-service:3003/ready',
        expect.objectContaining({ timeout: 2000 })
      );
    });

    test('returns 503 when Orders is unavailable', async () => {
      axios.get
        .mockRejectedValueOnce(new Error('Orders unavailable'))
        .mockResolvedValueOnce({ status: 200, data: { ready: true } });

      const response = await request(app).get('/ready');

      expect(response.status).toBe(503);
      expect(response.body.ready).toBe(false);
    });

    test('returns 503 when Inventory is unavailable', async () => {
      axios.get
        .mockResolvedValueOnce({ status: 200, data: { ready: true } })
        .mockRejectedValueOnce(new Error('Inventory unavailable'));

      const response = await request(app).get('/ready');

      expect(response.status).toBe(503);
      expect(response.body.ready).toBe(false);
    });

    test('returns 503 when a dependency responds with non-200 status', async () => {
      axios.get
        .mockResolvedValueOnce({ status: 200, data: { ready: true } })
        .mockResolvedValueOnce({ status: 503, data: { ready: false } });

      const response = await request(app).get('/ready');

      expect(response.status).toBe(503);
      expect(response.body.ready).toBe(false);
    });
  });
});
