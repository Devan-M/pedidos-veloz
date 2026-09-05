from flask import Flask, request, jsonify
import os
import logging
from datetime import datetime, UTC
from uuid import uuid4
import json

import psycopg2
import redis
import pika
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)

# Logging
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger(__name__)

# Dependências
db = None
redis_client = None
channel = None


class Database:
    """Pequeno wrapper para manter a interface usada pela aplicação e pelos testes."""

    def __init__(self, connection):
        self.connection = connection

    def execute(self, query, params=None):
        # O código original usa placeholders "?".
        # PostgreSQL/psycopg2 usa "%s".
        query = query.replace("?", "%s")

        cursor = self.connection.cursor()
        cursor.execute(query, params or ())
        self.connection.commit()
        return cursor


def set_dependencies(database, mock_redis=None, channel_param=None):
    global db, redis_client, channel
    db = database
    redis_client = mock_redis
    channel = channel_param


def connect_postgres():
    """Tenta conectar ou reconectar ao PostgreSQL."""
    global db

    postgres_host = os.getenv("POSTGRES_HOST", "postgres-service")
    postgres_port = int(os.getenv("POSTGRES_PORT", "5432"))
    postgres_db = os.getenv("POSTGRES_DB", "pedidos_veloz")
    postgres_user = os.getenv("POSTGRES_USER", "postgres")
    postgres_password = os.getenv("POSTGRES_PASSWORD", "")

    try:
        connection = psycopg2.connect(
            host=postgres_host,
            port=postgres_port,
            dbname=postgres_db,
            user=postgres_user,
            password=postgres_password,
            connect_timeout=5,
        )

        connection.autocommit = False
        db = Database(connection)

        logger.info(
            "PostgreSQL connected successfully: %s:%s/%s",
            postgres_host,
            postgres_port,
            postgres_db,
        )

        return True

    except Exception as e:
        db = None
        logger.warning("PostgreSQL connection attempt failed: %s", e)
        return False


def initialize_dependencies():
    global db, redis_client, channel

    # PostgreSQL
    connect_postgres()

    # Redis
    try:
        redis_host = os.getenv("REDIS_HOST", "redis-service")
        redis_port = int(os.getenv("REDIS_PORT", "6379"))
        redis_password = os.getenv("REDIS_PASSWORD") or None

        redis_client = redis.Redis(
            host=redis_host,
            port=redis_port,
            password=redis_password,
            decode_responses=True,
            socket_connect_timeout=5,
            socket_timeout=5,
        )

        redis_client.ping()

        logger.info(
            "Redis connected successfully: %s:%s",
            redis_host,
            redis_port,
        )

    except Exception as e:
        redis_client = None
        logger.error("Redis initialization error: %s", e)

    # RabbitMQ
    try:
        rabbitmq_host = os.getenv("RABBITMQ_HOST", "rabbitmq-service")
        rabbitmq_user = os.getenv("RABBITMQ_USER", "guest")
        rabbitmq_password = os.getenv("RABBITMQ_PASSWORD", "guest")

        credentials = pika.PlainCredentials(
            rabbitmq_user,
            rabbitmq_password,
        )

        parameters = pika.ConnectionParameters(
            host=rabbitmq_host,
            port=5672,
            credentials=credentials,
            connection_attempts=3,
            retry_delay=2,
        )

        rabbit_connection = pika.BlockingConnection(parameters)
        channel = rabbit_connection.channel()

        channel.exchange_declare(
            exchange="payments",
            exchange_type="direct",
            durable=True,
        )

        logger.info(
            "RabbitMQ connected successfully: %s",
            rabbitmq_host,
        )

    except Exception as e:
        channel = None
        logger.error("RabbitMQ initialization error: %s", e)


# Prometheus metrics
@app.route("/metrics", methods=["GET"])
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


# Health check
@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "status": "ok",
        "service": "payments-service"
    }), 200


# Readiness check
@app.route("/ready", methods=["GET"])
def ready():
    global db

    try:
        # Se a conexão ainda não foi estabelecida durante o startup,
        # tenta recuperá-la sem derrubar o processo.
        if db is None:
            if not connect_postgres():
                return jsonify({
                    "ready": False,
                    "error": "Database unavailable"
                }), 503

        try:
            result = db.execute("SELECT 1")
            result.fetchone()

        except Exception as e:
            # A conexão existente pode ter sido perdida depois do startup.
            logger.warning(
                "PostgreSQL readiness check failed, attempting reconnect: %s",
                e,
            )

            db = None

            if not connect_postgres():
                return jsonify({
                    "ready": False,
                    "error": "Database unavailable"
                }), 503

            result = db.execute("SELECT 1")
            result.fetchone()

        return jsonify({"ready": True}), 200

    except Exception as e:
        db = None
        logger.error("Readiness check failed: %s", e)
        return jsonify({
            "ready": False,
            "error": "Database unavailable"
        }), 503


