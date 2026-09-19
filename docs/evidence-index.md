# Meridian Retail — Evidence Index

## 1. Purpose

This index provides the authoritative traceability map for the completed
Meridian Retail as-is implementation.

The as-is delivery scope is D1 through D10. The project is implementation
complete. This document records the governed source, merge, tag, workflow and
runtime evidence that supports that closure.

This index deliberately distinguishes three evidence types:

1. **governed source evidence** — pull requests, source commits, merge commits,
   files and annotated baseline tags;
2. **operational qualification evidence** — DNS, routing, TLS, database,
   backup/restore and production runtime validation;
3. **release evidence** — the exact production merge SHA, immutable container
   digests, GitHub Actions deployment run and final production baseline tag.

A deliverable does not need a dedicated source-code PR if its implementation
was an operational qualification activity. D5 is the principal example.

---

## 2. Authoritative final production release

| Evidence | Frozen value |
| --- | --- |
| Repository | `TechTemi/meridian-retail` |
| Production release SHA | `7d608b128f5404eb4a80d0b318bd3e616a730f7c` |
| Production release tree | `dd75ec920998670ffc7754b13b188f6f42dfda11` |
| Production workflow ID | `361794473` |
| Production workflow run | `35412599053` |
| Workflow attempt | `1` |
| Workflow event | `push` |
| Workflow branch | `main` |
| Workflow conclusion | `success` |
| Production baseline tag | `production-ci-cd-baseline-7d608b1` |
| D10 annotated tag object | `9e28d7275157946ec070853f0a662b6683f56c78` |
| Production hostname | `meridian-retail-temi.duckdns.org` |
| Production Elastic IP | `98.88.168.236` |

The final production baseline is frozen. The annotated D10 tag must not be
retargeted, recreated, force-updated or republished.

---

## 3. Governed implementation baseline chain

The following source-governed baselines form the implementation chain that
supports D1-D10.

| Baseline | PR | Qualified head | Governed merge | Annotated tag | Tag object |
| --- | ---: | --- | --- | --- | --- |
| AWS infrastructure foundation | #3 | `f1b24d502cf24ed6eaaa2d61e182a8634f5e890c` | `166ae0b98598c0d8113c8cc88c9af6c7c9373bfc` | `aws-infrastructure-baseline-166ae0b` | `46d245e1a0ce84a347fa9375b20a122b80e04d90` |
| Production host bootstrap | #4 | `43155db5bec7701654291549c475c547f41d1712` | `94d9d5dc93954a9f16fb83ed7e52a26ac78037e3` | `server-bootstrap-baseline-94d9d5d` | `10d1b900e40192dac197c819181ac8d32d40e65e` |
| Production deployment contract | #5 | `4bb812e9d27f70716bf19bc9dafee10e1852a48a` | `83dc755e57db1d03ee9d3c017303402058dc55c8` | `production-deployment-baseline-83dc755` | `bc285b6a9e35aafbc969cc35fa2766dce6802868` |
| HTTP/Nginx routing contract | #6 | `775333356794ca448647ece2f72f62ec86720f23` | `d4ee733fe9df48d7a47f28711ca02f6183c1e3d0` | `http-routing-baseline-d4ee733` | `9988568458270728aea24c427310cbec9bb8f2e5` |
| D7 HTTPS/TLS | #7 | `37e35725b89bac545a994b0512e47c33071f06d2` | `cbf8a24e78abea6f74f9a3fe380e706a1eaea05e` | `https-tls-baseline-cbf8a24` | `316f996d4d580555e3019080bf1d05500b5f5fc4` |
| D8 PostgreSQL least privilege | #8 | `1bac4a9c5c1ae264925027d6c5fa51a20f108e86` | `81f2409674ab8188ad50df98a7d342436b53c49c` | `postgres-least-privilege-baseline-81f2409` | `1d0234b7c3cce0d654b1ed60c089e04becb2a5c6` |
| D9 backup/restore automation | #9 | `d6a90572e9eb0d16867a5f77095410e7f2c6f68c` | `0a825def4fb507bd3b6bf215571386acbb34df92` | `postgres-backup-restore-baseline-0a825de` | `3bbcfaaf650fdfd6665acbea08f40f9b34d40071` |
| D10 production CI/CD | #10 | `53e016d03245655d4f5f7a43fd408a91fd9cede6` | `7d608b128f5404eb4a80d0b318bd3e616a730f7c` | `production-ci-cd-baseline-7d608b1` | `9e28d7275157946ec070853f0a662b6683f56c78` |

