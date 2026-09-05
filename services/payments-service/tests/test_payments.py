import pytest
import sys
import os
from unittest.mock import Mock, patch, MagicMock

# Adicionar o diretório pai ao path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import app, set_dependencies

@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

@pytest.fixture
def mock_db():
    return Mock()

@pytest.fixture
def mock_redis():
    return Mock()

@pytest.fixture
def mock_channel():
    return Mock()

def test_simple():
    """Test simples para verificar se pytest está funcionando"""
    assert 1 + 1 == 2

def test_health_endpoint(client):
    """Test do endpoint de health"""
    response = client.get('/health')

    assert response.status_code == 200
    assert response.json['status'] == 'ok'
    assert response.json['service'] == 'payments-service'

def test_get_payments(client, mock_db, mock_redis, mock_channel):
    """Test para listar pagamentos"""
    set_dependencies(mock_db, mock_redis=mock_redis, channel_param=mock_channel)

    mock_db.execute.return_value.fetchall.return_value = []

    response = client.get('/payments')
    assert response.status_code == 200
    assert isinstance(response.json, list)

def test_create_payment_success(client, mock_db, mock_redis, mock_channel):
    """Test para criar pagamento com sucesso"""
    set_dependencies(mock_db, mock_redis=mock_redis, channel_param=mock_channel)

    payment_data = {
        'order_id': 'order-123',
        'amount': 199.98,
        'payment_method': 'credit_card'
    }

    mock_payment = {
        'id': 'payment-123',
        'order_id': 'order-123',
        'amount': 199.98,
        'payment_method': 'credit_card',
        'status': 'pending',
        'created_at': '2026-08-21T01:46:40Z'
    }

    mock_db.execute.return_value.fetchone.return_value = mock_payment

    response = client.post('/payments', 
        json=payment_data,
        content_type='application/json'
    )

    assert response.status_code == 201
    assert response.json['order_id'] == 'order-123'
    assert response.json['status'] == 'pending'

def test_create_payment_missing_fields(client):
    """Test para criar pagamento sem campos obrigatórios"""
    payment_data = {
        'order_id': 'order-123'
    }

    response = client.post('/payments',
        json=payment_data,
        content_type='application/json'
    )

    assert response.status_code == 400
    assert 'error' in response.json

def test_get_payment_by_id(client, mock_db, mock_redis, mock_channel):
    """Test para obter pagamento específico"""
    set_dependencies(mock_db, mock_redis=mock_redis, channel_param=mock_channel)

    mock_payment = {
        'id': 'payment-123',
        'order_id': 'order-123',
        'amount': 199.98,
        'status': 'pending'
    }

    mock_db.execute.return_value.fetchone.return_value = mock_payment

    response = client.get('/payments/payment-123')
    assert response.status_code == 200
    assert response.json['id'] == 'payment-123'

def test_get_payment_not_found(client, mock_db, mock_redis, mock_channel):
    """Test para obter pagamento que não existe"""
    set_dependencies(mock_db, mock_redis=mock_redis, channel_param=mock_channel)

    mock_db.execute.return_value.fetchone.return_value = None

    response = client.get('/payments/nonexistent')
    assert response.status_code == 404
    assert 'error' in response.json

def test_process_payment_success(client, mock_db, mock_redis, mock_channel):
    """Test para processar pagamento com sucesso"""
    set_dependencies(mock_db, mock_redis=mock_redis, channel_param=mock_channel)

    process_data = {
        'status': 'completed'
    }

    mock_payment = {
        'id': 'payment-123',
        'order_id': 'order-123',
        'amount': 199.98,
        'status': 'completed'
    }

    mock_db.execute.return_value.fetchone.return_value = mock_payment

    response = client.patch('/payments/payment-123',
        json=process_data,
        content_type='application/json'
    )

    assert response.status_code == 200
    assert response.json['status'] == 'completed'

def test_process_payment_missing_status(client):
    """Test para processar pagamento sem status"""
    process_data = {}

    response = client.patch('/payments/payment-123',
        json=process_data,
        content_type='application/json'
    )

    assert response.status_code == 400

def test_ready_check(client, mock_db, mock_redis, mock_channel):
    """Test do endpoint ready"""
    set_dependencies(mock_db, mock_redis=mock_redis, channel_param=mock_channel)

    mock_db.execute.return_value.fetchone.return_value = (1,)

    response = client.get('/ready')
    assert response.status_code == 200
    assert response.json['ready'] == True

def test_ready_reconnects_when_database_is_not_initialized(client):
    """Ready deve tentar conectar quando o banco ainda não foi inicializado."""
    import app as payments_app

    mock_connection = Mock()
    mock_cursor = Mock()
    mock_cursor.fetchone.return_value = (1,)
    mock_connection.cursor.return_value = mock_cursor

    with patch(
        "app.psycopg2.connect",
        return_value=mock_connection,
    ) as mock_connect:
        payments_app.db = None

        response = client.get("/ready")

        assert response.status_code == 200
        assert response.json["ready"] is True
        mock_connect.assert_called_once()
        assert payments_app.db is not None


def test_ready_returns_503_when_database_reconnect_fails(client):
    """Ready deve permanecer 503 quando o PostgreSQL continua indisponível."""
    import app as payments_app

    payments_app.db = None

    with patch(
        "app.psycopg2.connect",
        side_effect=Exception("connection refused"),
    ) as mock_connect:
        response = client.get("/ready")

        assert response.status_code == 503
        assert response.json["ready"] is False
        assert response.json["error"] == "Database unavailable"
        mock_connect.assert_called_once()
        assert payments_app.db is None


def test_ready_reconnects_after_existing_database_connection_fails(client):
    """Ready deve reconectar quando uma conexão existente deixa de funcionar."""
    import app as payments_app

    broken_db = Mock()
    broken_db.execute.side_effect = Exception("connection lost")

    new_connection = Mock()
    new_cursor = Mock()
    new_cursor.fetchone.return_value = (1,)
    new_connection.cursor.return_value = new_cursor

    with patch(
        "app.psycopg2.connect",
        return_value=new_connection,
    ) as mock_connect:
        payments_app.db = broken_db

        response = client.get("/ready")

        assert response.status_code == 200
        assert response.json["ready"] is True
        mock_connect.assert_called_once()
        assert payments_app.db is not None
        assert payments_app.db.connection is new_connection
