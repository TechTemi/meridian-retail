#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

AWS_REGION="${AWS_REGION:?AWS_REGION is required}"
ECR_REGISTRY="${ECR_REGISTRY:?ECR_REGISTRY is required}"
PRODUCTION_SECURITY_GROUP_ID="${PRODUCTION_SECURITY_GROUP_ID:?PRODUCTION_SECURITY_GROUP_ID is required}"
PRODUCTION_HOST="${PRODUCTION_HOST:?PRODUCTION_HOST is required}"
PRODUCTION_USER="${PRODUCTION_USER:?PRODUCTION_USER is required}"
SSH_KEY_PATH="${SSH_KEY_PATH:?SSH_KEY_PATH is required}"
KNOWN_HOSTS_PATH="${KNOWN_HOSTS_PATH:?KNOWN_HOSTS_PATH is required}"

GITHUB_SHA="${GITHUB_SHA:?GITHUB_SHA is required}"
GITHUB_RUN_ID="${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"
GITHUB_RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:?GITHUB_RUN_ATTEMPT is required}"
RUNNER_TEMP="${RUNNER_TEMP:?RUNNER_TEMP is required}"
LOCAL_PRODUCTION_COMPOSE="ops/deployment/docker-compose.production.yml"

if [[ ! "${GITHUB_SHA}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "FAIL: GITHUB_SHA must be a full 40-character lowercase Git SHA." >&2
  exit 10
fi

if [[ ! "${GITHUB_RUN_ID}" =~ ^[0-9]+$ ]]; then
  echo "FAIL: GITHUB_RUN_ID is invalid." >&2
  exit 11
fi

if [[ ! "${GITHUB_RUN_ATTEMPT}" =~ ^[0-9]+$ ]]; then
  echo "FAIL: GITHUB_RUN_ATTEMPT is invalid." >&2
  exit 12
fi

for command in \
  aws \
  awk \
  curl \
  docker \
  grep \
  jq \
  scp \
  sha256sum \
  ssh
do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "FAIL: required command unavailable: ${command}" >&2
    exit 13
  }
done

for file in \
  "${SSH_KEY_PATH}" \
  "${KNOWN_HOSTS_PATH}" \
  "${LOCAL_PRODUCTION_COMPOSE}" \
  "ops/deployment/deploy-production.sh"
do
  [[ -f "${file}" ]] || {
    echo "FAIL: required file absent: ${file}" >&2
    exit 14
  }
done

REPOSITORIES=(
  auth
  catalog
  orders
  frontend
)

RULE_STATE_FILE="${RUNNER_TEMP}/meridian-d10-rule-state.tsv"
DEPLOY_OUTPUT="${RUNNER_TEMP}/meridian-d10-deploy-output.txt"

REMOTE_SCRIPT="/tmp/meridian-deploy-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}-${GITHUB_SHA}.sh"
RULE_DESCRIPTION="Meridian GitHub Actions run ${GITHUB_RUN_ID} attempt ${GITHUB_RUN_ATTEMPT}"

TEMP_RULE_ID=""
RUNNER_CIDR=""
ECR_LOGGED_IN="NO"

SSH_OPTS=(
  -4
  -i "${SSH_KEY_PATH}"
  -o BatchMode=yes
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=yes
  -o UserKnownHostsFile="${KNOWN_HOSTS_PATH}"
  -o CheckHostIP=yes
  -o UpdateHostKeys=no
  -o ConnectTimeout=15
)

ecr_manifest() {
  local service="$1"

  aws ecr batch-get-image \
    --region "${AWS_REGION}" \
    --repository-name "meridian/${service}" \
    --image-ids "imageTag=${GITHUB_SHA}" \
    --query 'images[0].imageManifest' \
    --output text \
    2>/dev/null
}

ecr_image_exists() {
  local service="$1"
  local manifest

  manifest="$(ecr_manifest "${service}")"

  [[ \
    -n "${manifest}" && \
    "${manifest}" != "None" && \
    "${manifest}" != "null" \
  ]]
}

verify_ecr_image_matches_local() {
  local service="$1"
  local repository="meridian/${service}"
  local local_image="meridian-${service}:${GITHUB_SHA}"
  local manifest
  local remote_config_digest
  local local_config_digest

  manifest="$(ecr_manifest "${service}")"

  if [[ \
    -z "${manifest}" || \
    "${manifest}" == "None" || \
    "${manifest}" == "null" \
  ]]; then
    echo "FAIL: ECR manifest unavailable for ${repository}:${GITHUB_SHA}." >&2
    return 1
  fi

  remote_config_digest="$(
    jq -er '.config.digest' <<<"${manifest}"
  )"

  local_config_digest="$(
    docker image inspect \
      --format '{{.Id}}' \
      "${local_image}"
  )"

  if [[ "${remote_config_digest}" != "${local_config_digest}" ]]; then
    echo "FAIL: ECR image differs from locally built ${service} image." >&2
    return 1
  fi

  echo "ECR_IMAGE_VERIFIED=${repository}:${GITHUB_SHA}"
}

