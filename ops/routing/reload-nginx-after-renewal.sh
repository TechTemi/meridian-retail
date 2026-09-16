#!/usr/bin/env bash

set -Eeuo pipefail

test "$(id -u)" = "0" \
    || {
        printf '%s\n' 'ERROR: Certbot deploy hook must run as root.' >&2
        exit 1
    }

NGINX="$(command -v nginx)"
SYSTEMCTL="$(command -v systemctl)"

"${NGINX}" -t
"${SYSTEMCTL}" reload nginx

printf '%s\n' 'MERIDIAN_CERTBOT_DEPLOY_HOOK=SUCCESS'
