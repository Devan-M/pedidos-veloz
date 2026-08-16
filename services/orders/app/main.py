import os
from contextlib import asynccontextmanager
from uuid import uuid4

import psycopg
from fastapi import FastAPI
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel
from psycopg.rows import dict_row


DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://localhost:5432/pedidos",
)


class OrderRequest(BaseModel):
    customer_id: str
    product_id: str
    quantity: int
    amount: float


def initialize_database() -> None:
    with psycopg.connect(DATABASE_URL) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS orders (
                    id UUID PRIMARY KEY,
                    customer_id TEXT NOT NULL,
                    product_id TEXT NOT NULL,
                    quantity INTEGER NOT NULL CHECK (quantity > 0),
                    amount NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
                    status TEXT NOT NULL,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
                """
            )


@asynccontextmanager
async def lifespan(app: FastAPI):
    initialize_database()
    yield


app = FastAPI(
    title="Pedidos Veloz - Orders",
    lifespan=lifespan,
)


@app.get("/health")
def health():
    return {"status": "ok", "service": "orders"}


@app.get("/ready")
def ready():
    return {"status": "ready", "service": "orders"}


@app.post("/orders", status_code=201)
def create_order(order: OrderRequest):
    order_id = uuid4()

    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO orders (
                    id, customer_id, product_id, quantity, amount, status
                )
                VALUES (%s, %s, %s, %s, %s, %s)
                RETURNING
                    id::text AS id,
                    customer_id,
                    product_id,
                    quantity,
                    amount::float8 AS amount,
                    status
                """,
                (
                    order_id,
                    order.customer_id,
                    order.product_id,
                    order.quantity,
                    order.amount,
                    "CREATED",
                ),
            )
            return cursor.fetchone()


@app.get("/orders")
def list_orders():
    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    id::text AS id,
                    customer_id,
                    product_id,
                    quantity,
                    amount::float8 AS amount,
                    status
                FROM orders
                ORDER BY created_at ASC, id ASC
                """
            )
            return cursor.fetchall()


Instrumentator().instrument(app).expose(app)