Every baseline above was independently reconciled in C3.1 so that the PR merge
SHA exactly equals the peeled annotated-tag target.

---

## 4. D1-D10 authoritative traceability matrix

| Deliverable | Requirement | Evidence type | Exact traceability | Closure |
| --- | --- | --- | --- | --- |
| D1 | Terraform custom VPC + EC2 | Governed source | PR #3; merge `166ae0b98598c0d8113c8cc88c9af6c7c9373bfc`; tag `aws-infrastructure-baseline-166ae0b`; key source `terraform/network.tf`, `terraform/ec2.tf`, `terraform/eip.tf` | Complete |
| D2 | SSH security-group IP whitelisting / network access control | Governed source | PR #3; security-control commit `a86ed03c020aaf37a564d09bc8963ae375c90d87`; merge `166ae0b98598c0d8113c8cc88c9af6c7c9373bfc`; key source `terraform/security.tf` | Complete |
| D3 | Four immutable ECR repositories | Governed source + runtime qualification | PR #3; ECR commit `e018dc4cb2eab1f816eb4a38453fecb6ea211718`; merge `166ae0b98598c0d8113c8cc88c9af6c7c9373bfc`; key source `terraform/ecr.tf`; immutable ECR later requalified during D10 acceptance | Complete |
| D4 | Least-privilege EC2 IAM role | Governed source + runtime qualification | PR #3; IAM commit `4b8b02a45acdbb43a3f27465053a53ba5c561941`; merge `166ae0b98598c0d8113c8cc88c9af6c7c9373bfc`; key source `terraform/iam.tf`; runtime instance-profile identity later requalified | Complete |
| D5 | DuckDNS hostname -> production EIP | Operational qualification | Hostname `meridian-retail-temi.duckdns.org`; EIP `98.88.168.236`; source context frozen at PR #6 / merge `d4ee733fe9df48d7a47f28711ca02f6183c1e3d0` / tag `http-routing-baseline-d4ee733`; DNS mapping was subsequently carried forward and requalified before D6/TLS | Complete |
| D6 | Nginx routing through production hostname | Governed source + operational routing qualification | PR #6; head `775333356794ca448647ece2f72f62ec86720f23`; merge `d4ee733fe9df48d7a47f28711ca02f6183c1e3d0`; tag `http-routing-baseline-d4ee733`; key files `nginx/meridian-http.conf`, `ops/routing/install-nginx-routing.sh`, `ops/validation/Invoke-MeridianStage7SourceGate.ps1`; hostname routing acceptance passed | Complete and frozen |
| D7 | HTTPS/TLS | Governed source + production TLS qualification | PR #7; head `37e35725b89bac545a994b0512e47c33071f06d2`; merge `cbf8a24e78abea6f74f9a3fe380e706a1eaea05e`; tag `https-tls-baseline-cbf8a24`; source-controlled ACME, HTTPS and renewal contracts | Complete and frozen |
| D8 | PostgreSQL least-privilege runtime | Governed source + database acceptance | PR #8; head `1bac4a9c5c1ae264925027d6c5fa51a20f108e86`; merge `81f2409674ab8188ad50df98a7d342436b53c49c`; tag `postgres-least-privilege-baseline-81f2409`; D8 SQL/apply/rollback/source-gate artifacts | Complete and frozen |
| D9 | Backup + tested restore | Governed source + recovery acceptance | PR #9; final head `d6a90572e9eb0d16867a5f77095410e7f2c6f68c`; merge `0a825def4fb507bd3b6bf215571386acbb34df92`; tag `postgres-backup-restore-baseline-0a825de`; source-controlled backup/restore/systemd contracts and isolated restore proof | Complete and frozen |
| D10 | Automated production CI/CD | Governed source + immutable release acceptance | PR #10; final head `53e016d03245655d4f5f7a43fd408a91fd9cede6`; merge/release `7d608b128f5404eb4a80d0b318bd3e616a730f7c`; workflow run `35412599053`; tag `production-ci-cd-baseline-7d608b1` | Complete and evidence-frozen |

---

## 5. D1-D4 infrastructure commit evidence

