from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_process_payment():
    response = client.post(
        "/payments",
        json={
            "order_id": "order-1",
            "amount": 99.90,
        },
    )

    assert response.status_code == 200
    assert response.json()["status"] == "APPROVED"