# Listar pagamentos
@app.route("/payments", methods=["GET"])
def get_payments():
    try:
        if db is None:
            return jsonify({"error": "Database unavailable"}), 503

        result = db.execute(
            "SELECT * FROM payments ORDER BY created_at DESC LIMIT 100"
        )

        payments = result.fetchall()

        return jsonify(payments or []), 200

    except Exception as e:
        logger.error("Error fetching payments: %s", e)
        return jsonify({"error": str(e)}), 500


# Criar pagamento
@app.route("/payments", methods=["POST"])
def create_payment():
    data = request.get_json()

    if not data or not all(
        k in data for k in ["order_id", "amount", "payment_method"]
    ):
        return jsonify({"error": "Missing required fields"}), 400

    try:
        if db is None:
            return jsonify({"error": "Database unavailable"}), 503

        payment_id = str(uuid4())
        order_id = data["order_id"]
        amount = data["amount"]
        payment_method = data["payment_method"]

        query = """
            INSERT INTO payments
                (id, order_id, amount, payment_method, status, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            RETURNING *
        """

        result = db.execute(
            query,
            (
                payment_id,
                order_id,
                amount,
                payment_method,
                "pending",
                datetime.now(UTC),
            ),
        )

        payment = result.fetchone()

        if channel:
            try:
                channel.basic_publish(
                    exchange="payments",
                    routing_key="payment.created",
                    body=json.dumps({
                        "paymentId": payment_id,
                        "orderId": order_id,
                        "amount": amount,
                        "timestamp": datetime.now(UTC).isoformat(),
                    }),
                )
            except Exception as e:
                logger.error("RabbitMQ publish error: %s", e)

        if redis_client:
            try:
                redis_client.setex(
                    f"payment:{payment_id}",
                    3600,
                    json.dumps(payment, default=str),
                )
            except Exception as e:
                logger.error("Redis cache error: %s", e)

        return jsonify(payment), 201

    except Exception as e:
        logger.error("Error creating payment: %s", e)

        if db and hasattr(db, "connection"):
            try:
                db.connection.rollback()
            except Exception:
                pass

        return jsonify({"error": str(e)}), 500


# Obter pagamento específico
@app.route("/payments/<payment_id>", methods=["GET"])
def get_payment(payment_id):
    try:
        if db is None:
            return jsonify({"error": "Database unavailable"}), 503

        if redis_client:
            try:
                cached = redis_client.get(f"payment:{payment_id}")

                if cached:
                    return jsonify(json.loads(cached)), 200

            except Exception as e:
                logger.warning("Redis read error: %s", e)

        result = db.execute(
            "SELECT * FROM payments WHERE id = ?",
            (payment_id,),
        )

        payment = result.fetchone()

        if not payment:
            return jsonify({"error": "Payment not found"}), 404

        if redis_client:
            try:
                redis_client.setex(
                    f"payment:{payment_id}",
                    3600,
                    json.dumps(payment, default=str),
                )
            except Exception as e:
                logger.warning("Redis cache error: %s", e)

        return jsonify(payment), 200

    except Exception as e:
        logger.error("Error fetching payment: %s", e)
        return jsonify({"error": str(e)}), 500


# Processar pagamento
@app.route("/payments/<payment_id>", methods=["PATCH"])
def process_payment(payment_id):
    data = request.get_json()

    if not data or "status" not in data:
        return jsonify({"error": "Status is required"}), 400

    try:
        if db is None:
            return jsonify({"error": "Database unavailable"}), 503

        status = data["status"]

        query = """
            UPDATE payments
            SET status = ?, updated_at = ?
            WHERE id = ?
            RETURNING *
        """

        result = db.execute(
            query,
            (
                status,
                datetime.now(UTC),
                payment_id,
            ),
        )

        payment = result.fetchone()

        if not payment:
            return jsonify({"error": "Payment not found"}), 404

        if redis_client:
            try:
                redis_client.delete(f"payment:{payment_id}")
            except Exception as e:
                logger.warning("Redis delete error: %s", e)

        if channel:
            try:
                channel.basic_publish(
                    exchange="payments",
                    routing_key="payment.updated",
                    body=json.dumps({
                        "paymentId": payment_id,
                        "status": status,
                        "timestamp": datetime.now(UTC).isoformat(),
                    }),
                )
            except Exception as e:
                logger.error("RabbitMQ publish error: %s", e)

        return jsonify(payment), 200

    except Exception as e:
        logger.error("Error processing payment: %s", e)

        if db and hasattr(db, "connection"):
            try:
                db.connection.rollback()
            except Exception:
                pass

        return jsonify({"error": str(e)}), 500


# Error handling
@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": "Not Found"}), 404


@app.errorhandler(500)
def internal_error(error):
    return jsonify({"error": "Internal Server Error"}), 500


# Inicializar dependências antes de iniciar o servidor
initialize_dependencies()


if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=int(os.getenv("PAYMENTS_SERVICE_PORT", 3002)),
    )
