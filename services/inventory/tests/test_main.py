from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_reserve_stock():
    response = client.post(
        "/inventory/reserve",
        json={
            "product_id": "product-1",
            "quantity": 2,
        },
    )

    assert response.status_code == 200
    assert response.json()["reserved"] is True
