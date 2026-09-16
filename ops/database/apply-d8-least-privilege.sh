#!/usr/bin/env bash

set -Eeuo pipefail

MERIDIAN_ROOT="${MERIDIAN_ROOT:-/opt/meridian}"
ENV_FILE="${MERIDIAN_ROOT}/config/.env.production"
SQL_FILE="${MERIDIAN_ROOT}/app/ops/database/bootstrap-d8-least-privilege.sql"
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-meridian-retail-postgres-1}"


fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}


[[ -f "${ENV_FILE}" ]] \
    || fail "production environment file is missing"

[[ -f "${SQL_FILE}" ]] \
    || fail "D8 least-privilege SQL file is missing"


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
AUTH_DB_PASSWORD="$(read_env_key AUTH_DB_PASSWORD)"

CATALOG_DB_USER="$(read_env_key CATALOG_DB_USER)"
CATALOG_DB_PASSWORD="$(read_env_key CATALOG_DB_PASSWORD)"

ORDERS_DB_USER="$(read_env_key ORDERS_DB_USER)"
ORDERS_DB_PASSWORD="$(read_env_key ORDERS_DB_PASSWORD)"


for value in \
    "${DB_NAME}" \
    "${DB_ADMIN_USER}" \
    "${AUTH_DB_USER}" \
    "${AUTH_DB_PASSWORD}" \
    "${CATALOG_DB_USER}" \
    "${CATALOG_DB_PASSWORD}" \
    "${ORDERS_DB_USER}" \
    "${ORDERS_DB_PASSWORD}"
do
    [[ -n "${value}" ]] \
        || fail "required D8 database value is empty"
done


[[ "${AUTH_DB_USER}" != "${DB_ADMIN_USER}" ]] \
    || fail "auth runtime role equals admin role"

[[ "${CATALOG_DB_USER}" != "${DB_ADMIN_USER}" ]] \
    || fail "catalog runtime role equals admin role"

[[ "${ORDERS_DB_USER}" != "${DB_ADMIN_USER}" ]] \
    || fail "orders runtime role equals admin role"

[[ "${AUTH_DB_USER}" != "${CATALOG_DB_USER}" ]] \
    || fail "auth and catalog runtime roles collide"

[[ "${AUTH_DB_USER}" != "${ORDERS_DB_USER}" ]] \
    || fail "auth and orders runtime roles collide"

[[ "${CATALOG_DB_USER}" != "${ORDERS_DB_USER}" ]] \
    || fail "catalog and orders runtime roles collide"


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
    -e AUTH_DB_PASSWORD="${AUTH_DB_PASSWORD}" \
    -e CATALOG_DB_USER="${CATALOG_DB_USER}" \
    -e CATALOG_DB_PASSWORD="${CATALOG_DB_PASSWORD}" \
    -e ORDERS_DB_USER="${ORDERS_DB_USER}" \
    -e ORDERS_DB_PASSWORD="${ORDERS_DB_PASSWORD}" \
    "${POSTGRES_CONTAINER}" \
    psql \
        -X \
        -v ON_ERROR_STOP=1 \
        -U "${DB_ADMIN_USER}" \
        -d "${DB_NAME}" \
    < "${SQL_FILE}"


printf '%s\n' \
    'MERIDIAN_D8_LEAST_PRIVILEGE_BOOTSTRAP=SUCCESS'