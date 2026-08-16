import os

import httpx
from fastapi import FastAPI, HTTPException
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI(title="Pedidos Veloz - Gateway")

ORDERS_URL = os.getenv("ORDERS_URL", "http://orders:8000")
PAYMENTS_URL = os.getenv("PAYMENTS_URL", "http://payments:8000")
INVENTORY_URL = os.getenv("INVENTORY_URL", "http://inventory:8000")


@app.get("/health")
def health():
    return {"status": "ok", "service": "gateway"}


@app.get("/ready")
def ready():
    return {"status": "ready", "service": "gateway"}


@app.post("/api/orders")
async def create_order(payload: dict):
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(
                f"{ORDERS_URL}/orders",
                json=payload,
                timeout=5,
            )
            response.raise_for_status()
            return response.json()
        except httpx.HTTPError as exc:
            raise HTTPException(
                status_code=502,
                detail=f"orders service unavailable: {exc}",
            ) from exc


@app.post("/api/payments")
async def process_payment(payload: dict):
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(
                f"{PAYMENTS_URL}/payments",
                json=payload,
                timeout=5,
            )
            response.raise_for_status()
            return response.json()
        except httpx.HTTPError as exc:
            raise HTTPException(
                status_code=502,
                detail=f"payments service unavailable: {exc}",
            ) from exc


@app.post("/api/inventory/reserve")
async def reserve_inventory(payload: dict):
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(
                f"{INVENTORY_URL}/inventory/reserve",
                json=payload,
                timeout=5,
            )
            response.raise_for_status()
            return response.json()
        except httpx.HTTPError as exc:
            raise HTTPException(
                status_code=502,
                detail=f"inventory service unavailable: {exc}",
            ) from exc


Instrumentator().instrument(app).expose(app)