PR #3 contains eleven implementation commits. The commits most directly tied
to the as-is deliverables are:

| Commit | Subject | Primary closure relevance |
| --- | --- | --- |
| `ee6a3fc4580ddfbb1ff285989662976064643357` | `feat: establish Terraform AWS foundation` | Provider/version/state foundation |
| `633bfb97c82ad3d3d5415aedd1cf85fb7955dcc8` | `feat: provision Meridian VPC networking` | D1 VPC networking |
| `a86ed03c020aaf37a564d09bc8963ae375c90d87` | `feat: enforce Meridian network security controls` | D2 security-group controls |
| `e018dc4cb2eab1f816eb4a38453fecb6ea211718` | `feat: provision immutable Meridian ECR repositories` | D3 immutable ECR |
| `4b8b02a45acdbb43a3f27465053a53ba5c561941` | `feat: enforce least-privilege EC2 instance IAM` | D4 EC2 IAM |
| `7755cecccc84417abca218ee41262df7967d7629` | `feat: establish GitHub Actions OIDC deployment identity` | Later D10 deployment identity foundation |
| `78073d237b3e2ebc7927e5526a0eace80cd1d64d` | `feat: provision Ubuntu EC2 application host` | D1 EC2 |
| `5af345220ede6bfb6f63d45e864e795d843284ed` | `feat: harden Meridian EC2 instance` | Host hardening |
| `b630b737f53866b2b9338879d539b6930815f592` | `feat: assign stable Elastic IP to Meridian host` | Stable production address |
| `f1b24d502cf24ed6eaaa2d61e182a8634f5e890c` | `fix: reconcile EC2 public IP state with Elastic IP` | Final Stage-4 qualified head |

The infrastructure merge contains fourteen Terraform files including:

- `terraform/network.tf`
- `terraform/security.tf`
- `terraform/ec2.tf`
- `terraform/eip.tf`
- `terraform/ecr.tf`
- `terraform/iam.tf`
- `terraform/github_oidc.tf`
- `terraform/s3.tf`
- provider, version, variable, local and output contracts

The governed infrastructure merge is
`166ae0b98598c0d8113c8cc88c9af6c7c9373bfc`.

---

## 6. Supporting pre-D5 production baselines

These baselines are not separate D1-D10 deliverable numbers, but they form the
governed delivery chain that made D5 and D6 possible.

### Stage 5 — production host bootstrap

- PR: `#4`
- qualified head:
  `43155db5bec7701654291549c475c547f41d1712`
- governed merge:
  `94d9d5dc93954a9f16fb83ed7e52a26ac78037e3`
- annotated baseline:
  `server-bootstrap-baseline-94d9d5d`
- source artifact:
  `ops/bootstrap/bootstrap-host.sh`

### Stage 6 — production deployment contract

- PR: `#5`
- final qualified head:
  `4bb812e9d27f70716bf19bc9dafee10e1852a48a`
- governed merge:
  `83dc755e57db1d03ee9d3c017303402058dc55c8`
- annotated baseline:
  `production-deployment-baseline-83dc755`
- key source:
  - `ops/deployment/deploy-production.sh`
  - `ops/deployment/docker-compose.production.yml`
  - `ops/validation/Invoke-MeridianStage6Gate.ps1`
  - `ops/validation/stage6-invariants.json`

### Stage 7 — source-controlled HTTP/Nginx routing

- PR: `#6`
- qualified head:
  `775333356794ca448647ece2f72f62ec86720f23`
- governed merge:
  `d4ee733fe9df48d7a47f28711ca02f6183c1e3d0`
- annotated baseline:
  `http-routing-baseline-d4ee733`
- key source:
  - `nginx/meridian-http.conf`
  - `ops/routing/install-nginx-routing.sh`
  - `ops/validation/Invoke-MeridianStage7SourceGate.ps1`
  - `docs/routing-explained.md`

---

## 7. D5 DNS evidence classification

D5 is intentionally classified as an **operational DNS qualification** rather
than a dedicated source-code merge.

The authoritative production identity is:

- hostname: `meridian-retail-temi.duckdns.org`
- production EIP: `98.88.168.236`

The source/governance context remained frozen at the already-qualified
Stage-7 HTTP routing baseline:

