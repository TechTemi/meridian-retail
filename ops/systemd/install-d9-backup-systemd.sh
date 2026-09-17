#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

if [[ "${EUID}" -ne 0 ]]; then
    fail "installer must run as root"
fi

REPO_ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/../.."
    pwd
)"

BACKUP_SOURCE="${REPO_ROOT}/scripts/backup_db.sh"
SERVICE_SOURCE="${REPO_ROOT}/ops/systemd/meridian-db-backup.service"
TIMER_SOURCE="${REPO_ROOT}/ops/systemd/meridian-db-backup.timer"

PRODUCTION_APP="/opt/meridian/app"
PRODUCTION_SCRIPT_DIR="${PRODUCTION_APP}/scripts"
PRODUCTION_BACKUP_SCRIPT="${PRODUCTION_SCRIPT_DIR}/backup_db.sh"
PRODUCTION_BACKUP_DIR="/opt/meridian/backups/d9"

SERVICE_TARGET="/etc/systemd/system/meridian-db-backup.service"
TIMER_TARGET="/etc/systemd/system/meridian-db-backup.timer"

for command_name in install systemctl stat id getent; do
    command -v "${command_name}" >/dev/null 2>&1 ||
        fail "required command absent: ${command_name}"
done

id ubuntu >/dev/null 2>&1 ||
    fail "required service account absent: ubuntu"

primary_group="$(id -gn ubuntu)"

[[ "${primary_group}" == "ubuntu" ]] ||
    fail "ubuntu primary group is not ubuntu: ${primary_group}"

getent group docker >/dev/null 2>&1 ||
    fail "required docker group absent"

for source_path in \
    "${BACKUP_SOURCE}" \
    "${SERVICE_SOURCE}" \
    "${TIMER_SOURCE}"
do
    [[ -f "${source_path}" ]] ||
        fail "required source artifact absent: ${source_path}"
done

[[ -d "${PRODUCTION_APP}" ]] ||
    fail "production application root absent: ${PRODUCTION_APP}"

[[ -d "${PRODUCTION_BACKUP_DIR}" ]] ||
    fail "qualified production backup directory absent: ${PRODUCTION_BACKUP_DIR}"

backup_owner="$(stat -c '%U' "${PRODUCTION_BACKUP_DIR}")"
backup_group="$(stat -c '%G' "${PRODUCTION_BACKUP_DIR}")"
backup_mode="$(stat -c '%a' "${PRODUCTION_BACKUP_DIR}")"

[[ "${backup_owner}" == "ubuntu" ]] ||
    fail "production backup directory owner is not ubuntu"

[[ "${backup_group}" == "docker" ]] ||
    fail "production backup directory group is not docker"

case "${backup_mode}" in
    700|2700)
        ;;
    *)
        fail "production backup directory mode is not restrictive: ${backup_mode}"
        ;;
esac

[[ ! -e "${PRODUCTION_BACKUP_SCRIPT}" ]] ||
    fail "production backup script target already exists: ${PRODUCTION_BACKUP_SCRIPT}"

[[ ! -e "${SERVICE_TARGET}" ]] ||
    fail "service target already exists: ${SERVICE_TARGET}"

[[ ! -e "${TIMER_TARGET}" ]] ||
    fail "timer target already exists: ${TIMER_TARGET}"

install \
    -d \
    -m 2775 \
    -o root \
    -g docker \
    "${PRODUCTION_SCRIPT_DIR}"

install \
    -m 0755 \
    -o root \
    -g docker \
    "${BACKUP_SOURCE}" \
    "${PRODUCTION_BACKUP_SCRIPT}"

install \
    -m 0644 \
    -o root \
    -g root \
    "${SERVICE_SOURCE}" \
    "${SERVICE_TARGET}"

install \
    -m 0644 \
    -o root \
    -g root \
    "${TIMER_SOURCE}" \
    "${TIMER_TARGET}"

systemctl daemon-reload
systemctl enable meridian-db-backup.timer

systemctl is-enabled --quiet meridian-db-backup.timer ||
    fail "Meridian backup timer was not enabled"

printf '\n'
printf '%s\n' 'D9 DAILY BACKUP AUTOMATION INSTALLATION PASS'
printf 'PRODUCTION_BACKUP_SCRIPT=%s\n' "${PRODUCTION_BACKUP_SCRIPT}"
printf 'PRODUCTION_BACKUP_DIR=%s\n' "${PRODUCTION_BACKUP_DIR}"
printf 'SERVICE_UNIT=%s\n' "${SERVICE_TARGET}"
printf 'TIMER_UNIT=%s\n' "${TIMER_TARGET}"
printf 'TIMER_ENABLED=YES\n'
printf 'TIMER_STARTED=NO\n'
printf 'BACKUP_EXECUTED=NO\n'
