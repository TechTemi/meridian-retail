#!/usr/bin/env bash

set -Eeuo pipefail

SOURCE_CONFIG="${1:?Usage: install-nginx-routing.sh SOURCE_CONFIG}"

AVAILABLE="/etc/nginx/sites-available/meridian"
ENABLED="/etc/nginx/sites-enabled/meridian"
DEFAULT_ENABLED="/etc/nginx/sites-enabled/default"

ROLLBACK_ROOT="/var/lib/meridian/nginx-rollback"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
ROLLBACK_DIR="${ROLLBACK_ROOT}/${RUN_ID}"


fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}


test "$(id -u)" = "0" \
    || fail "Run as root."

test -f "${SOURCE_CONFIG}" \
    || fail "Source Nginx configuration does not exist."

command -v nginx >/dev/null 2>&1 \
    || fail "nginx is unavailable."

command -v systemctl >/dev/null 2>&1 \
    || fail "systemctl is unavailable."

systemctl is-active --quiet nginx \
    || fail "nginx is not active before routing installation."


mkdir -p "${ROLLBACK_DIR}"


had_available=0
had_enabled=0
had_default=0


if [ -e "${AVAILABLE}" ]; then

    had_available=1

    cp -a \
        "${AVAILABLE}" \
        "${ROLLBACK_DIR}/meridian.available"
fi


if [ -e "${ENABLED}" ] || [ -L "${ENABLED}" ]; then

    had_enabled=1

    cp -a \
        --no-dereference \
        "${ENABLED}" \
        "${ROLLBACK_DIR}/meridian.enabled"
fi


if [ -e "${DEFAULT_ENABLED}" ] || [ -L "${DEFAULT_ENABLED}" ]; then

    had_default=1

    cp -a \
        --no-dereference \
        "${DEFAULT_ENABLED}" \
        "${ROLLBACK_DIR}/default.enabled"
fi


rollback() {

    printf 'ROLLBACK: restoring previous Nginx site state.\n' >&2

    rm -f "${ENABLED}"
    rm -f "${AVAILABLE}"


    if [ "${had_available}" = "1" ]; then

        cp -a \
            "${ROLLBACK_DIR}/meridian.available" \
            "${AVAILABLE}"
    fi


    if [ "${had_enabled}" = "1" ]; then

        cp -a \
            --no-dereference \
            "${ROLLBACK_DIR}/meridian.enabled" \
            "${ENABLED}"
    fi


    rm -f "${DEFAULT_ENABLED}"


    if [ "${had_default}" = "1" ]; then

        cp -a \
            --no-dereference \
            "${ROLLBACK_DIR}/default.enabled" \
            "${DEFAULT_ENABLED}"
    fi


    nginx -t >/dev/null 2>&1 \
        || {
            printf 'CRITICAL: restored Nginx configuration is invalid.\n' >&2
            return 1
        }


    systemctl reload nginx \
        || {
            printf 'CRITICAL: rollback reload failed.\n' >&2
            return 1
        }


    printf 'ROLLBACK=PASS\n' >&2
}


rollback_required=1


cleanup() {

    rc=$?

    if [ "${rc}" -ne 0 ] && [ "${rollback_required}" = "1" ]; then
        rollback || true
    fi

    exit "${rc}"
}


trap cleanup EXIT


install \
    -o root \
    -g root \
    -m 0644 \
    "${SOURCE_CONFIG}" \
    "${AVAILABLE}"


ln -sfn \
    "${AVAILABLE}" \
    "${ENABLED}"


rm -f "${DEFAULT_ENABLED}"


nginx -t


systemctl reload nginx


systemctl is-active --quiet nginx \
    || fail "nginx is not active after reload."


test -L "${ENABLED}" \
    || fail "Meridian enabled-site symlink is missing."


test "$(
    readlink -f "${ENABLED}"
)" = "${AVAILABLE}" \
    || fail "Meridian enabled-site symlink target is incorrect."


test ! -e "${DEFAULT_ENABLED}" \
    || fail "Ubuntu default Nginx site remains enabled."


rollback_required=0

trap - EXIT


printf 'MERIDIAN_NGINX_INSTALL=SUCCESS\n'
printf 'ROLLBACK_EVIDENCE=%s\n' "${ROLLBACK_DIR}"
