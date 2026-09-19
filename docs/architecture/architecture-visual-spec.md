# Meridian Retail — Architecture Visual Specification

## 1. Purpose

This specification defines the portfolio visual assets for the completed
Meridian Retail as-is implementation.

The diagrams are derived only from qualified repository source and the closed
D1-D10 evidence package. They must explain the implementation without adding
unverified production capabilities.

Production remains frozen at:

`7d608b128f5404eb4a80d0b318bd3e616a730f7c`

The documentation branch remains separate from `main`.

## 2. Visual design principles

The final rendered diagrams should be:

- technically accurate before decorative;
- readable at normal GitHub and presentation widths;
- understandable by recruiters and hiring managers without code inspection;
- detailed enough for a DevOps / DevSecOps technical interview;
- explicit about production boundaries;
- free of credentials, secret values and private key material;
- free of invented managed services or network tiers that are not present in
  the qualified implementation.

Each diagram should have one clear story and should not attempt to represent
every implementation detail simultaneously.

## 3. Qualified architecture facts

### Public request path

The qualified public request path is:

`Internet -> DuckDNS -> Elastic IP -> EC2 -> Nginx -> application services`

The production hostname is:

`meridian-retail-temi.duckdns.org`

Nginx accepts HTTP/HTTPS and routes application traffic to loopback-bound
container ports on the production EC2 host.

### AWS infrastructure

Terraform provisions or governs:

- one custom VPC;
- one public subnet;
- an Internet Gateway;
- public routing;
- the application security group;
- the Ubuntu EC2 application host;
- a stable Elastic IP;
- four immutable ECR repositories;
- the EC2 application IAM role and instance profile;
- the GitHub deployment IAM role;
- the GitHub OIDC provider;
- a protected S3 backup bucket;
- supporting key-pair and lifecycle/security resources.

Do not add an Application Load Balancer, NAT Gateway, ECS, EKS, RDS, CloudFront
or Route 53 to the diagrams. Those services are not part of the qualified
as-is implementation.

### Runtime services

The production Docker Compose runtime contains:

- `frontend`
- `auth`
- `catalog`
- `orders`
- `postgres`

Loopback bindings are:

- auth: host `127.0.0.1:8001` -> container `8000`
- catalog: host `127.0.0.1:8002` -> container `4000`
- orders: host `127.0.0.1:8003` -> container `8001`
- frontend: host `127.0.0.1:8080` -> container `80`

PostgreSQL uses port `5432` internally and is not published as a public host
port.

### Nginx request routing

The source-controlled Nginx routing contract includes:

- HTTP port `80`;
- HTTPS port `443`;
- TLS 1.2 and TLS 1.3;
- ACME HTTP-01 challenge handling;
- `/api/auth/` -> `127.0.0.1:8001`;
- `/api/catalog/` -> `127.0.0.1:8002`;
- `/api/orders` -> `127.0.0.1:8003`;
- `/` -> `127.0.0.1:8080`.

### CI/CD delivery

The production GitHub Actions workflow:

- triggers on push to `main`;
- has `contents: read`;
- has `id-token: write`;
- uses GitHub OIDC to assume the AWS deployment role;
- works with immutable ECR release images;
- uses the exact Git commit SHA as release identity;
- uses a temporary GitHub runner `/32` SSH ingress rule;
- uses pinned production SSH host identity;
- checks source/live production Compose drift;
- deploys through the governed production deployment helper;
- cleans up the temporary runner ingress rule;
- uses a concurrency control with `cancel-in-progress: false`;
- does not use automatic rollback.

The frozen accepted workflow run is:

`35412599053`

### Database backup and restore

The D9 recovery design includes:

- a daily systemd timer;
- `pg_dump` backup creation;
- a SHA-256 checksum sidecar;
- an isolated restore target;
- `pg_restore` archive validation;
- restore targets restricted to names beginning with `meridian_d9_`;
- explicit refusal to restore over the live source database;
- post-restore D8 schema validation;
- cleanup of incomplete restore targets.