validate_ipv4() {
  local ip="$1"
  local octet
  local -a parts

  if [[ ! "${ip}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    return 1
  fi

  IFS='.' read -r -a parts <<<"${ip}"

  [[ "${#parts[@]}" -eq 4 ]] || return 1

  for octet in "${parts[@]}"; do
    if (( 10#${octet} < 0 || 10#${octet} > 255 )); then
      return 1
    fi
  done
}

get_security_group_json() {
  aws ec2 describe-security-groups \
    --region "${AWS_REGION}" \
    --group-ids "${PRODUCTION_SECURITY_GROUP_ID}" \
    --output json
}

count_ssh_cidr_rules() {
  local cidr="$1"
  local sg_json

  sg_json="$(get_security_group_json)"

  jq \
    --arg cidr "${cidr}" \
    '[
      .SecurityGroups[0].IpPermissions[]?
      | select(
          .IpProtocol == "tcp"
          and .FromPort == 22
          and .ToPort == 22
        )
      | .IpRanges[]?
      | select(.CidrIp == $cidr)
    ] | length' \
    <<<"${sg_json}"
}

count_owned_ssh_rules() {
  local cidr="$1"
  local description="$2"
  local sg_json

  sg_json="$(get_security_group_json)"

  jq \
    --arg cidr "${cidr}" \
    --arg description "${description}" \
    '[
      .SecurityGroups[0].IpPermissions[]?
      | select(
          .IpProtocol == "tcp"
          and .FromPort == 22
          and .ToPort == 22
        )
      | .IpRanges[]?
      | select(
          .CidrIp == $cidr
          and (.Description // "") == $description
        )
    ] | length' \
    <<<"${sg_json}"
}

cleanup_remote_script() {
  set +e

  if [[ -z "${TEMP_RULE_ID}" ]]; then
    return 0
  fi

  # REMOTE_SCRIPT is a locally validated workflow-owned path.
  # shellcheck disable=SC2029
  ssh \
    "${SSH_OPTS[@]}" \
    "${PRODUCTION_USER}@${PRODUCTION_HOST}" \
    "rm -f -- '${REMOTE_SCRIPT}'" \
    >/dev/null 2>&1

  return $?
}

cleanup_security_group_rule() {
  local owned_count

  if [[ -z "${TEMP_RULE_ID}" ]]; then
    return 0
  fi

  if [[ ! "${TEMP_RULE_ID}" =~ ^sgr-[0-9a-f]+$ ]]; then
    echo "WARN: refusing cleanup of malformed rule ID." >&2
    return 1
  fi

  if [[ -z "${RUNNER_CIDR}" ]]; then
    echo "WARN: runner CIDR unavailable for cleanup." >&2
    return 1
  fi

  owned_count="$(
    count_owned_ssh_rules \
      "${RUNNER_CIDR}" \
      "${RULE_DESCRIPTION}"
  )"

  if [[ "${owned_count}" == "0" ]]; then
    TEMP_RULE_ID=""
    rm -f "${RULE_STATE_FILE}"
    return 0
  fi

  if [[ "${owned_count}" != "1" ]]; then
    echo "WARN: ambiguous workflow-owned SSH-rule state." >&2
    return 1
  fi

  aws ec2 revoke-security-group-ingress \
    --region "${AWS_REGION}" \
    --group-id "${PRODUCTION_SECURITY_GROUP_ID}" \
    --security-group-rule-ids "${TEMP_RULE_ID}" \
    >/dev/null || return 1

  owned_count="$(
    count_owned_ssh_rules \
      "${RUNNER_CIDR}" \
      "${RULE_DESCRIPTION}"
  )"

  if [[ "${owned_count}" != "0" ]]; then
    echo "WARN: workflow-owned SSH rule remains after revoke." >&2
    return 1
  fi

  TEMP_RULE_ID=""
  rm -f "${RULE_STATE_FILE}"

  return 0
}

cleanup() {
  exit_code=$?

  set +e

  cleanup_remote_script || true
  cleanup_security_group_rule || true

  if [[ "${ECR_LOGGED_IN}" == "YES" ]]; then
    docker logout "${ECR_REGISTRY}" >/dev/null 2>&1 || true
  fi

  rm -f "${DEPLOY_OUTPUT}"

  exit "${exit_code}"
}

trap cleanup EXIT

echo "=== MERIDIAN D10 PRODUCTION DEPLOYMENT HELPER ==="
echo "RELEASE_SHA=${GITHUB_SHA}"

# -----------------------------------------------------------------
# 1. Determine immutable ECR release-set state.
# -----------------------------------------------------------------

existing_count=0

for service in "${REPOSITORIES[@]}"; do
  if ecr_image_exists "${service}"; then
    existing_count=$((existing_count + 1))
    echo "ECR_IMAGE_ALREADY_EXISTS=meridian/${service}:${GITHUB_SHA}"
  else
    echo "ECR_IMAGE_ABSENT=meridian/${service}:${GITHUB_SHA}"
  fi
done

echo "EXISTING_RELEASE_IMAGE_COUNT=${existing_count}"

if (( existing_count > 0 && existing_count < 4 )); then
  echo "FAIL: PARTIAL_ECR_SHA_SET detected; deployment blocked." >&2
  exit 20
fi

# -----------------------------------------------------------------
# 2. Publish only when the full SHA is absent everywhere.
# -----------------------------------------------------------------

if (( existing_count == 0 )); then
  aws ecr get-login-password \
    --region "${AWS_REGION}" |
    docker login \
      --username AWS \
      --password-stdin \
      "${ECR_REGISTRY}"

  ECR_LOGGED_IN="YES"

  for service in "${REPOSITORIES[@]}"; do
    docker tag \
      "meridian-${service}:${GITHUB_SHA}" \
      "${ECR_REGISTRY}/meridian/${service}:${GITHUB_SHA}"
  done

  for service in "${REPOSITORIES[@]}"; do
    docker push \
      "${ECR_REGISTRY}/meridian/${service}:${GITHUB_SHA}"
  done

  docker logout "${ECR_REGISTRY}" >/dev/null
  ECR_LOGGED_IN="NO"

  echo "ECR_PUBLICATION=COMPLETE"
else
  echo "ECR_PUBLICATION=REUSE_EXISTING_IMMUTABLE_SHA"
fi

# -----------------------------------------------------------------
# 3. All four images must exist and match this run's local builds.
# -----------------------------------------------------------------

for service in "${REPOSITORIES[@]}"; do
  if ! ecr_image_exists "${service}"; then
    echo "FAIL: release image absent after publication: ${service}" >&2
    exit 21
  fi

  verify_ecr_image_matches_local "${service}"
done

echo "ECR_ALL_FOUR_RELEASE_IMAGES=QUALIFIED"

# -----------------------------------------------------------------
# 4. Resolve exact GitHub runner public IPv4.
# -----------------------------------------------------------------

RUNNER_IP="$(
  curl \
    -4 \
    --fail \
    --silent \
    --show-error \
    --max-time 10 \
    https://checkip.amazonaws.com |
    tr -d '[:space:]'
)"

