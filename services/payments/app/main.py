from uuid import uuid4

from fastapi import FastAPI
from pydantic import BaseModel
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI(title="Pedidos Veloz - Payments")


class PaymentRequest(BaseModel):
    order_id: str
    amount: float


@app.get("/health")
def health():
    return {"status": "ok", "service": "payments"}


@app.get("/ready")
def ready():
    return {"status": "ready", "service": "payments"}


@app.post("/payments")
def process_payment(payment: PaymentRequest):
    return {
        "id": str(uuid4()),
        "order_id": payment.order_id,
        "amount": payment.amount,
        "status": "APPROVED",
    }


Instrumentator().instrument(app).expose(app)
