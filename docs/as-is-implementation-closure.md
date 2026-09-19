# Meridian Retail — As-Is Implementation Closure

## 1. Closure status

The Meridian Retail as-is implementation is complete. The implementation scope
is D1 through D10. No D11 engineering capability is part of this closure.

| Field | Frozen value |
| --- | --- |
| Repository | `TechTemi/meridian-retail` |
| Production release SHA | `7d608b128f5404eb4a80d0b318bd3e616a730f7c` |
| Production release tree | `dd75ec920998670ffc7754b13b188f6f42dfda11` |
| Production workflow run | `35412599053` |
| Workflow attempt | `1` |
| Workflow result | `success` |
| Production baseline tag | `production-ci-cd-baseline-7d608b1` |
| Production hostname | `meridian-retail-temi.duckdns.org` |
| Final implementation state | `D1-D10 COMPLETE` |

## 2. D1-D10 completion matrix

| Deliverable | Implemented capability | Final status |
| --- | --- | --- |
| D1 | Terraform-provisioned custom VPC and EC2 production infrastructure | Complete |
| D2 | Restricted SSH access through security-group IP whitelisting | Complete |
| D3 | Immutable ECR repositories for auth, catalog, orders and frontend | Complete |
| D4 | Least-privilege IAM identity attached to the production EC2 runtime | Complete |
| D5 | DuckDNS production hostname mapped to the production Elastic IP | Complete |
| D6 | Nginx routing qualified through the production hostname | Complete |
| D7 | Governed HTTPS/TLS with certificate renewal qualification | Complete and frozen |
| D8 | PostgreSQL runtime secured with least-privilege application identities | Complete and frozen |
| D9 | Automated PostgreSQL backup plus isolated restore/recovery acceptance | Complete and frozen |
| D10 | GitHub Actions production CI/CD with immutable release identity | Complete and frozen |

## 3. Final architecture

Production path:

`Internet -> DuckDNS hostname -> Elastic IP -> EC2 -> Nginx -> application services`

The runtime contains frontend, auth, catalog, orders and PostgreSQL. Terraform
manages AWS infrastructure. Four application images are stored in immutable
Amazon ECR repositories. GitHub Actions deploys the production release after a
controlled merge to `main`.

## 4. Production release model

The production workflow uses GitHub Actions `GITHUB_SHA` as the release
identity. For the frozen release:

`GITHUB_SHA = 7d608b128f5404eb4a80d0b318bd3e616a730f7c`

The same full SHA identifies the four deployed application image tags. The
accepted workflow is run `35412599053`, attempt `1`, conclusion `success`.

## 5. CI/CD security controls

- GitHub OIDC federation instead of long-lived AWS access keys.
- Least-privilege deployment permissions.
- Immutable ECR repositories.
- Full Git SHA image tags.
- Pinned GitHub Action revisions.
- Pinned production SSH host identity.
- Temporary runner SSH ingress with cleanup.
- Source/live production Compose drift checking.
- Fail-closed deployment behavior.
- Exact release-SHA reconciliation after merge.
- No automatic rollback that could hide a failed release.

## 6. Database and recovery controls

- application-specific least-privilege runtime identities;
- no host-published PostgreSQL port;
- controlled backup generation;
- SHA-256 backup integrity evidence;
- isolated restore validation;
- recovery testing without modifying the live source database;
- daily systemd backup timer;
- preserved backup evidence.

## 7. TLS and routing controls

Production hostname: `meridian-retail-temi.duckdns.org`

The implementation includes Nginx routing, HTTPS/TLS, ACME HTTP-01 validation,
a Certbot deploy hook and successful renewal dry-run qualification.

## 8. Frozen governance baselines

| Stage | Governed baseline |
| --- | --- |
| D7 | `https-tls-baseline-cbf8a24` |
| D8 | `postgres-least-privilege-baseline-81f2409` |
| D9 | `postgres-backup-restore-baseline-0a825de` |
| D10 | `production-ci-cd-baseline-7d608b1` |

## 9. Main-branch safety boundary

The D10 deployment workflow triggers from pushes to `main` and has no
documentation path exclusion at closure time. Documentation-only changes must
therefore not be casually merged into `main`, because doing so can create a new
production release.

## 10. Final disposition

`AS_IS_IMPLEMENTATION=D1_THROUGH_D10_COMPLETE`

`PRODUCTION_BASELINE=FROZEN`

`NEW_ENGINEERING_SCOPE=NONE`

`PROJECT_PHASE=PORTFOLIO_CLOSURE`