if ! validate_ipv4 "${RUNNER_IP}"; then
  echo "FAIL: runner public IPv4 validation failed." >&2
  exit 30
fi

RUNNER_CIDR="${RUNNER_IP}/32"

echo "RUNNER_IPV4=QUALIFIED"

# -----------------------------------------------------------------
# 5. Refuse ownership of an existing SSH rule.
# -----------------------------------------------------------------

existing_rule_count="$(
  count_ssh_cidr_rules "${RUNNER_CIDR}"
)"

if [[ ! "${existing_rule_count}" =~ ^[0-9]+$ ]]; then
  echo "FAIL: existing runner SSH-rule count is invalid." >&2
  exit 31
fi

if (( existing_rule_count != 0 )); then
  echo "FAIL: runner /32 already has TCP/22 access." >&2
  exit 32
fi

# -----------------------------------------------------------------
# 6. Create one temporary, workflow-owned SSH rule.
# -----------------------------------------------------------------

permission_json="$(
  jq \
    --compact-output \
    --null-input \
    --arg cidr "${RUNNER_CIDR}" \
    --arg description "${RULE_DESCRIPTION}" \
    '[
      {
        IpProtocol: "tcp",
        FromPort: 22,
        ToPort: 22,
        IpRanges: [
          {
            CidrIp: $cidr,
            Description: $description
          }
        ]
      }
    ]'
)"

