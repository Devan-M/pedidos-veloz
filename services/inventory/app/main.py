from fastapi import FastAPI
from pydantic import BaseModel
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI(title="Pedidos Veloz - Inventory")

stock = {
    "product-1": 100,
    "product-2": 50,
}


class ReserveRequest(BaseModel):
    product_id: str
    quantity: int


@app.get("/health")
def health():
    return {"status": "ok", "service": "inventory"}


@app.get("/ready")
def ready():
    return {"status": "ready", "service": "inventory"}


@app.post("/inventory/reserve")
def reserve_stock(request: ReserveRequest):
    available = stock.get(request.product_id, 0)

    if available < request.quantity:
        return {
            "reserved": False,
            "reason": "insufficient_stock",
        }

    stock[request.product_id] -= request.quantity

    return {
        "reserved": True,
        "product_id": request.product_id,
        "quantity": request.quantity,
        "remaining": stock[request.product_id],
    }


Instrumentator().instrument(app).expose(app)
