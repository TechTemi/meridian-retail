# Meridian Retail Host Routing Contract

## Status

This document replaces the empty routing placeholder that existed in
the original repository.

Stage 7 establishes the source-controlled host-level HTTP routing
contract for the already-qualified Stage-6 production deployment.

## Qualified Stage-6 upstreams

| Component | Host upstream | Direct public exposure |
| --- | --- | --- |
| Auth service | `127.0.0.1:8001` | No |
| Catalog service | `127.0.0.1:8002` | No |
| Orders service | `127.0.0.1:8003` | No |
| Frontend | `127.0.0.1:8080` | No |
| PostgreSQL | no host binding | No |

The loopback bindings above were qualified during Stage 6 and are not
changed by Stage 7.

## Public HTTP route map

| Public path | Nginx upstream |
| --- | --- |
| `/api/auth/healthz` | `http://127.0.0.1:8001/healthz` |
| `/api/catalog/healthz` | `http://127.0.0.1:8002/healthz` |
| `/api/orders/healthz` | `http://127.0.0.1:8003/healthz` |
| `/api/auth/*` | `http://127.0.0.1:8001` |
| `/api/catalog/*` | `http://127.0.0.1:8002` |
| `/api/orders*` | `http://127.0.0.1:8003` |
| all remaining paths | `http://127.0.0.1:8080` |

Normal application API request URIs are preserved exactly.

The three health endpoints are explicit aliases because the backend
services expose their native health endpoint at `/healthz`.

## Nginx ownership

Canonical repository source:

`nginx/meridian-http.conf`

Production installed file:

`/etc/nginx/sites-available/meridian`

Production enabled link:

`/etc/nginx/sites-enabled/meridian`

The Ubuntu default site is disabled only as part of the controlled
installer transaction.

## Network boundary

Public traffic terminates at host Nginx.

The following application ports remain loopback-only:

- `8001`
- `8002`
- `8003`
- `8080`

PostgreSQL port `5432` remains internal and host-unpublished.

No Stage-7 security-group rule may expose those ports.

## Installation

The controlled installer is:

`ops/routing/install-nginx-routing.sh`

It:

1. requires root;
2. confirms Nginx is already active;
3. preserves the previous site state;
4. installs the canonical Meridian configuration;
5. enables the Meridian site;
6. removes the Ubuntu default-site symlink;
7. runs `nginx -t`;
8. reloads rather than restarts Nginx;
9. validates the final site state;
10. automatically restores the previous state if a mutating step fails.

Rollback evidence is retained beneath:

`/var/lib/meridian/nginx-rollback/<run-id>/`

## Runtime acceptance contract

Stage 7 runtime qualification must prove:

1. `/` returns the Meridian storefront rather than the Ubuntu default page.
2. `/api/auth/healthz` returns the auth-service health response.
3. `/api/catalog/healthz` returns the catalog-service health response.
4. `/api/orders/healthz` returns the orders-service health response.
5. `/api/catalog/products` returns exactly five products.
6. Existing authentication paths remain functional through public Nginx.
7. Existing order paths remain functional through public Nginx.
8. The exact Stage-6 containers are not recreated.
9. The exact Stage-6 application images remain unchanged.
10. PostgreSQL remains host-unpublished.
11. Application ports remain loopback-only.
12. Terraform remains at zero infrastructure drift.

## HTTPS boundary

HTTPS is deliberately outside this HTTP routing slice.

The AWS security group already permits TCP/443, but Stage 7A did not
establish an authoritative production DNS name or certificate.

A separate controlled TLS slice must establish and qualify:

- authoritative DNS ownership;
- hostname-to-EIP resolution;
- certificate issuance;
- HTTP-to-HTTPS redirection;
- automatic certificate renewal;
- TLS endpoint validation.

No guessed or placeholder domain is permitted in the production Nginx
configuration.

## Legacy placeholder

`scripts/server_setup.sh` remains the untouched zero-byte legacy
placeholder from the original repository.

Stage 5 already established the authoritative production host bootstrap
implementation under:

`ops/bootstrap/bootstrap-host.sh`

Stage 7 therefore does not repurpose or silently rewrite the legacy
placeholder.
