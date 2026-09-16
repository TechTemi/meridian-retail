#!/usr/bin/env bash

set -Eeuo pipefail

MODE="${1:?Usage: install-nginx-d7.sh MODE SOURCE_CONFIG DEPLOY_HOOK_SOURCE}"
SOURCE_CONFIG="${2:?Usage: install-nginx-d7.sh MODE SOURCE_CONFIG DEPLOY_HOOK_SOURCE}"
DEPLOY_HOOK_SOURCE="${3:?Usage: install-nginx-d7.sh MODE SOURCE_CONFIG DEPLOY_HOOK_SOURCE}"

FQDN="meridian-retail-temi.duckdns.org"

AVAILABLE="/etc/nginx/sites-available/meridian"
ENABLED="/etc/nginx/sites-enabled/meridian"
DEFAULT_ENABLED="/etc/nginx/sites-enabled/default"

ACME_ROOT="/var/www/meridian-acme"
ACME_CHALLENGE="${ACME_ROOT}/.well-known/acme-challenge"

FULLCHAIN="/etc/letsencrypt/live/${FQDN}/fullchain.pem"
PRIVATE_KEY="/etc/letsencrypt/live/${FQDN}/privkey.pem"

DEPLOY_HOOK_TARGET="/usr/local/sbin/meridian-certbot-deploy-hook"

ROLLBACK_ROOT="/var/lib/meridian/nginx-rollback"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
ROLLBACK_DIR="${ROLLBACK_ROOT}/${RUN_ID}"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

test "$(id -u)" = "0" \
    || fail "Run as root."

case "${MODE}" in
    acme|https)
        ;;
    *)
        fail "MODE must be acme or https."
        ;;
esac

test -f "${SOURCE_CONFIG}" \
    || fail "Source Nginx configuration is missing."

test -f "${DEPLOY_HOOK_SOURCE}" \
    || fail "Source Certbot deploy hook is missing."

command -v nginx >/dev/null \
    || fail "nginx is unavailable."

command -v systemctl >/dev/null \
    || fail "systemctl is unavailable."

command -v openssl >/dev/null \
    || fail "openssl is unavailable."

command -v ss >/dev/null \
    || fail "ss is unavailable."

systemctl is-active --quiet nginx \
    || fail "nginx is not active before change."

nginx -t >/dev/null 2>&1 \
    || fail "pre-change Nginx configuration is invalid."

if [ "${MODE}" = "https" ]; then

    test -s "${FULLCHAIN}" \
        || fail "Production certificate fullchain is absent."

    test -s "${PRIVATE_KEY}" \
        || fail "Production certificate private key is absent."

    openssl x509 \
        -in "${FULLCHAIN}" \
        -checkend 0 \
        -noout >/dev/null \
        || fail "Production certificate is expired or invalid."

    openssl x509 \
        -in "${FULLCHAIN}" \
        -noout \
        -ext subjectAltName |
    grep -Fq "DNS:${FQDN}" \
        || fail "Certificate SAN does not contain production hostname."
fi


mkdir -p "${ROLLBACK_DIR}"

had_available=0
had_enabled=0
had_default=0
had_deploy_hook=0
had_acme_root=0

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

if [ -e "${DEPLOY_HOOK_TARGET}" ]; then
    had_deploy_hook=1
    cp -a \
        "${DEPLOY_HOOK_TARGET}" \
        "${ROLLBACK_DIR}/certbot-deploy-hook"
fi

if [ -d "${ACME_ROOT}" ]; then
    had_acme_root=1
fi


mutated=0

rollback() {

    printf '%s\n' \
        'ROLLBACK: restoring previous Meridian Nginx state.' >&2

    rm -f "${ENABLED}"
    rm -f "${AVAILABLE}"
    rm -f "${DEPLOY_HOOK_TARGET}"

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

    if [ "${had_default}" = "1" ]; then
        cp -a \
            --no-dereference \
            "${ROLLBACK_DIR}/default.enabled" \
            "${DEFAULT_ENABLED}"
    else
        rm -f "${DEFAULT_ENABLED}"
    fi

    if [ "${had_deploy_hook}" = "1" ]; then
        cp -a \
            "${ROLLBACK_DIR}/certbot-deploy-hook" \
            "${DEPLOY_HOOK_TARGET}"
    fi

    if [ "${had_acme_root}" = "0" ]; then
        rmdir "${ACME_CHALLENGE}" 2>/dev/null || true
        rmdir "${ACME_ROOT}/.well-known" 2>/dev/null || true
        rmdir "${ACME_ROOT}" 2>/dev/null || true
    fi

    nginx -t >/dev/null 2>&1
    systemctl reload nginx

    printf '%s\n' 'ROLLBACK=PASS'
}


on_exit() {

    rc=$?

    trap - EXIT

    if [ "${rc}" -ne 0 ] && [ "${mutated}" = "1" ]; then

        if ! rollback; then
            printf '%s\n' 'ROLLBACK=FAIL' >&2
        fi
    fi

    exit "${rc}"
}

trap on_exit EXIT


# Every filesystem mutation occurs after rollback has been armed.
mutated=1

install \
    -d \
    -m 0755 \
    "${ACME_CHALLENGE}"

install \
    -m 0755 \
    "${DEPLOY_HOOK_SOURCE}" \
    "${DEPLOY_HOOK_TARGET}"

install \
    -m 0644 \
    "${SOURCE_CONFIG}" \
    "${AVAILABLE}"

ln -sfn \
    "${AVAILABLE}" \
    "${ENABLED}"

rm -f "${DEFAULT_ENABLED}"

nginx -t

systemctl reload nginx

test "$(
    readlink -f "${ENABLED}"
)" = "${AVAILABLE}"

cmp -s \
    "${SOURCE_CONFIG}" \
    "${AVAILABLE}"

test -x "${DEPLOY_HOOK_TARGET}"

if [ "${MODE}" = "acme" ]; then

    if ss -ltnH |
        awk '{print $4}' |
        grep -Eq '(^|:)443$'
    then
        fail "HTTPS listener appeared during ACME-only installation."
    fi

else

    ss -ltnH |
        awk '{print $4}' |
        grep -Eq '(^|:)443$' \
        || fail "HTTPS listener is absent after HTTPS installation."
fi

trap - EXIT

printf 'D7_MODE=%s\n' "${MODE}"
printf 'D7_ROLLBACK_DIR=%s\n' "${ROLLBACK_DIR}"
printf '%s\n' 'MERIDIAN_D7_INSTALL=SUCCESS'
