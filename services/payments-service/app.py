from flask import Flask, request, jsonify
import os
import logging
from datetime import datetime
from uuid import uuid4
import json

app = Flask(__name__)

# Logging
logging.basicConfig(level=os.getenv('LOG_LEVEL', 'INFO'))
logger = logging.getLogger(__name__)

# Dependências
db = None
redis_client = None
channel = None

def set_dependencies(database, mock_redis=None, channel_param=None):
    global db, redis_client, channel
    db = database
    redis_client = mock_redis
    channel = channel_param

# Health check
@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'ok', 'service': 'payments-service'}), 200

# Readiness check
@app.route('/ready', methods=['GET'])
def ready():
    try:
        if not db:
            return jsonify({'ready': False, 'error': 'Database not initialized'}), 503

        db.execute('SELECT 1')
        return jsonify({'ready': True}), 200
    except Exception as e:
        return jsonify({'ready': False, 'error': str(e)}), 503

# Listar pagamentos
@app.route('/payments', methods=['GET'])
def get_payments():
    try:
        if not db:
            return jsonify({'error': 'Database unavailable'}), 503

        result = db.execute('SELECT * FROM payments ORDER BY created_at DESC LIMIT 100')
        payments = result.fetchall()
        return jsonify(payments or []), 200
    except Exception as e:
        logger.error(f'Error fetching payments: {str(e)}')
        return jsonify({'error': str(e)}), 500

# Criar pagamento
@app.route('/payments', methods=['POST'])
def create_payment():
    data = request.get_json()

    if not data or not all(k in data for k in ['order_id', 'amount', 'payment_method']):
        return jsonify({'error': 'Missing required fields'}), 400

    try:
        if not db:
            return jsonify({'error': 'Database unavailable'}), 503

        payment_id = str(uuid4())
        order_id = data['order_id']
        amount = data['amount']
        payment_method = data['payment_method']

        query = '''
            INSERT INTO payments (id, order_id, amount, payment_method, status, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            RETURNING *
        '''

        result = db.execute(query, (
            payment_id, order_id, amount, payment_method, 'pending', datetime.utcnow()
        ))
        payment = result.fetchone()

        # Publicar evento no RabbitMQ
        if channel:
            channel.basic_publish(
                exchange='payments',
                routing_key='payment.created',
                body=json.dumps({
                    'paymentId': payment_id,
                    'orderId': order_id,
                    'amount': amount,
                    'timestamp': datetime.utcnow().isoformat()
                })
            )

        # Cache no Redis
        if redis_client:
            redis_client.setex(f'payment:{payment_id}', 3600, json.dumps(payment))

        return jsonify(payment), 201
    except Exception as e:
        logger.error(f'Error creating payment: {str(e)}')
        return jsonify({'error': str(e)}), 500

# Obter pagamento específico
@app.route('/payments/<payment_id>', methods=['GET'])
def get_payment(payment_id):
    try:
        if not db:
            return jsonify({'error': 'Database unavailable'}), 503

        # Tentar cache primeiro
        if redis_client:
            try:
                cached = redis_client.get(f'payment:{payment_id}')
                if cached and isinstance(cached, (str, bytes)):
                    return jsonify(json.loads(cached)), 200
            except (TypeError, json.JSONDecodeError):
                pass

        result = db.execute('SELECT * FROM payments WHERE id = ?', (payment_id,))
        payment = result.fetchone()

        if not payment:
            return jsonify({'error': 'Payment not found'}), 404

        # Cache o resultado
        if redis_client:
            try:
                redis_client.setex(f'payment:{payment_id}', 3600, json.dumps(payment))
            except (TypeError, AttributeError):
                pass

        return jsonify(payment), 200
    except Exception as e:
        logger.error(f'Error fetching payment: {str(e)}')
        return jsonify({'error': str(e)}), 500

# Processar pagamento
@app.route('/payments/<payment_id>', methods=['PATCH'])
def process_payment(payment_id):
    data = request.get_json()

    if not data or 'status' not in data:
        return jsonify({'error': 'Status is required'}), 400

    try:
        if not db:
            return jsonify({'error': 'Database unavailable'}), 503

        status = data['status']

        query = 'UPDATE payments SET status = ?, updated_at = ? WHERE id = ? RETURNING *'
        result = db.execute(query, (status, datetime.utcnow(), payment_id))
        payment = result.fetchone()

        if not payment:
            return jsonify({'error': 'Payment not found'}), 404

        # Invalidar cache
        if redis_client:
            try:
                redis_client.delete(f'payment:{payment_id}')
            except (TypeError, AttributeError):
                pass

        # Publicar evento
        if channel:
            try:
                channel.basic_publish(
                    exchange='payments',
                    routing_key='payment.updated',
                    body=json.dumps({
                        'paymentId': payment_id,
                        'status': status,
                        'timestamp': datetime.utcnow().isoformat()
                    })
                )
            except (TypeError, AttributeError):
                pass

        return jsonify(payment), 200
    except Exception as e:
        logger.error(f'Error processing payment: {str(e)}')
        return jsonify({'error': str(e)}), 500

# Error handling
@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Not Found'}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({'error': 'Internal Server Error'}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.getenv('PAYMENTS_SERVICE_PORT', 3002)))