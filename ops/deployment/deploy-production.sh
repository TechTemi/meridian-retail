#!/usr/bin/env bash

set -Eeuo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
MERIDIAN_ROOT="${MERIDIAN_ROOT:-/opt/meridian}"
COMPOSE_FILE="${MERIDIAN_ROOT}/app/docker-compose.production.yml"
ENV_FILE="${MERIDIAN_ROOT}/config/.env.production"

usage() {
    printf 'Usage: %s <immutable-image-tag>\n' "$0" >&2
    exit 64
}

if [[ $# -ne 1 ]]; then
    usage
fi

IMAGE_TAG="$1"

if [[ ! "${IMAGE_TAG}" =~ ^[0-9a-f]{7,40}$ ]]; then
    printf 'ERROR: image tag must be a Git commit SHA.\n' >&2
    exit 65
fi

if [[ ! -f "${COMPOSE_FILE}" ]]; then
    printf 'ERROR: production Compose file is missing.\n' >&2
    exit 66
fi

if [[ ! -f "${ENV_FILE}" ]]; then
    printf 'ERROR: production environment file is missing.\n' >&2
    exit 67
fi

for command in aws docker curl ss; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        printf 'ERROR: required command is unavailable: %s\n' "${command}" >&2
        exit 68
    fi
done

ACCOUNT_ID="$(
    aws sts get-caller-identity \
        --region "${AWS_REGION}" \
        --query Account \
        --output text
)"

if [[ ! "${ACCOUNT_ID}" =~ ^[0-9]{12}$ ]]; then
    printf 'ERROR: unable to resolve AWS account identity.\n' >&2
    exit 69
fi

ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

export AWS_REGION
export ECR_REGISTRY
export IMAGE_TAG

aws ecr get-login-password \
    --region "${AWS_REGION}" |
docker login \
    --username AWS \
    --password-stdin \
    "${ECR_REGISTRY}" \
    >/dev/null

docker compose \
    --env-file "${ENV_FILE}" \
    -f "${COMPOSE_FILE}" \
    config \
    --quiet

docker compose \
    --env-file "${ENV_FILE}" \
    -f "${COMPOSE_FILE}" \
    pull

docker compose \
    --env-file "${ENV_FILE}" \
    -f "${COMPOSE_FILE}" \
    up \
    -d \
    --remove-orphans \
    --wait \
    --wait-timeout 180

EXPECTED_SERVICES=(
    postgres
    auth-service
    catalog-service
    orders-service
    frontend
)

for service in "${EXPECTED_SERVICES[@]}"; do

    CONTAINER_ID="$(
        docker compose \
            --env-file "${ENV_FILE}" \
            -f "${COMPOSE_FILE}" \
            ps \
            -q \
            "${service}"
    )"

    if [[ -z "${CONTAINER_ID}" ]]; then
        printf 'ERROR: service container missing: %s\n' "${service}" >&2
        exit 70
    fi

    STATUS="$(
        docker inspect \
            --format '{{.State.Status}}' \
            "${CONTAINER_ID}"
    )"

    if [[ "${STATUS}" != "running" ]]; then
        printf 'ERROR: service is not running: %s\n' "${service}" >&2
        exit 71
    fi
done

curl -fsS http://127.0.0.1:8001/healthz >/dev/null
curl -fsS http://127.0.0.1:8002/healthz >/dev/null
curl -fsS http://127.0.0.1:8003/healthz >/dev/null
curl -fsS http://127.0.0.1:8080/ >/dev/null

if ss -ltnH |
    awk '{print $4}' |
    grep -Eq '(^|:)5432$'; then

    printf 'ERROR: PostgreSQL is unexpectedly published on the host.\n' >&2
    exit 72
fi

printf 'MERIDIAN_PRODUCTION_DEPLOYMENT=SUCCESS\n'