- PR `#6`
- merge `d4ee733fe9df48d7a47f28711ca02f6183c1e3d0`
- tag `http-routing-baseline-d4ee733`

Subsequent D6 and D7 qualification re-proved that the hostname resolved to the
same production EIP. Therefore the lack of a dedicated D5 source PR is not an
evidence gap and does not represent unfinished implementation.

---

## 8. D6 hostname routing evidence

D6 qualified the already-governed Nginx HTTP routing contract through the
DuckDNS production hostname.

Governed source:

- PR `#6`
- head `775333356794ca448647ece2f72f62ec86720f23`
- merge `d4ee733fe9df48d7a47f28711ca02f6183c1e3d0`
- baseline `http-routing-baseline-d4ee733`

Operational qualification established that:

- the hostname resolved to `98.88.168.236`;
- the storefront remained reachable;
- auth, catalog and orders health routes reached their intended services;
- the catalog remained the exact five-product contract;
- unauthenticated orders remained HTTP `401`;
- HTTPS was intentionally absent until D7;
- the Stage-7 source/tag baseline remained unchanged.

D6 therefore closes as runtime routing qualification against already-governed
source rather than as another source merge.

---

## 9. D7 HTTPS/TLS governance evidence

- PR: `#7`
- qualified head:
  `37e35725b89bac545a994b0512e47c33071f06d2`
- governed merge:
  `cbf8a24e78abea6f74f9a3fe380e706a1eaea05e`
- annotated baseline:
  `https-tls-baseline-cbf8a24`
- tag object:
  `316f996d4d580555e3019080bf1d05500b5f5fc4`

PR #7 contains:

- line-ending hardening;
- the source-controlled HTTPS contract;
- Nginx listener-convergence remediation.

Governed source files include:

- `docs/tls-explained.md`
- `nginx/meridian-acme.conf`
- `nginx/meridian-https.conf`
- `ops/routing/install-nginx-d7.sh`
- `ops/routing/reload-nginx-after-renewal.sh`
- `ops/validation/Invoke-MeridianD7SourceGate.ps1`

Production qualification included ACME HTTP-01 validation, certificate
issuance, HTTPS activation, canonical redirect behavior and renewal
qualification.

---

## 10. D8 PostgreSQL least-privilege evidence

- PR: `#8`
- qualified head:
  `1bac4a9c5c1ae264925027d6c5fa51a20f108e86`
- governed merge:
  `81f2409674ab8188ad50df98a7d342436b53c49c`
- annotated baseline:
  `postgres-least-privilege-baseline-81f2409`
- tag object:
  `1d0234b7c3cce0d654b1ed60c089e04becb2a5c6`

PR #8 contains seven changed files, including:

- `ops/database/apply-d8-least-privilege.sh`
- `ops/database/apply-d8-rollback.sh`
- `ops/database/bootstrap-d8-least-privilege.sql`
- `ops/database/rollback-d8-least-privilege.sql`
- `ops/validation/Invoke-MeridianD8SourceGate.ps1`
- governed production environment/schema changes

The application roles are:

- `meridian_auth_app`
- `meridian_catalog_app`
- `meridian_orders_app`

The governed schemas are:

- `auth`
- `catalog`
- `orders`

---

## 11. D9 backup/restore governance and recovery evidence

- PR: `#9`
- original implementation commit:
  `16d0f5fa77bdee1d59eb6cf67f78a967e4f51ff8`
- final hardened head:
  `d6a90572e9eb0d16867a5f77095410e7f2c6f68c`
- governed merge:
  `0a825def4fb507bd3b6bf215571386acbb34df92`
- annotated baseline:
  `postgres-backup-restore-baseline-0a825de`
- tag object:
  `3bbcfaaf650fdfd6665acbea08f40f9b34d40071`

PR #9 contains eight governed files:

- `docs/backup-strategy.md`
- `ops/systemd/install-d9-backup-systemd.sh`
- `ops/systemd/meridian-db-backup.service`
- `ops/systemd/meridian-db-backup.timer`
- `ops/validation/Invoke-MeridianD9AutomationGate.ps1`
- `ops/validation/Invoke-MeridianD9SourceGate.ps1`
- `scripts/backup_db.sh`
- `scripts/restore_db.sh`

Recovery acceptance proved that:

