import os
import json
import logging
from datetime import datetime
from uuid import uuid4
from functools import wraps

from flask import Flask, request, jsonify
from flask_cors import CORS
from dotenv import load_dotenv
import psycopg2
from psycopg2.extras import RealDictCursor
import redis
import pika
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST

load_dotenv()

app = Flask(__name__)
CORS(app)

# Configuração
PORT = int(os.getenv('PAYMENTS_SERVICE_PORT', 3002))
LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')

# Logging
logging.basicConfig(level=LOG_LEVEL)
logger = logging.getLogger(__name__)

# Database connection
def get_db_connection():
    try:
        conn = psycopg2.connect(
            host=os.getenv('POSTGRES_HOST', 'postgres'),
            database=os.getenv('POSTGRES_DB'),
            user=os.getenv('POSTGRES_USER'),
            password=os.getenv('POSTGRES_PASSWORD'),
            port=int(os.getenv('POSTGRES_PORT', 5432))
        )
        return conn
    except Exception as e:
        logger.error(f"Database connection error: {e}")
        return None

# Redis connection
try:
    redis_client = redis.Redis(
        host=os.getenv('REDIS_HOST', 'redis'),
        port=int(os.getenv('REDIS_PORT', 6379)),
        password=os.getenv('REDIS_PASSWORD'),
        decode_responses=True
    )
    redis_client.ping()
    logger.info("Redis connected")
except Exception as e:
    logger.error(f"Redis connection error: {e}")
    redis_client = None

# RabbitMQ connection
def get_rabbitmq_channel():
    try:
        credentials = pika.PlainCredentials(
            os.getenv('RABBITMQ_DEFAULT_USER', 'guest'),
            os.getenv('RABBITMQ_DEFAULT_PASS', 'guest')
        )
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(
                host=os.getenv('RABBITMQ_HOST', 'rabbitmq'),
                credentials=credentials
            )
        )
        channel = connection.channel()
        channel.exchange_declare(exchange='payments', exchange_type='topic', durable=True)
        return channel
    except Exception as e:
        logger.error(f"RabbitMQ connection error: {e}")
        return None

# Métricas Prometheus
payments_total = Counter(
    'payments_total',
    'Total number of payments',
    ['status']
)

payments_amount = Counter(
    'payments_amount_total',
    'Total amount of payments',
    ['status']
)

payment_processing_time = Histogram(
    'payment_processing_time_seconds',
    'Payment processing time in seconds'
)

active_payments = Gauge(
    'active_payments',
    'Number of active payments'
)

# Health check
@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'ok', 'service': 'payments-service'}), 200

# Readiness check
@app.route('/ready', methods=['GET'])
def ready():
    try:
        conn = get_db_connection()
        if conn:
            conn.close()
            return jsonify({'ready': True}), 200
        return jsonify({'ready': False, 'error': 'Database unavailable'}), 503
    except Exception as e:
        return jsonify({'ready': False, 'error': str(e)}), 503

# Métricas
@app.route('/metrics', methods=['GET'])
def metrics():
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

# Criar pagamento
@app.route('/payments', methods=['POST'])
@payment_processing_time.time()
def create_payment():
    data = request.get_json()
    order_id = data.get('order_id')
    amount = data.get('amount')
    payment_method = data.get('payment_method', 'credit_card')

    if not order_id or not amount:
        return jsonify({'error': 'Missing required fields'}), 400

    try:
        payment_id = str(uuid4())
        conn = get_db_connection()

        if not conn:
            return jsonify({'error': 'Database unavailable'}), 503

        cur = conn.cursor(cursor_factory=RealDictCursor)

        # Inserir pagamento
        cur.execute('''
            INSERT INTO payments (id, order_id, amount, payment_method, status, created_at)
            VALUES (%s, %s, %s, %s, %s, NOW())
            RETURNING *
        ''', (payment_id, order_id, amount, payment_method, 'pending'))

        payment = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()

        # Publicar evento no RabbitMQ
        try:
            channel = get_rabbitmq_channel()
            if channel:
                channel.basic_publish(
                    exchange='payments',
                    routing_key='payment.created',
                    body=json.dumps({
                        'payment_id': payment_id,
                        'order_id': order_id,
                        'amount': float(amount),
                        'timestamp': datetime.now().isoformat()
                    })
                )
        except Exception as e:
            logger.error(f"RabbitMQ publish error: {e}")

        # Cache no Redis
        if redis_client:
            redis_client.setex(
                f'payment:{payment_id}',
                3600,
                json.dumps(payment, default=str)
            )

        payments_total.labels(status='created').inc()
        payments_amount.labels(status='created').inc(float(amount))
        active_payments.inc()

        return jsonify(payment), 201

    except Exception as e:
        logger.error(f"Error creating payment: {e}")
        payments_total.labels(status='error').inc()
        return jsonify({'error': str(e)}), 500

