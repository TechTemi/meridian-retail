# Meridian Retail — D7 HTTPS / TLS Contract

## Production identity

Hostname:

`meridian-retail-temi.duckdns.org`

Elastic IP:

`98.88.168.236`

D5 proved authoritative DNS resolution. D6 proved the existing HTTP
routing contract through this exact hostname.

## Source ownership

The frozen Stage-7 artifact remains unchanged:

`nginx/meridian-http.conf`

D7 adds:

- `nginx/meridian-acme.conf`
- `nginx/meridian-https.conf`
- `ops/routing/install-nginx-d7.sh`
- `ops/routing/reload-nginx-after-renewal.sh`

## ACME qualification state

`nginx/meridian-acme.conf` explicitly owns the production hostname,
preserves the qualified application routing, and serves:

`/.well-known/acme-challenge/`

from:

`/var/www/meridian-acme`

It remains HTTP-only.

The challenge path must be externally proven before certificate
issuance.

## Certificate issuance contract

The intended Certbot model is:

`certbot certonly --webroot`

Webroot:

`/var/www/meridian-acme`

Certificate name and domain:

`meridian-retail-temi.duckdns.org`

The controlled runtime command must include:

`--deploy-hook /usr/local/sbin/meridian-certbot-deploy-hook`

so the hook is retained for subsequent renewals.

Expected lineage:

`/etc/letsencrypt/live/meridian-retail-temi.duckdns.org/`

No Certbot Nginx installer is used. Nginx remains source controlled.

## Final HTTPS state

`nginx/meridian-https.conf`:

- retains the ACME HTTP-01 challenge path;
- redirects all other canonical HTTP traffic to
  `https://meridian-retail-temi.duckdns.org`;
- does not trust arbitrary `$host` when constructing the redirect;
- listens on TCP/443;
- uses the exact production certificate lineage;
- permits TLS 1.2 and TLS 1.3 only;
- preserves the existing Meridian application routing.

Certificate paths:

`/etc/letsencrypt/live/meridian-retail-temi.duckdns.org/fullchain.pem`

`/etc/letsencrypt/live/meridian-retail-temi.duckdns.org/privkey.pem`

## Runtime invariants

Application upstreams remain:

- auth: `127.0.0.1:8001`
- catalog: `127.0.0.1:8002`
- orders: `127.0.0.1:8003`
- frontend: `127.0.0.1:8080`

PostgreSQL remains host-unpublished.

No production application container is recreated by D7.

Terraform remains zero-drift.

The protected backup stash remains unchanged.

## Renewal qualification

Before D7 closes, renewal must be tested with:

`certbot renew --cert-name meridian-retail-temi.duckdns.org --dry-run --run-deploy-hooks`

The deploy hook validates Nginx before reloading it.

## Prohibited shortcuts

D7 forbids:

- `curl -k`
- `--insecure`
- guessed hostnames
- manual Nginx edits
- Certbot-managed Nginx rewrites
- application container rebuilds
- removal of the PostgreSQL volume
