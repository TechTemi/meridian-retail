# Meridian Retail — Read-Only Demo Runbook

## 1. Purpose

This runbook provides a safe portfolio/interview demonstration path for the
completed Meridian Retail as-is project. The demo must not change production.

## 2. Safety rules

- do not push to `main`;
- do not merge a pull request;
- do not rerun or manually dispatch the production workflow;
- do not change security groups;
- do not restart or replace containers;
- do not display production `.env` contents;
- do not display SSH private-key or secret values.

Accepted production baseline:

`7d608b128f5404eb4a80d0b318bd3e616a730f7c`

## 3. Ten-minute demo sequence

### Step 1 — Explain the system

Architecture:

`Internet -> DuckDNS -> Elastic IP -> EC2 -> Nginx -> services`

Services: frontend, auth, catalog, orders and PostgreSQL.

### Step 2 — Prove the frozen production release

Run these read-only commands:

~~~powershell
git ls-remote --heads origin refs/heads/main
git ls-remote --tags origin refs/tags/production-ci-cd-baseline-7d608b1 'refs/tags/production-ci-cd-baseline-7d608b1^{}'
~~~

Expected production commit:

`7d608b128f5404eb4a80d0b318bd3e616a730f7c`

### Step 3 — Show the CI/CD workflow source

~~~powershell
git show production-ci-cd-baseline-7d608b1:.github/workflows/deploy.yml | Select-Object -First 120
~~~

Discuss OIDC, immutable ECR images, full-SHA tags, pinned actions, temporary
runner SSH ingress, Compose drift detection, pinned host identity and
fail-closed deployment behavior.

### Step 4 — Show the accepted GitHub Actions run

~~~powershell
gh run view 35412599053 --repo TechTemi/meridian-retail --json databaseId,headSha,headBranch,event,status,conclusion,url
~~~

Expected: branch `main`, event `push`, status `completed`, conclusion `success`,
head SHA `7d608b128f5404eb4a80d0b318bd3e616a730f7c`.

### Step 5 — Demonstrate public HTTPS health

~~~powershell
curl.exe -sS -o NUL -w "%{http_code}`n" https://meridian-retail-temi.duckdns.org/
curl.exe -sS -o NUL -w "%{http_code}`n" https://meridian-retail-temi.duckdns.org/api/auth/healthz
curl.exe -sS -o NUL -w "%{http_code}`n" https://meridian-retail-temi.duckdns.org/api/catalog/healthz
curl.exe -sS -o NUL -w "%{http_code}`n" https://meridian-retail-temi.duckdns.org/api/orders/healthz
~~~

Healthy endpoints are expected to return HTTP `200`.

### Step 6 — Explain PostgreSQL security

Use source-controlled Compose/database documentation instead of interactively
connecting to production. Explain that PostgreSQL is not host-published and
application services use separate least-privilege roles.

### Step 7 — Explain recovery

~~~powershell
git show postgres-backup-restore-baseline-0a825de:docs/backup-strategy.md | Select-Object -First 120
~~~

Discuss custom-format backup, SHA-256 integrity, isolated restore, controlled
recovery proof, live database protection and the daily systemd backup timer.

### Step 8 — Close with release traceability

`source -> PR -> merge SHA -> GitHub Actions -> immutable ECR tags -> production -> acceptance -> annotated baseline tag`

## 4. Interview talking points

Be prepared to explain why the implementation uses full commit SHA image tags,
immutable ECR repositories, OIDC rather than static cloud keys, pinned SSH host
identity, temporary runner ingress, Compose drift checking, isolated database
restore tests and an explicit non-automatic rollback model.

## 5. Demo stop conditions

Stop rather than improvise if `origin/main` differs from the frozen release,
the baseline tag resolves elsewhere, workflow run `35412599053` is no longer
attempt 1 / success, a health endpoint is unexpectedly unhealthy, or a command
would expose a secret or mutate production.
