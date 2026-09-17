#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-meridian-retail-postgres-1}"
RESTORE_TARGET_DB="${RESTORE_TARGET_DB:-meridian_d9_restore}"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat >&2 <<'USAGE'
Usage:
  restore_db.sh BACKUP_FILE [TARGET_DATABASE]

Default target:
  meridian_d9_restore

Safety:
  - restoring over the live source database is always refused
  - restore targets must begin with meridian_d9_

USAGE
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        fail "required command not found: $1"
}

require_command docker
require_command sha256sum

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    usage
    exit 64
fi

BACKUP_FILE="$1"
TARGET_DB="${2:-${RESTORE_TARGET_DB}}"

[ -f "${BACKUP_FILE}" ] ||
    fail "backup file not found: ${BACKUP_FILE}"

[ -s "${BACKUP_FILE}" ] ||
    fail "backup file is empty: ${BACKUP_FILE}"

case "${TARGET_DB}" in
    ''|*[!A-Za-z0-9_]*)
        fail "invalid target database name: ${TARGET_DB}"
        ;;
esac

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

SOURCE_DB="$(
    docker exec \
        "${POSTGRES_CONTAINER}" \
        sh -ceu '
            : "${POSTGRES_DB:?POSTGRES_DB is required}"
            printf "%s" "${POSTGRES_DB}"
        '
)"

[ -n "${SOURCE_DB}" ] ||
    fail "unable to determine source database"

if [ "${TARGET_DB}" = "${SOURCE_DB}" ]; then
    fail "refusing to restore over live source database ${SOURCE_DB}"
fi

case "${TARGET_DB}" in
    meridian_d9_*)
        ;;
    *)
        fail "restore target must begin with meridian_d9_"
        ;;
esac

backup_dir="$(cd "$(dirname "${BACKUP_FILE}")" && pwd)"
backup_name="$(basename "${BACKUP_FILE}")"
checksum_file="${backup_dir}/${backup_name}.sha256"

[ -f "${checksum_file}" ] ||
    fail "checksum sidecar not found: ${checksum_file}"

printf 'Validating backup checksum\n'

(
    cd "${backup_dir}"
    sha256sum -c "$(basename "${checksum_file}")"
) ||
    fail "backup checksum validation failed"

printf 'Validating PostgreSQL archive\n'

docker exec \
    -i \
    "${POSTGRES_CONTAINER}" \
    pg_restore --list \
    < "${BACKUP_FILE}" \
    >/dev/null ||
    fail "backup archive is not readable by pg_restore"

printf 'Preparing isolated restore database\n'
printf '  source : %s\n' "${SOURCE_DB}"
printf '  target : %s\n' "${TARGET_DB}"

cleanup_target() {
    docker exec \
        -e TARGET_DB="${TARGET_DB}" \
        "${POSTGRES_CONTAINER}" \
        sh -ceu '
            : "${POSTGRES_USER:?POSTGRES_USER is required}"
            : "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
            : "${TARGET_DB:?TARGET_DB is required}"

            export PGPASSWORD="${POSTGRES_PASSWORD}"

            exec dropdb \
                --host=127.0.0.1 \
                --port=5432 \
                --username="${POSTGRES_USER}" \
                --if-exists \
                --force \
                "${TARGET_DB}"
        ' || true
}

if ! docker exec \
        -e TARGET_DB="${TARGET_DB}" \
        "${POSTGRES_CONTAINER}" \
        sh -ceu '
            : "${POSTGRES_USER:?POSTGRES_USER is required}"
            : "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
            : "${TARGET_DB:?TARGET_DB is required}"

            export PGPASSWORD="${POSTGRES_PASSWORD}"

            dropdb \
                --host=127.0.0.1 \
                --port=5432 \
                --username="${POSTGRES_USER}" \
                --if-exists \
                --force \
                "${TARGET_DB}"

            exec createdb \
                --host=127.0.0.1 \
                --port=5432 \
                --username="${POSTGRES_USER}" \
                --owner="${POSTGRES_USER}" \
                "${TARGET_DB}"
        '
then
    printf 'Restore preparation failed; removing incomplete D9 target\n' >&2
    cleanup_target
    fail "unable to prepare isolated D9 restore database"
fi

printf 'Restoring PostgreSQL archive\n'

if ! docker exec \
        -i \
        -e TARGET_DB="${TARGET_DB}" \
        "${POSTGRES_CONTAINER}" \
        sh -ceu '
            : "${POSTGRES_USER:?POSTGRES_USER is required}"
            : "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
            : "${TARGET_DB:?TARGET_DB is required}"

            export PGPASSWORD="${POSTGRES_PASSWORD}"

            exec pg_restore \
                --host=127.0.0.1 \
                --port=5432 \
                --username="${POSTGRES_USER}" \
                --dbname="${TARGET_DB}" \
                --exit-on-error
        ' < "${BACKUP_FILE}"
then
    printf 'Restore failed; removing incomplete D9 target\n' >&2
    cleanup_target
    fail "pg_restore failed"
fi

printf 'Validating restored D8 schema contract\n'

if ! d8_structure="$(
    printf '%s\n' \
        "SELECT" \
        "    to_regclass('auth.users') IS NOT NULL" \
        "    AND to_regclass('catalog.products') IS NOT NULL" \
        "    AND to_regclass('orders.orders') IS NOT NULL" \
        "    AND to_regclass('public.users') IS NULL" \
        "    AND to_regclass('public.products') IS NULL" \
        "    AND to_regclass('public.orders') IS NULL;" |
        docker exec \
            -i \
            -e TARGET_DB="${TARGET_DB}" \
            "${POSTGRES_CONTAINER}" \
            sh -ceu '
                : "${POSTGRES_USER:?POSTGRES_USER is required}"
                : "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
                : "${TARGET_DB:?TARGET_DB is required}"

                export PGPASSWORD="${POSTGRES_PASSWORD}"

                exec psql \
                    --host=127.0.0.1 \
                    --port=5432 \
                    --username="${POSTGRES_USER}" \
                    --dbname="${TARGET_DB}" \
                    --tuples-only \
                    --no-align
            '
)"
then
    printf 'Restore validation failed; removing incomplete D9 target\n' >&2
    cleanup_target
    fail "restored database D8 schema validation command failed"
fi

d8_structure="$(
    printf '%s' "${d8_structure}" |
        tr -d '[:space:]'
)"

if [ "${d8_structure}" != "t" ]; then
    printf 'Restore validation failed; removing incomplete D9 target\n' >&2
    cleanup_target
    fail "restored database does not satisfy D8 schema contract"
fi

printf '\n'
printf 'RESTORE PASS\n'
printf 'Backup          : %s\n' "${BACKUP_FILE}"
printf 'Source database : %s\n' "${SOURCE_DB}"
printf 'Target database : %s\n' "${TARGET_DB}"
printf 'D8 structure    : PASS\n'
