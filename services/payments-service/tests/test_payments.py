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