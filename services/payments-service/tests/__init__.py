import pytest
import json
from unittest.mock import Mock, patch, MagicMock
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

def test_health_check(client):
    response = client.get('/health')
    assert response.status_code == 200
    assert response.json['status'] == 'ok'

def test_get_payments(client, mock_db):
    set_dependencies(mock_db, mock_redis=Mock(), channel=Mock())

    mock_db.execute.return_value.fetchall.return_value = []

    response = client.get('/payments')
    assert response.status_code == 200
    assert isinstance(response.json, list)

def test_create_payment_success(client, mock_db):
    mock_redis = Mock()
    mock_channel = Mock()
    set_dependencies(mock_db, mock_redis=mock_redis, channel=mock_channel)

    payment_data = {
        'order_id': 'order-123',
        'amount': 199.98,
        'payment_method': 'credit_card'
    }

    mock_payment = {
        'id': 'payment-123',
        **payment_data,
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
    payment_data = {
        'order_id': 'order-123'
    }

    response = client.post('/payments',
        json=payment_data,
        content_type='application/json'
    )

    assert response.status_code == 400

def test_get_payment_by_id(client, mock_db):
    set_dependencies(mock_db, mock_redis=Mock(), channel=Mock())

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

def test_process_payment_success(client, mock_db):
    mock_redis = Mock()
    mock_channel = Mock()
    set_dependencies(mock_db, mock_redis=mock_redis, channel=mock_channel)

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

def test_ready_check(client, mock_db):
    set_dependencies(mock_db, mock_redis=Mock(), channel=Mock())

    mock_db.execute.return_value.fetchone.return_value = (1,)

    response = client.get('/ready')
    assert response.status_code == 200
    assert response.json['ready'] == True