TEMP_RULE_ID="$(
  aws ec2 authorize-security-group-ingress \
    --region "${AWS_REGION}" \
    --group-id "${PRODUCTION_SECURITY_GROUP_ID}" \
    --ip-permissions "${permission_json}" \
    --query 'SecurityGroupRules[0].SecurityGroupRuleId' \
    --output text
)"

if [[ ! "${TEMP_RULE_ID}" =~ ^sgr-[0-9a-f]+$ ]]; then
  echo "FAIL: temporary SSH-rule ID was not returned." >&2
  exit 33
fi

printf '%s\t%s\t%s\n' \
  "${TEMP_RULE_ID}" \
  "${RUNNER_CIDR}" \
  "${RULE_DESCRIPTION}" \
  > "${RULE_STATE_FILE}"

chmod 600 "${RULE_STATE_FILE}"

owned_count="$(
  count_owned_ssh_rules \
    "${RUNNER_CIDR}" \
    "${RULE_DESCRIPTION}"
)"

if [[ "${owned_count}" != "1" ]]; then
  echo "FAIL: temporary SSH-rule ownership verification failed." >&2
  exit 34
fi

echo "TEMPORARY_SSH_RULE=QUALIFIED"

# -----------------------------------------------------------------
# 7. Strict pinned-host SSH.
# -----------------------------------------------------------------

ssh \
  "${SSH_OPTS[@]}" \
  "${PRODUCTION_USER}@${PRODUCTION_HOST}" \
  'printf "%s\n" "PINNED_SSH_CONNECTIVITY=PASS"'

# -----------------------------------------------------------------
# 8. Fail closed on production Compose drift.
# -----------------------------------------------------------------

local_compose_sha="$(
  sha256sum "${LOCAL_PRODUCTION_COMPOSE}" |
    awk '{print $1}'
)"

if [[ ! "${local_compose_sha}" =~ ^[0-9a-f]{64}$ ]]; then
  echo "FAIL: source production Compose SHA-256 is invalid." >&2
  exit 35
fi

