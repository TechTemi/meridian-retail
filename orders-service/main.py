"""
Meridian Retail Group — orders-service
FastAPI service that places orders, calling auth-service (to verify the
user's JWT) and catalog-service (to validate the product and price)
over the internal Docker Compose network.

This service is PRE-BUILT for the assessment. Do not modify application
logic — your job is the infrastructure around it, not the app code.

Endpoints:
    GET  /healthz          -> liveness check used by Nginx/monitoring
    POST /api/orders       -> place an order (requires Authorization: Bearer <jwt>)
    GET  /api/orders       -> list orders for the authenticated user
"""

import os
import time
import uuid

import httpx
import psycopg2
import psycopg2.extras
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel

app = FastAPI(title="orders-service")

DB_HOST = os.getenv("DB_HOST", "postgres")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "meridian_db")
DB_USER = os.getenv("DB_USER", "meridian")
DB_PASSWORD = os.getenv("DB_PASSWORD", "meridian")

# Internal, container-to-container URLs (Docker Compose service names).
# These are NOT the same as the host-mapped ports Nginx uses.
AUTH_SERVICE_URL = os.getenv("AUTH_SERVICE_URL", "http://auth-service:8000")
CATALOG_SERVICE_URL = os.getenv("CATALOG_SERVICE_URL", "http://catalog-service:4000")


def get_conn():
    for attempt in range(10):
        try:
            return psycopg2.connect(
                host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
                user=DB_USER, password=DB_PASSWORD,
            )
        except psycopg2.OperationalError:
            time.sleep(2)
    raise RuntimeError("Could not connect to database after retries")


def init_db():
    conn = get_conn()
    with conn, conn.cursor() as cur:
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS orders (
                id UUID PRIMARY KEY,
                user_id TEXT NOT NULL,
                product_id INTEGER NOT NULL,
                quantity INTEGER NOT NULL,
                total_price NUMERIC(10, 2) NOT NULL,
                created_at TIMESTAMPTZ DEFAULT now()
            );
            """
        )
    conn.close()


@app.on_event("startup")
def on_startup():
    init_db()


class OrderRequest(BaseModel):
    product_id: int
    quantity: int = 1


def verify_token(authorization: str) -> dict:
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing Authorization header")
    try:
        resp = httpx.get(
            f"{AUTH_SERVICE_URL}/api/auth/verify",
            headers={"Authorization": authorization},
            timeout=5.0,
        )
    except httpx.RequestError:
        raise HTTPException(status_code=502, detail="auth-service unreachable")
    if resp.status_code != 200:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return resp.json()


def fetch_product(product_id: int) -> dict:
    try:
        resp = httpx.get(
            f"{CATALOG_SERVICE_URL}/api/catalog/products/{product_id}", timeout=5.0
        )
    except httpx.RequestError:
        raise HTTPException(status_code=502, detail="catalog-service unreachable")
    if resp.status_code == 404:
        raise HTTPException(status_code=404, detail="Product not found")
    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail="catalog-service error")
    return resp.json()


@app.get("/healthz")
def healthz():
    return {"status": "ok", "service": "orders-service"}


@app.post("/api/orders")
def place_order(order: OrderRequest, authorization: str = Header(default=None)):
    user = verify_token(authorization)
    product = fetch_product(order.product_id)

    total_price = float(product["price"]) * order.quantity
    order_id = str(uuid.uuid4())

    conn = get_conn()
    try:
        with conn, conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO orders (id, user_id, product_id, quantity, total_price)
                VALUES (%s, %s, %s, %s, %s)
                """,
                (order_id, user["user_id"], order.product_id, order.quantity, total_price),
            )
    finally:
        conn.close()

    return {
        "order_id": order_id,
        "product": product["name"],
        "quantity": order.quantity,
        "total_price": total_price,
    }


@app.get("/api/orders")
def list_orders(authorization: str = Header(default=None)):
    user = verify_token(authorization)
    conn = get_conn()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(
                "SELECT * FROM orders WHERE user_id = %s ORDER BY created_at DESC",
                (user["user_id"],),
            )
            rows = cur.fetchall()
        return rows
    finally:
        conn.close()
