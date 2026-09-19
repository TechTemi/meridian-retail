# Meridian Retail — Evidence Index

## 1. Authoritative production release

| Evidence | Value |
| --- | --- |
| Production release SHA | `7d608b128f5404eb4a80d0b318bd3e616a730f7c` |
| Production release tree | `dd75ec920998670ffc7754b13b188f6f42dfda11` |
| Production workflow ID | `361794473` |
| Production workflow run | `35412599053` |
| Run attempt | `1` |
| Run conclusion | `success` |
| Annotated baseline tag | `production-ci-cd-baseline-7d608b1` |
| Tag object | `9e28d7275157946ec070853f0a662b6683f56c78` |

## 2. Deliverable evidence map

| Deliverable | Requirement | Closure status | Governed evidence |
| --- | --- | --- | --- |
| D1 | Terraform custom VPC + EC2 | Complete | Repository/Terraform history; exact traceability finalized in C3 |
| D2 | SSH security-group whitelisting | Complete | Terraform/runtime evidence; exact traceability finalized in C3 |
| D3 | Four immutable ECR repositories | Complete | Terraform/live AWS evidence; exact traceability finalized in C3 |
| D4 | Least-privilege EC2 IAM | Complete | Terraform IAM and runtime profile evidence; exact traceability finalized in C3 |
| D5 | DuckDNS production mapping | Complete | Authoritative DNS qualification; exact traceability finalized in C3 |
| D6 | Nginx hostname routing | Complete | Production routing qualification; exact traceability finalized in C3 |
| D7 | HTTPS/TLS | Complete | Merge `cbf8a24e78abea6f74f9a3fe380e706a1eaea05e`; tag `https-tls-baseline-cbf8a24` |
| D8 | Secured PostgreSQL | Complete | Merge `81f2409674ab8188ad50df98a7d342436b53c49c`; tag `postgres-least-privilege-baseline-81f2409` |
| D9 | Backup + tested restore | Complete | Merge `0a825def4fb507bd3b6bf215571386acbb34df92`; tag `postgres-backup-restore-baseline-0a825de` |
| D10 | Production CI/CD | Complete | Merge `7d608b128f5404eb4a80d0b318bd3e616a730f7c`; run `35412599053`; tag `production-ci-cd-baseline-7d608b1` |

## 3. Immutable D10 application images

| Repository | Qualified digest |
| --- | --- |
| `meridian/auth` | `sha256:0ef9d27c1ff12324f5b1409ee74aea06ad8d909757c74b5bc26e6c9fbd7aab70` |
| `meridian/catalog` | `sha256:f9c8e64b5297bf251abd4a042870ca4e2cf5e0b4856dafa33798ed9f93e4bb65` |
| `meridian/orders` | `sha256:ff2c425c321968ebc8b63641a1c2d811d62b35fded536173f093dedffbb2ef34` |
| `meridian/frontend` | `sha256:53f193c394ec137c0b476b70298a15a61c6980ebcebcd74087947661327ea85b` |

## 4. Runtime acceptance

Final D10 acceptance established that the captured workflow completed
successfully, all four application release images existed in immutable ECR,
temporary runner SSH ingress was removed, source/live Compose hashes matched,
all five production containers were healthy, the four application containers
ran the exact release SHA, PostgreSQL remained pinned, and all public endpoint
checks passed.

## 5. Sensitive evidence handling

Portfolio artifacts must never contain SSH private keys, GitHub secret values,
database passwords, JWT secrets, DuckDNS tokens, AWS secret keys, production
`.env` contents or transient runner IP addresses.

## 6. C3 traceability boundary

D7-D10 have exact governed identifiers in this initial index. C3 audits the
historical record for D1-D6 and replaces broad descriptions with exact evidence
where the record supports it. A missing pointer here does not mean the
implementation is unfinished.
