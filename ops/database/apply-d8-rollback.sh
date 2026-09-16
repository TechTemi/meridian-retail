#!/usr/bin/env bash

set -Eeuo pipefail

MERIDIAN_ROOT="${MERIDIAN_ROOT:-/opt/meridian}"
ENV_FILE="${MERIDIAN_ROOT}/config/.env.production"
SQL_FILE="${MERIDIAN_ROOT}/app/ops/database/rollback-d8-least-privilege.sql"

POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-meridian-retail-postgres-1}"

EXPECTED_CONFIRMATION="ROLLBACK_D8_DATABASE_TO_PUBLIC_SCHEMA"


fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}


[[ "${MERIDIAN_D8_ROLLBACK_CONFIRM:-}" == "${EXPECTED_CONFIRMATION}" ]] \
    || fail "explicit D8 rollback confirmation is required"

[[ -f "${ENV_FILE}" ]] \
    || fail "production environment file is missing"

[[ -f "${SQL_FILE}" ]] \
    || fail "D8 rollback SQL file is missing"


read_env_key() {

    local key="$1"

    awk \
        -v key="${key}" '
            index($0,key "=") == 1 {
                print substr($0,length(key)+2)
                found=1
            }

            END {
                if (!found) {
                    exit 1
                }
            }
        ' \
        "${ENV_FILE}"
}


DB_NAME="$(read_env_key DB_NAME)"
DB_ADMIN_USER="$(read_env_key DB_ADMIN_USER)"

AUTH_DB_USER="$(read_env_key AUTH_DB_USER)"
CATALOG_DB_USER="$(read_env_key CATALOG_DB_USER)"
ORDERS_DB_USER="$(read_env_key ORDERS_DB_USER)"


for value in \
    "${DB_NAME}" \
    "${DB_ADMIN_USER}" \
    "${AUTH_DB_USER}" \
    "${CATALOG_DB_USER}" \
    "${ORDERS_DB_USER}"
do
    [[ -n "${value}" ]] \
        || fail "required rollback database value is empty"
done


# ============================================================
# Application services must already be stopped.
#
# Database rollback changes name resolution from:
#   auth / catalog / orders schemas
#
# back to:
#   public
#
# Refusing active application containers prevents a mixed topology.
# ============================================================

for container in \
    meridian-retail-auth-service-1 \
    meridian-retail-catalog-service-1 \
    meridian-retail-orders-service-1
do
    if docker inspect "${container}" >/dev/null 2>&1; then

        state="$(
            docker inspect \
                -f '{{.State.Running}}' \
                "${container}"
        )"

        [[ "${state}" != "true" ]] \
            || fail "application container is still running: ${container}"
    fi
done


docker inspect \
    "${POSTGRES_CONTAINER}" \
    >/dev/null 2>&1 \
    || fail "production PostgreSQL container is absent"


[[ "$(
    docker inspect \
        -f '{{.State.Status}}' \
        "${POSTGRES_CONTAINER}"
)" == "running" ]] \
    || fail "production PostgreSQL container is not running"


[[ "$(
    docker inspect \
        -f '{{.State.Health.Status}}' \
        "${POSTGRES_CONTAINER}"
)" == "healthy" ]] \
    || fail "production PostgreSQL container is not healthy"


docker exec \
    -i \
    -e DB_NAME="${DB_NAME}" \
    -e DB_ADMIN_USER="${DB_ADMIN_USER}" \
    -e AUTH_DB_USER="${AUTH_DB_USER}" \
    -e CATALOG_DB_USER="${CATALOG_DB_USER}" \
    -e ORDERS_DB_USER="${ORDERS_DB_USER}" \
    "${POSTGRES_CONTAINER}" \
    psql \
        -X \
        -v ON_ERROR_STOP=1 \
        -U "${DB_ADMIN_USER}" \
        -d "${DB_NAME}" \
    < "${SQL_FILE}"


printf '%s\n' \
    'MERIDIAN_D8_DATABASE_ROLLBACK=SUCCESS'