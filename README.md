# Meridian Retail Group — Reverse Proxy, Domains, TLS & Multi-Service Foundations

This repository contains the pre-built Meridian Retail Group application
(three backend services, a frontend, and a Postgres database) used in the
DevOps Foundations internship project.

## What's already built (do not modify)

- `auth-service/main.py` — FastAPI signup/login/JWT service
- `catalog-service/app.js` — Express + Postgres product catalog service
- `orders-service/main.py` — FastAPI orders service (calls auth-service + catalog-service)
- `frontend/index.html` — static storefront (calls relative `/api/*` paths)
- `requirements.txt` / `package.json` — dependencies for each service

## What you need to build

The following files exist but are **empty** — you're building these from
scratch, with no starter code or hints:

- `auth-service/Dockerfile`
- `catalog-service/Dockerfile`
- `orders-service/Dockerfile`
- `frontend/Dockerfile`
- `docker-compose.yml` — wire all four services + Postgres together
- `scripts/server_setup.sh` — bootstrap a fresh EC2 instance (Docker, Nginx, Certbot)
- `nginx/meridian-http.conf` — your hand-written reverse proxy config
- `nginx/meridian-https-reference.conf` — filled in after running Certbot
- `scripts/backup_db.sh` — automated daily Postgres backup
- `scripts/restore_db.sh` — restore from a backup and prove it works
- `.github/workflows/ci.yml` — build + test on every push
- `.github/workflows/deploy.yml` — build, push to ECR, deploy on push to main
- `docs/routing-explained.md` — written explanation of your Nginx config
- `docs/backup-strategy.md` — written explanation of your backup approach

See the full project brief (provided separately) for the two-week schedule,
all ten deliverables (D1–D10), and the pre/post-assessment questions.

## Getting started locally

```bash
cp .env.example .env
# edit .env with real values (DB password, JWT secret, etc.)

# You'll need to write docker-compose.yml and each service's Dockerfile
# before this works:
docker compose up -d --build
docker compose ps          # all five containers should be Up
curl http://localhost:8080 # should return the storefront HTML
```

## Service ports (local/dev)

| Service          | Container Port | Host Port (127.0.0.1 only) |
|------------------|-----------------|------------------------------|
| auth-service     | 8000            | 8001                         |
| catalog-service  | 4000            | 8002                         |
| orders-service   | 8001            | 8003                         |
| frontend         | 80              | 8080 (public, temporary)     |
| postgres         | 5432            | 5432                         |

Once your reverse proxy is in place, the frontend's public port exposure
should be reconsidered — customers should reach everything through your
domain and Nginx, not a raw `:8080`.
