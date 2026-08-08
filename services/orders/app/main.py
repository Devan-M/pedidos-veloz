from uuid import uuid4

from fastapi import FastAPI
from pydantic import BaseModel
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI(title="Pedidos Veloz - Orders")

orders = []


class OrderRequest(BaseModel):
    customer_id: str
    product_id: str
    quantity: int
    amount: float


@app.get("/health")
def health():
    return {"status": "ok", "service": "orders"}


@app.get("/ready")
def ready():
    return {"status": "ready", "service": "orders"}


@app.post("/orders", status_code=201)
def create_order(order: OrderRequest):
    new_order = {
        "id": str(uuid4()),
        "customer_id": order.customer_id,
        "product_id": order.product_id,
        "quantity": order.quantity,
        "amount": order.amount,
        "status": "CREATED",
    }

    orders.append(new_order)
    return new_order


@app.get("/orders")
def list_orders():
    return orders


Instrumentator().instrument(app).expose(app)