- backup integrity was qualified using SHA-256;
- restore occurred against an isolated scratch database;
- a controlled deleted row reappeared after restoring the qualified backup;
- the live production database was not used as the destructive test target;
- the scratch database was removed after acceptance;
- the daily systemd backup timer was installed and qualified.

---

## 12. D10 production CI/CD governance evidence

- PR: `#10`
- original implementation:
  `804f3a8ff9da4dea801e52703c08e3d42f8c7b7b`
- final reviewed head:
  `53e016d03245655d4f5f7a43fd408a91fd9cede6`
- governed production merge:
  `7d608b128f5404eb4a80d0b318bd3e616a730f7c`
- production workflow run:
  `35412599053`
- workflow attempt:
  `1`
- workflow result:
  `success`
- annotated baseline:
  `production-ci-cd-baseline-7d608b1`
- tag object:
  `9e28d7275157946ec070853f0a662b6683f56c78`

PR #10 contains six governed files:

- `.github/workflows/deploy.yml`
- `README.md`
- `docs/ci-cd.md`
- `ops/deployment/github-actions-production-deploy.sh`
- `ops/ssh/known_hosts.production`
- `ops/validation/Invoke-MeridianD10SourceGate.ps1`

The accepted production workflow identity is:

| Field | Value |
| --- | --- |
| Run ID | `35412599053` |
| Workflow ID | `361794473` |
| Head SHA | `7d608b128f5404eb4a80d0b318bd3e616a730f7c` |
| Branch | `main` |
| Event | `push` |
| Attempt | `1` |
| Status | `completed` |
| Conclusion | `success` |
| Created | `2026-09-19T01:25:19Z` |
| Updated | `2026-09-19T01:27:47Z` |

The workflow log qualified the exact release SHA, the production Compose drift
interlock and successful production deployment.

---

## 13. Immutable D10 application image evidence

The D10 release produced one immutable image in each application ECR
repository under the exact production release SHA.

| Repository | Qualified digest |
| --- | --- |
| `meridian/auth` | `sha256:0ef9d27c1ff12324f5b1409ee74aea06ad8d909757c74b5bc26e6c9fbd7aab70` |
| `meridian/catalog` | `sha256:f9c8e64b5297bf251abd4a042870ca4e2cf5e0b4856dafa33798ed9f93e4bb65` |
| `meridian/orders` | `sha256:ff2c425c321968ebc8b63641a1c2d811d62b35fded536173f093dedffbb2ef34` |
| `meridian/frontend` | `sha256:53f193c394ec137c0b476b70298a15a61c6980ebcebcd74087947661327ea85b` |

All four repositories were qualified as immutable, scan-on-push enabled and
AES-256 encrypted during final production acceptance.

---

## 14. Final runtime acceptance evidence

Final D10 production acceptance established that:

- the exact captured workflow run completed successfully;
- all four application release images existed in immutable ECR;
- the temporary GitHub runner SSH ingress rule was removed after deployment;
- source and live production Compose hashes matched;
- all five production containers were healthy;
- auth, catalog, orders and frontend ran the exact D10 release SHA;
- PostgreSQL remained pinned to its governed digest;
- auth, catalog, orders and frontend endpoint checks passed;
- the production environment file remained protected and its contents were not
  exposed during evidence collection.

This final acceptance carries forward and consolidates the production runtime
evidence created throughout D1-D9.

---

## 15. Evidence handling and portfolio safety

Portfolio artifacts must never contain:

- SSH private-key material;
- GitHub secret values;
- database passwords;
- JWT secrets;
- DuckDNS tokens;
- AWS secret access keys;
- production `.env` contents;
- transient GitHub runner IP addresses.

Permitted portfolio evidence includes:

- commit IDs;
- PR numbers;
- annotated tag names and object identities;
- non-secret architecture;
- source file paths;
- sanitized workflow metadata;
- immutable image digests;
- non-secret runtime validation results.

---

## 16. Closure conclusion

The traceability audit found no unimplemented D1-D10 requirement.

The evidence model is:

`requirement -> source/operational evidence -> governed merge or qualification -> baseline -> production acceptance`

Final closure state:

`D1_D10_IMPLEMENTATION=COMPLETE`

`D1_D10_TRACEABILITY=QUALIFIED`

`PRODUCTION_BASELINE=FROZEN`

`C3_EVIDENCE_INDEX=EXACT_TRACEABILITY`
