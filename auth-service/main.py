"""
Meridian Retail Group — auth-service
FastAPI service handling signup, login, and JWT issuance/verification.

This service is PRE-BUILT for the assessment. Do not modify application
logic — your job is the infrastructure around it (reverse proxy, TLS,
backups, CI/CD), not the app code itself.

Endpoints:
    GET  /healthz              -> liveness check used by Nginx/monitoring
    POST /api/auth/signup      -> create a user, returns a JWT
    POST /api/auth/login       -> authenticate a user, returns a JWT
    GET  /api/auth/verify      -> verify a JWT (used internally by orders-service)
"""

import os
import time
import uuid
from datetime import datetime, timedelta

import jwt
import bcrypt
import psycopg2
import psycopg2.extras
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel, EmailStr

app = FastAPI(title="auth-service")

DB_HOST = os.getenv("DB_HOST", "postgres")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "meridian_db")
DB_USER = os.getenv("DB_USER", "meridian")
DB_PASSWORD = os.getenv("DB_PASSWORD", "meridian")
JWT_SECRET = os.getenv("JWT_SECRET", "change-me-in-env")
JWT_ALGO = "HS256"
JWT_EXPIRY_MINUTES = int(os.getenv("JWT_EXPIRY_MINUTES", "60"))


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
            CREATE TABLE IF NOT EXISTS users (
                id UUID PRIMARY KEY,
                email TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                created_at TIMESTAMPTZ DEFAULT now()
            );
            """
        )
    conn.close()


@app.on_event("startup")
def on_startup():
    init_db()


class SignupRequest(BaseModel):
    email: EmailStr
    password: str


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


def make_token(user_id: str, email: str) -> str:
    payload = {
        "sub": user_id,
        "email": email,
        "exp": datetime.utcnow() + timedelta(minutes=JWT_EXPIRY_MINUTES),
        "iat": datetime.utcnow(),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGO)


@app.get("/healthz")
def healthz():
    return {"status": "ok", "service": "auth-service"}


@app.post("/api/auth/signup")
def signup(req: SignupRequest):
    conn = get_conn()
    try:
        with conn, conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE email = %s", (req.email,))
            if cur.fetchone():
                raise HTTPException(status_code=409, detail="Email already registered")

            user_id = str(uuid.uuid4())
            password_hash = bcrypt.hashpw(req.password.encode(), bcrypt.gensalt()).decode()
            cur.execute(
                "INSERT INTO users (id, email, password_hash) VALUES (%s, %s, %s)",
                (user_id, req.email, password_hash),
            )
        token = make_token(user_id, req.email)
        return {"token": token, "user_id": user_id, "email": req.email}
    finally:
        conn.close()


@app.post("/api/auth/login")
def login(req: LoginRequest):
    conn = get_conn()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("SELECT id, password_hash FROM users WHERE email = %s", (req.email,))
            row = cur.fetchone()
        if not row or not bcrypt.checkpw(req.password.encode(), row["password_hash"].encode()):
            raise HTTPException(status_code=401, detail="Invalid credentials")
        token = make_token(row["id"], req.email)
        return {"token": token, "user_id": row["id"], "email": req.email}
    finally:
        conn.close()


@app.get("/api/auth/verify")
def verify(authorization: str = Header(default=None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.split(" ", 1)[1]
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGO])
    except jwt.PyJWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return {"valid": True, "user_id": payload["sub"], "email": payload["email"]}
