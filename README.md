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

## New Concepts Reference Table

| Concept | Description | Status |
|---|---|---|
| Terraform & VPC | Automating custom network isolation, subnets, and server provisioning via code. | New to this project |
| IAM Instance Profile | Securely attaching scoped permissions directly to a server instead of using keys. | New to this project |
| Immutable ECR | Secure container registries that prevent overwriting existing image tags. | New to this project |
| Dynamic Security Groups | Modifying AWS firewall rules through CI/CD to whitelist runner IPs. | New to this project |
| Reverse Proxy | A server that sits in front of backend services and forwards client requests. | New to this project |
| `proxy_pass` directive | The Nginx directive that forwards a matched request to a backend address. | New to this project |
| DNS A record | A DNS record that maps a domain name to an IPv4 address. | New to this project |
| TLS / HTTPS (Certbot) | Encrypting traffic between the browser and the server. | New to this project |
| Docker Compose networking | Containers reaching each other by service name internally. | Existing knowledge |

## What You Will Build

The project has ten deliverables. Each deliverable has a specific,
observable verification. D9, the tested restore, and D10, the automated
deployment, most clearly distinguish this project from a tutorial because
both require proving that the system works end to end securely.

| Ref | Deliverable | Verification |
|---|---|---|
| D1 | Custom VPC and EC2 provisioned via Terraform | `terraform output` shows the VPC ID and EC2 public IP. The server runs Ubuntu 22.04. |
| D2 | Security group IP whitelisting | AWS Console confirms that port 22 is restricted exclusively to the intern's specific IP address. |
| D3 | Immutable ECR repositories | AWS Console shows ECR repositories for auth, catalog, orders, and frontend with mutability set to `IMMUTABLE`. |
| D4 | Least-privilege IAM role | `terraform state list` shows an `aws_iam_role` attached to the EC2 instance, allowing read-only access to ECR. |
| D5 | DuckDNS routing active | `dig yourdomain.duckdns.org +short` resolves exactly to the EC2 instance's public IP. |
| D6 | Manual Nginx routing correctly configured | `curl http://yourdomain.duckdns.org/api/auth/healthz` returns `200 OK` from the auth container. |
| D7 | HTTPS active and redirecting | `curl -I https://yourdomain.duckdns.org` returns HTTP 200 without a certificate warning. The browser padlock is confirmed. |
| D8 | Database deployed and secured | PostgreSQL runs in Docker Compose, its port is bound to `127.0.0.1` on the host, and it is seeded with sample data. |
| D9 | Backup restore tested | Drop a test row, restore from the backup using `scripts/restore_db.sh`, and confirm that the row reappears. |
| D10 | CI/CD pipeline automation | Pushing to `main` triggers GitHub Actions to build images, push them to ECR, dynamically update the EC2 security group for the runner IP, connect through SSH, and run `docker compose up -d`. |

## Repository and File Structure

The repository contains the full pre-built application as well as the
infrastructure work: Terraform configuration, Nginx configuration, backup
scripts, and CI/CD workflows.

```text
meridian-retail/
├── terraform/
│   ├── main.tf              # VPC, EC2, IAM, and ECR infrastructure
│   ├── variables.tf         # Region, personal IP, and other variables
│   └── outputs.tf            # EC2 public IP and VPC IDs
├── auth-service/
│   ├── main.py              # Signup, login, and JWT issuance
│   ├── requirements.txt
│   ├── Dockerfile
│   └── tests/test_auth.py
├── catalog-service/
│   ├── app.js               # Express + Postgres product listings
│   ├── package.json
│   └── Dockerfile
├── orders-service/
│   ├── main.py              # Calls auth-service and catalog-service
│   ├── requirements.txt
│   └── Dockerfile
├── frontend/
│   ├── index.html           # Storefront UI; calls /api/* on the same domain
│   └── Dockerfile
├── nginx/
│   ├── meridian-http.conf   # Phase 1: hand-written HTTP routing config
│   └── meridian-https-reference.conf # Phase 2: Certbot-generated reference
├── scripts/
│   ├── backup_db.sh         # Create PostgreSQL backups
│   ├── restore_db.sh        # Restore PostgreSQL backups
│   ├── server_setup.sh      # Bootstrap Docker, Nginx, and Certbot
│   └── ...
├── .github/workflows/
│   ├── ci.yml               # Build and test on every push
│   └── deploy.yml           # Build, publish, and deploy to EC2
├── docker-compose.yml
└── README.md
```