# Listar pagamentos
@app.route('/payments', methods=['GET'])
def list_payments():
    try:
        conn = get_db_connection()
        if not conn:
            return jsonify({'error': 'Database unavailable'}), 503

        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute('SELECT * FROM payments ORDER BY created_at DESC LIMIT 100')
        payments = cur.fetchall()
        cur.close()
        conn.close()

        return jsonify(payments), 200

    except Exception as e:
        logger.error(f"Error listing payments: {e}")
        return jsonify({'error': str(e)}), 500

# Obter pagamento específico
@app.route('/payments/<payment_id>', methods=['GET'])
def get_payment(payment_id):
    try:
        # Tentar cache primeiro
        if redis_client:
            cached = redis_client.get(f'payment:{payment_id}')
            if cached:
                return jsonify(json.loads(cached)), 200

        conn = get_db_connection()
        if not conn:
            return jsonify({'error': 'Database unavailable'}), 503

        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute('SELECT * FROM payments WHERE id = %s', (payment_id,))
        payment = cur.fetchone()
        cur.close()
        conn.close()

        if not payment:
            return jsonify({'error': 'Payment not found'}), 404

        # Cache o resultado
        if redis_client:
            redis_client.setex(
                f'payment:{payment_id}',
                3600,
                json.dumps(payment, default=str)
            )

        return jsonify(payment), 200

    except Exception as e:
        logger.error(f"Error getting payment: {e}")
        return jsonify({'error': str(e)}), 500

# Processar pagamento
@app.route('/payments/<payment_id>/process', methods=['POST'])
@payment_processing_time.time()
def process_payment(payment_id):
    try:
        conn = get_db_connection()
        if not conn:
            return jsonify({'error': 'Database unavailable'}), 503

        cur = conn.cursor(cursor_factory=RealDictCursor)

        # Atualizar status
        cur.execute('''
            UPDATE payments SET status = %s, updated_at = NOW() WHERE id = %s RETURNING *
        ''', ('processed', payment_id))

        payment = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()

        if not payment:
            return jsonify({'error': 'Payment not found'}), 404

        # Invalidar cache
        if redis_client:
            redis_client.delete(f'payment:{payment_id}')

        # Publicar evento
        try:
            channel = get_rabbitmq_channel()
            if channel:
                channel.basic_publish(
                    exchange='payments',
                    routing_key='payment.processed',
                    body=json.dumps({
                        'payment_id': payment_id,
                        'status': 'processed',
                        'timestamp': datetime.now().isoformat()
                    })
                )
        except Exception as e:
            logger.error(f"RabbitMQ publish error: {e}")

        payments_total.labels(status='processed').inc()
        active_payments.dec()

        return jsonify(payment), 200

    except Exception as e:
        logger.error(f"Error processing payment: {e}")
        payments_total.labels(status='error').inc()
        return jsonify({'error': str(e)}), 500

# Inicializar banco de dados
def init_db():
    try:
        conn = get_db_connection()
        if not conn:
            logger.error("Could not connect to database")
            return

        cur = conn.cursor()
        cur.execute('''
            CREATE TABLE IF NOT EXISTS payments (
                id UUID PRIMARY KEY,
                order_id UUID NOT NULL,
                amount DECIMAL(10, 2) NOT NULL,
                payment_method VARCHAR(50) NOT NULL,
                status VARCHAR(50) DEFAULT 'pending',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );

            CREATE INDEX IF NOT EXISTS idx_order_id ON payments(order_id);
            CREATE INDEX IF NOT EXISTS idx_status ON payments(status);
            CREATE INDEX IF NOT EXISTS idx_created_at ON payments(created_at);
        ''')
        conn.commit()
        cur.close()
        conn.close()
        logger.info("Database initialized")
    except Exception as e:
        logger.error(f"Database initialization error: {e}")

# Error handling
@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Not Found'}), 404

@app.errorhandler(500)
def internal_error(error):
    logger.error(f"Internal error: {error}")
    return jsonify({'error': 'Internal Server Error'}), 500

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=PORT, debug=False)