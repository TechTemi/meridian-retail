#!/usr/bin/env bash

set -Eeuo pipefail

BOOTSTRAP_VERSION="stage5b-v1"
MERIDIAN_ROOT="/opt/meridian"
LOG_FILE="/var/log/meridian-bootstrap.log"

log() {
    printf '[%s] %s\n' \
        "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        "$*"
}

fail() {
    log "ERROR: $*"
    exit 1
}

if [[ "${EUID}" -ne 0 ]]; then
    fail "bootstrap must run as root"
fi

exec > >(tee -a "${LOG_FILE}") 2>&1

log "Starting Meridian host bootstrap ${BOOTSTRAP_VERSION}"

# -------------------------------------------------------------------
# Host guardrails
# -------------------------------------------------------------------

source /etc/os-release

[[ "${ID}" == "ubuntu" ]] \
    || fail "unsupported operating system: ${ID}"

[[ "${VERSION_ID}" == "22.04" ]] \
    || fail "unsupported Ubuntu version: ${VERSION_ID}"

command -v systemctl >/dev/null 2>&1 \
    || fail "systemd is required"

if ! id ubuntu >/dev/null 2>&1; then
    fail "expected ubuntu administrator account is absent"
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

log "Ubuntu 22.04 host guardrails passed"

# -------------------------------------------------------------------
# Base operating packages
# -------------------------------------------------------------------

apt-get update

apt-get install -y \
    ca-certificates \
    curl \
    git \
    gnupg \
    jq \
    nginx \
    cron \
    snapd \
    unzip

log "Base operating packages installed"

# -------------------------------------------------------------------
# Docker Engine - official Docker apt repository
# -------------------------------------------------------------------

DOCKER_CONFLICTS=(
    docker.io
    docker-compose
    docker-compose-v2
    docker-doc
    docker-buildx
    podman-docker
    containerd
    runc
)

INSTALLED_CONFLICTS=()

for package in "${DOCKER_CONFLICTS[@]}"; do
    if dpkg-query \
        -W \
        -f='${Status}' \
        "${package}" \
        2>/dev/null |
        grep -q '^install ok installed$'; then

        INSTALLED_CONFLICTS+=("${package}")
    fi
done

if (( ${#INSTALLED_CONFLICTS[@]} > 0 )); then
    log "Removing conflicting Docker packages"

    apt-get remove -y \
        "${INSTALLED_CONFLICTS[@]}"
fi

install \
    -m 0755 \
    -d \
    /etc/apt/keyrings

curl \
    -fsSL \
    https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc

chmod \
    a+r \
    /etc/apt/keyrings/docker.asc

DOCKER_ARCH="$(dpkg --print-architecture)"

source /etc/os-release

DOCKER_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME}}"

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${DOCKER_CODENAME}
Components: stable
Architectures: ${DOCKER_ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update

apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

log "Official Docker Engine packages installed"

# -------------------------------------------------------------------
# Docker daemon production baseline
# -------------------------------------------------------------------

install \
    -m 0755 \
    -d \
    /etc/docker

cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

systemctl daemon-reload

systemctl enable docker.service
systemctl enable containerd.service

systemctl restart docker

systemctl is-active --quiet docker \
    || fail "Docker daemon is not active"

systemctl is-active --quiet containerd \
    || fail "containerd is not active"

log "Docker daemon baseline configured"

# -------------------------------------------------------------------
# Administrator Docker access
# -------------------------------------------------------------------

getent group docker >/dev/null \
    || groupadd docker

usermod \
    -aG docker \
    ubuntu

id -nG ubuntu |
    tr ' ' '\n' |
    grep -qx docker \
    || fail "ubuntu was not added to docker group"

log "ubuntu added to docker group"

# -------------------------------------------------------------------
# Nginx
# -------------------------------------------------------------------

systemctl enable nginx
systemctl restart nginx

nginx -t

systemctl is-active --quiet nginx \
    || fail "Nginx is not active"

curl \
    --fail \
    --silent \
    --show-error \
    http://127.0.0.1/ \
    >/dev/null

log "Nginx installed and local HTTP response validated"

# -------------------------------------------------------------------
# cron
# -------------------------------------------------------------------

systemctl enable cron
systemctl restart cron

systemctl is-active --quiet cron \
    || fail "cron is not active"

log "cron service validated"

# -------------------------------------------------------------------
# Certbot - official recommended snap installation
# -------------------------------------------------------------------

systemctl enable --now snapd.socket

snap wait system seed.loaded

if ! snap list core >/dev/null 2>&1; then
    snap install core
fi

if ! snap list certbot >/dev/null 2>&1; then
    snap install \
        --classic \
        certbot
fi

ln \
    -sfn \
    /snap/bin/certbot \
    /usr/local/bin/certbot

command -v certbot >/dev/null 2>&1 \
    || fail "Certbot command is unavailable"

certbot --version

log "Certbot installed"

# -------------------------------------------------------------------
# AWS CLI v2 - official AWS system installer
# -------------------------------------------------------------------

if ! command -v aws >/dev/null 2>&1; then

    AWS_INSTALLER="/tmp/awscli-v2-install.sh"

    curl \
        -fsSL \
        https://awscli.amazonaws.com/v2/install.sh \
        -o "${AWS_INSTALLER}"

    chmod \
        0755 \
        "${AWS_INSTALLER}"

    bash \
        "${AWS_INSTALLER}" \
        --system

    rm -f \
        "${AWS_INSTALLER}"
fi

command -v aws >/dev/null 2>&1 \
    || fail "AWS CLI command is unavailable"

aws --version

log "AWS CLI v2 installed"

# -------------------------------------------------------------------
# Meridian operating directories
# -------------------------------------------------------------------

install \
    -d \
    -o root \
    -g docker \
    -m 2775 \
    "${MERIDIAN_ROOT}"

install \
    -d \
    -o root \
    -g docker \
    -m 2775 \
    "${MERIDIAN_ROOT}/app" \
    "${MERIDIAN_ROOT}/config" \
    "${MERIDIAN_ROOT}/scripts" \
    "${MERIDIAN_ROOT}/evidence"

install \
    -d \
    -o root \
    -g docker \
    -m 2770 \
    "${MERIDIAN_ROOT}/backups"

log "Meridian operating directories created"

# -------------------------------------------------------------------
# Preserve exact bootstrap artifact on the host
# -------------------------------------------------------------------

if [[ "$(readlink -f "$0")" != \
      "${MERIDIAN_ROOT}/scripts/bootstrap-host.sh" ]]; then

    install \
        -o root \
        -g docker \
        -m 0755 \
        "$0" \
        "${MERIDIAN_ROOT}/scripts/bootstrap-host.sh"
fi

printf '%s\n' \
    "${BOOTSTRAP_VERSION}" \
    > /var/lib/meridian-bootstrap-version

chmod \
    0644 \
    /var/lib/meridian-bootstrap-version

# -------------------------------------------------------------------
# Functional Docker proof
# -------------------------------------------------------------------

docker version >/dev/null

docker compose version >/dev/null

docker buildx version >/dev/null

docker run \
    --rm \
    hello-world \
    >/dev/null

docker image rm \
    hello-world:latest \
    >/dev/null 2>&1 \
    || true

log "Docker Engine, Compose and Buildx validated"

# -------------------------------------------------------------------
# Final service assertions
# -------------------------------------------------------------------

for service in docker containerd nginx cron; do

    systemctl is-enabled --quiet "${service}" \
        || fail "${service} is not enabled"

    systemctl is-active --quiet "${service}" \
        || fail "${service} is not active"
done

log "MERIDIAN_BOOTSTRAP=SUCCESS"