if ! remote_compose_sha_line="$(
  ssh \
    "${SSH_OPTS[@]}" \
    "${PRODUCTION_USER}@${PRODUCTION_HOST}" \
    'sha256sum -- /opt/meridian/app/docker-compose.production.yml'
)"; then
  echo "FAIL: unable to hash live production Compose file." >&2
  exit 36
fi

remote_compose_sha="${remote_compose_sha_line%% *}"

if [[ ! "${remote_compose_sha}" =~ ^[0-9a-f]{64}$ ]]; then
  echo "FAIL: live production Compose SHA-256 is invalid." >&2
  exit 37
fi

if [[ "${remote_compose_sha}" != "${local_compose_sha}" ]]; then
  echo "FAIL: production Compose drift detected; deployment blocked." >&2
  exit 38
fi

echo "PRODUCTION_COMPOSE_DRIFT_CHECK=PASS"

# -----------------------------------------------------------------
# 9. Transport exact source-controlled deployment script.
# -----------------------------------------------------------------

LOCAL_DEPLOY_SCRIPT="ops/deployment/deploy-production.sh"

local_deploy_sha="$(
  sha256sum "${LOCAL_DEPLOY_SCRIPT}" |
    awk '{print $1}'
)"

scp \
  "${SSH_OPTS[@]}" \
  "${LOCAL_DEPLOY_SCRIPT}" \
  "${PRODUCTION_USER}@${PRODUCTION_HOST}:${REMOTE_SCRIPT}"

remote_sha_line="$(
  # REMOTE_SCRIPT is a locally validated workflow-owned path.
  # shellcheck disable=SC2029
  ssh \
    "${SSH_OPTS[@]}" \
    "${PRODUCTION_USER}@${PRODUCTION_HOST}" \
    "sha256sum '${REMOTE_SCRIPT}'"
)"

remote_deploy_sha="${remote_sha_line%% *}"

if [[ "${remote_deploy_sha}" != "${local_deploy_sha}" ]]; then
  echo "FAIL: transported deployment-script SHA-256 mismatch." >&2
  exit 40
fi

echo "REMOTE_DEPLOY_SCRIPT_SHA256=QUALIFIED"

# -----------------------------------------------------------------
# 10. Execute qualified production deployment entry point.
# -----------------------------------------------------------------

# REMOTE_SCRIPT and GITHUB_SHA are validated locally before remote execution.
# shellcheck disable=SC2029
ssh \
  "${SSH_OPTS[@]}" \
  "${PRODUCTION_USER}@${PRODUCTION_HOST}" \
  "chmod 700 '${REMOTE_SCRIPT}' && bash '${REMOTE_SCRIPT}' '${GITHUB_SHA}'" |
  tee "${DEPLOY_OUTPUT}"

if ! grep \
  --fixed-strings \
  --line-regexp \
  --quiet \
  'MERIDIAN_PRODUCTION_DEPLOYMENT=SUCCESS' \
  "${DEPLOY_OUTPUT}"
then
  echo "FAIL: production success marker not observed." >&2
  exit 41
fi

echo "PRODUCTION_DEPLOYMENT_MARKER=QUALIFIED"

# -----------------------------------------------------------------
# 11. Explicit successful cleanup.
# -----------------------------------------------------------------

if ! cleanup_remote_script; then
  echo "FAIL: temporary remote deployment-script cleanup failed." >&2
  exit 42
fi

if ! cleanup_security_group_rule; then
  echo "FAIL: temporary SSH-rule cleanup failed." >&2
  exit 43
fi

if [[ -n "${TEMP_RULE_ID}" || -e "${RULE_STATE_FILE}" ]]; then
  echo "FAIL: temporary SSH-rule state did not close." >&2
  exit 44
fi

echo "TEMPORARY_SSH_ACCESS_CLEANUP=QUALIFIED"
echo "MERIDIAN_GITHUB_ACTIONS_DEPLOYMENT=SUCCESS"