Terraform also provisions protected S3 backup storage. The D9 backup/restore
diagram must not imply a live S3 upload path unless that transfer is separately
qualified by source or runtime evidence. The visual may show S3 as provisioned
supporting infrastructure, but not as an asserted D9 transfer step.

## 4. Planned visual assets

### 01 — System Context

Audience:
Recruiter, hiring manager, technical interviewer.

Story:
Show the entire Meridian production system in one view, from the user/browser
through DNS and AWS edge identity to EC2/Nginx, the application services and
PostgreSQL. Show GitHub Actions and ECR as the delivery plane.

Must show:

- browser/user;
- DuckDNS;
- Elastic IP;
- EC2;
- Nginx;
- frontend/auth/catalog/orders/PostgreSQL;
- GitHub Actions;
- AWS OIDC role relationship;
- ECR release images.

Must not imply:

- load balancing;
- Kubernetes;
- managed RDS;
- Route 53 DNS.

### 02 — AWS Production Architecture

Audience:
Cloud/DevOps interviewer.

Story:
Show how Terraform-created AWS infrastructure surrounds the EC2 host.

Must show:

- Internet;
- VPC;
- public subnet;
- Internet Gateway;
- route table/public route;
- security group;
- Elastic IP;
- EC2 host;
- EC2 instance profile / IAM role;
- four ECR repositories;
- GitHub OIDC provider and deployment role;
- protected S3 backup bucket.

Use a dashed or annotated relationship for S3 if shown near backup/recovery;
do not assert an unqualified runtime upload route.

### 03 — Request Routing

Audience:
DevOps / platform interviewer.

Story:
Explain the exact Nginx-to-loopback routing contract.

Must show:

- hostname;
- HTTP 80;
- HTTPS 443;
- ACME challenge route;
- frontend `/` -> `127.0.0.1:8080`;
- auth `/api/auth/` -> `127.0.0.1:8001`;
- catalog `/api/catalog/` -> `127.0.0.1:8002`;
- orders `/api/orders` -> `127.0.0.1:8003`;
- service-to-PostgreSQL relationship.

### 04 — CI/CD Release Flow

Audience:
DevOps / DevSecOps interviewer.

Story:
Explain how a reviewed main-branch release becomes immutable application
artifacts and then a production deployment.

Must show:

- push to `main`;
- exact release SHA;
- GitHub Actions;
- OIDC federation;
- AWS deployment role;
- immutable ECR images;
- temporary runner `/32`;
- pinned SSH host identity;
- Compose drift interlock;
- production deploy helper;
- EC2 / Docker Compose;
- runner-rule cleanup;
- final acceptance / frozen baseline tag.

### 05 — Database Backup and Restore

Audience:
SRE / DevOps interviewer.

Story:
Show the safety controls in the D9 backup and recovery path.

Must show:

- daily systemd timer;
- backup service/script;
- `pg_dump`;
- custom backup artifact;
- SHA-256 sidecar;
- restore script;
- checksum validation;
- isolated `meridian_d9_*` target;
- `pg_restore`;
- D8 schema validation;
- live `meridian_db` protected from destructive restore;
- cleanup on failed/incomplete restore.

## 5. Rendering boundary

C4.2 creates diagram source only.

C4.3 may render these Mermaid sources to portfolio-friendly SVG and/or PNG
assets after source validation. Rendering must not modify `main` or production.

C4.4 will validate and publish the final C4 asset package from the documentation
branch only.

## 6. Architecture truth rule

If a rendered diagram conflicts with Terraform, Compose, Nginx, CI/CD,
database/recovery source or the D1-D10 evidence index, the source/evidence wins
and the diagram must be corrected.

`C4_ARCHITECTURE_SOURCE_OF_TRUTH=QUALIFIED_REPOSITORY_AND_CLOSURE_EVIDENCE`
