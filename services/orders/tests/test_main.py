from fastapi.testclient import TestClient

from app.main import app


def test_health():
    with TestClient(app) as client:
        response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_create_order():
    with TestClient(app) as client:
        response = client.post(
            "/orders",
            json={
                "customer_id": "customer-1",
                "product_id": "product-1",
                "quantity": 2,
                "amount": 49.90,
            },
        )

    assert response.status_code == 201
    assert response.json()["status"] == "CREATED"
