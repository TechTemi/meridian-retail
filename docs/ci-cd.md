# Meridian Production CI/CD

## Purpose

D10 introduces the source-controlled production delivery path for Meridian Retail.

A push to `main` causes `.github/workflows/deploy.yml` to build the four application images, authenticate to AWS through GitHub OIDC, publish immutable images to Amazon ECR, temporarily authorize SSH from the current GitHub-hosted runner, and execute the qualified production deployment entry point on the EC2 host.

## Release identity

The release identity is the full 40-character Git commit SHA supplied by `github.sha`.

The four repositories are `meridian/auth`, `meridian/catalog`, `meridian/orders`, and `meridian/frontend`.

No mutable production `latest` tag is used.

All four images are built before publication begins.

ECR does not provide a transaction spanning four independent repositories. D10 therefore uses a fail-closed release-set contract:

- if no repository contains the SHA, all four images are published;
- if all four already contain the SHA, each immutable ECR manifest must match the corresponding image built from the current source;
- if only a partial SHA set exists, deployment stops for controlled investigation;
- production SSH is not opened until all four immutable images qualify.

The deployment role uses its already-qualified `ecr:BatchGetImage` permission for release-image inspection. D10 does not require `ecr:DescribeImages`.

## AWS authentication

GitHub Actions uses OIDC and the existing production deployment role.

Long-lived AWS access keys are not stored in GitHub.

The trust remains restricted to the immutable Meridian repository identity on `refs/heads/main`.

## Production secrets

Database credentials and the JWT secret remain host-resident at:

`/opt/meridian/config/.env.production`

They are not copied into GitHub.

The D10 GitHub repository secret is:

`EC2_SSH_PRIVATE_KEY`

It contains only the production EC2 SSH client private key.

## SSH trust and temporary ingress

The qualified ED25519 production host key is stored in:

`ops/ssh/known_hosts.production`

Strict host-key checking is mandatory. Dynamic `ssh-keyscan` is forbidden.

The GitHub runner IPv4 is validated and converted to an exact temporary `/32` TCP/22 rule.

The workflow refuses to claim ownership if that `/32` already has TCP/22 access.

The deployment role uses its already-qualified `ec2:DescribeSecurityGroups` permission for ingress inspection. D10 does not require `ec2:DescribeSecurityGroupRules`.

The exact security-group rule ID returned by the current authorization call is persisted with its runner CIDR and workflow-owned description.

Only that workflow-owned temporary rule is eligible for revocation.

Both the deployment helper and the workflow `always()` cleanup step enforce cleanup.

## Deployment-script transport

`ops/deployment/deploy-production.sh` remains the production deployment entry point.

The workflow does not assume it is persistently installed on the EC2 host.

The exact source-controlled script is copied to a unique `/tmp` path for the current workflow run.

Its local and remote SHA-256 values must match before execution.

The temporary remote script is removed after the deployment attempt.

## Production runtime boundary

Production continues to use:

- `/opt/meridian/app/docker-compose.production.yml`
- `/opt/meridian/config/.env.production`
- the existing canonical PostgreSQL data volume.

D10 does not place PostgreSQL credentials in GitHub and does not publish PostgreSQL on the host.

## Failure behavior

D10 initially provides no automatic rollback.

A failed build, partial SHA set, image mismatch, runner-IP validation failure, temporary-ingress failure, pinned-host SSH failure, transported-script integrity failure, deployment failure, or missing production-success marker fails closed.

Previously published immutable release tags remain available for a separately governed rollback operation.

## Activation boundary

The workflow must not be merged to `main` until the required repository secret has been deliberately configured and D10 pre-deployment qualification has passed.

Creating these D10 source artifacts does not itself mutate AWS, the EC2 security group, or the running production application.
