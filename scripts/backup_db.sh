#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-meridian-retail-postgres-1}"
MERIDIAN_ROOT="${MERIDIAN_ROOT:-/opt/meridian-retail}"
BACKUP_DIR="${BACKUP_DIR:-${MERIDIAN_ROOT}/backups}"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        fail "required command not found: $1"
}

require_command docker
require_command sha256sum
require_command date

docker inspect "${POSTGRES_CONTAINER}" >/dev/null 2>&1 ||
    fail "PostgreSQL container not found: ${POSTGRES_CONTAINER}"

running="$(
    docker inspect \
        --format '{{.State.Running}}' \
        "${POSTGRES_CONTAINER}"
)"

[ "${running}" = "true" ] ||
    fail "PostgreSQL container is not running"

health="$(
    docker inspect \
        --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
        "${POSTGRES_CONTAINER}"
)"

if [ "${health}" != "none" ] && [ "${health}" != "healthy" ]; then
    fail "PostgreSQL container health is ${health}"
fi

source_db="$(
    docker exec \
        "${POSTGRES_CONTAINER}" \
        sh -ceu '
            : "${POSTGRES_DB:?POSTGRES_DB is required}"
            printf "%s" "${POSTGRES_DB}"
        '
)"

[ -n "${source_db}" ] ||
    fail "unable to determine source database"

safe_db="$(
    printf '%s' "${source_db}" |
        tr -c 'A-Za-z0-9_.-' '_'
)"

timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

backup_name="meridian-${safe_db}-${timestamp}.dump"
backup_path="${BACKUP_DIR}/${backup_name}"
temporary_path="${BACKUP_DIR}/.${backup_name}.partial"
checksum_path="${backup_path}.sha256"

cleanup() {
    rm -f "${temporary_path}"
}

trap cleanup EXIT

printf 'Creating PostgreSQL backup\n'
printf '  container : %s\n' "${POSTGRES_CONTAINER}"
printf '  database  : %s\n' "${source_db}"
printf '  artifact  : %s\n' "${backup_path}"

docker exec \
    "${POSTGRES_CONTAINER}" \
    sh -ceu '
        : "${POSTGRES_DB:?POSTGRES_DB is required}"
        : "${POSTGRES_USER:?POSTGRES_USER is required}"
        : "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"

        export PGPASSWORD="${POSTGRES_PASSWORD}"

        exec pg_dump \
            --host=127.0.0.1 \
            --port=5432 \
            --username="${POSTGRES_USER}" \
            --dbname="${POSTGRES_DB}" \
            --format=custom
    ' > "${temporary_path}"

[ -s "${temporary_path}" ] ||
    fail "backup artifact is empty"

docker exec \
    -i \
    "${POSTGRES_CONTAINER}" \
    pg_restore --list \
    < "${temporary_path}" \
    >/dev/null ||
    fail "pg_restore cannot read generated archive"

mv "${temporary_path}" "${backup_path}"

(
    cd "${BACKUP_DIR}"
    sha256sum "${backup_name}" > "${backup_name}.sha256"
)

[ -s "${checksum_path}" ] ||
    fail "checksum sidecar was not created"

trap - EXIT

printf '\n'
printf 'BACKUP PASS\n'
printf 'Backup   : %s\n' "${backup_path}"
printf 'Checksum : %s\n' "${checksum_path}"
printf 'Database : %s\n' "${source_db}"
