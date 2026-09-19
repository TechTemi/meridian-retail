$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Write-Host ""
Write-Host "=== MERIDIAN D10 - SOURCE QUALIFICATION GATE ===" `
    -ForegroundColor Cyan

$ExpectedBranch =
    "feat/d10-ci-cd"

$D9Merge =
    "0a825def4fb507bd3b6bf215571386acbb34df92"

$D10ImplementationCommit =
    "804f3a8ff9da4dea801e52703c08e3d42f8c7b7b"

$RemediationFiles = @(
    "docs/ci-cd.md",
    "ops/deployment/github-actions-production-deploy.sh",
    "ops/validation/Invoke-MeridianD10SourceGate.ps1"
) | Sort-Object

$ExpectedFiles = @(
    ".github/workflows/deploy.yml",
    "docs/ci-cd.md",
    "ops/deployment/github-actions-production-deploy.sh",
    "ops/ssh/known_hosts.production",
    "ops/validation/Invoke-MeridianD10SourceGate.ps1",
    "README.md"
) | Sort-Object

$NewFiles = @(
    ".github/workflows/deploy.yml",
    "docs/ci-cd.md",
    "ops/deployment/github-actions-production-deploy.sh",
    "ops/ssh/known_hosts.production",
    "ops/validation/Invoke-MeridianD10SourceGate.ps1"
)

function Assert-Contains {
    param(
        [string]$Text,
        [string]$Expected,
        [string]$Gate
    )

    if (-not $Text.Contains($Expected)) {
        throw "FAIL ${Gate}: required contract absent: ${Expected}"
    }
}

function Assert-NotContains {
    param(
        [string]$Text,
        [string]$Forbidden,
        [string]$Gate
    )

    if ($Text.Contains($Forbidden)) {
        throw "FAIL ${Gate}: forbidden contract present: ${Forbidden}"
    }
}

function Assert-LfNoBom {
    param([string]$Path)

    [byte[]]$Bytes =
        [System.IO.File]::ReadAllBytes(
            (Join-Path (Get-Location) $Path)
        )

    if (
        $Bytes.Length -ge 3 -and
        $Bytes[0] -eq 239 -and
        $Bytes[1] -eq 187 -and
        $Bytes[2] -eq 191
    ) {
        throw "FAIL D10-GATE-2: BOM detected: $Path"
    }

    for ($i = 1; $i -lt $Bytes.Length; $i++) {
        if (
            $Bytes[$i - 1] -eq 13 -and
            $Bytes[$i] -eq 10
        ) {
            throw "FAIL D10-GATE-2: CRLF detected: $Path"
        }
    }
}

if ((git branch --show-current).Trim() -ne $ExpectedBranch) {
    throw "FAIL D10-GATE-1: unexpected branch."
}

git merge-base --is-ancestor $D9Merge HEAD

if ($LASTEXITCODE -ne 0) {
    throw "FAIL D10-GATE-1: D9 merge is not an ancestor."
}

foreach ($Path in $ExpectedFiles) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "FAIL D10-GATE-1: required artifact absent: $Path"
    }

    if ((Get-Item -LiteralPath $Path).Length -eq 0) {
        throw "FAIL D10-GATE-1: empty artifact: $Path"
    }
}

Write-Host "PASS D10-GATE-1: six-file D10 source boundary exists."

foreach ($Path in $NewFiles) {
    Assert-LfNoBom -Path $Path
}

Write-Host "PASS D10-GATE-2: new D10 artifacts are LF-only and BOM-free."

$CurrentHead =
    (git rev-parse HEAD).Trim()

$ExpectedObservedPaths = @()

if ($CurrentHead -eq $D9Merge) {

    $Gate3Mode =
        "INITIAL_D10_WORKTREE"

    $ExpectedObservedPaths =
        @($ExpectedFiles)
}
elseif ($CurrentHead -eq $D10ImplementationCommit) {

    $Gate3Mode =
        "D10_COMPOSE_REMEDIATION_WORKTREE"

    $ExpectedObservedPaths =
        @($RemediationFiles)
}
else {

    git merge-base --is-ancestor `
        $D10ImplementationCommit `
        $CurrentHead

    if ($LASTEXITCODE -ne 0) {
        throw "FAIL D10-GATE-3: HEAD is outside qualified D10 history."
    }

    $Gate3Mode =
        "D10_COMPOSE_REMEDIATION_COMMITTED"

    $CommittedRemediationPaths = @(
        git diff `
            --name-only `
            $D10ImplementationCommit `
            $CurrentHead `
            --
    ) |
        ForEach-Object {
            ([string]$_).Trim()
        } |
        Where-Object {
            $_ -ne ""
        } |
        Sort-Object -Unique

    if (
        @(
            Compare-Object `
                $RemediationFiles `
                $CommittedRemediationPaths
        ).Count -ne 0
    ) {
        Write-Host "EXPECTED COMMITTED REMEDIATION FILES:"

        $RemediationFiles |
            ForEach-Object {
                Write-Host "  $_"
            }

        Write-Host "OBSERVED COMMITTED REMEDIATION FILES:"

        $CommittedRemediationPaths |
            ForEach-Object {
                Write-Host "  $_"
            }

        throw "FAIL D10-GATE-3: committed remediation surface differs."
    }

    $ExpectedObservedPaths = @()
}

$StatusRows = @(
    git status `
        --porcelain=v1 `
        --untracked-files=all
)

$ObservedPaths =
    New-Object System.Collections.Generic.List[string]

foreach ($Row in $StatusRows) {

    $Text =
        [string]$Row

    if ($Text.Length -lt 4) {
        throw "FAIL D10-GATE-3: malformed Git status row."
    }

    $Path =
        $Text.Substring(3).Trim('"')

    if ($Path.Contains(" -> ")) {
        $Path =
            ($Path -split ' -> ')[-1].Trim('"')
    }

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $ObservedPaths.Add($Path)
    }
}

$ObservedPaths =
    @(
        $ObservedPaths |
            Sort-Object -Unique
    )

$ExpectedObservedPaths =
    @(
        $ExpectedObservedPaths |
            Sort-Object -Unique
    )

Write-Host "D10_GATE_3_MODE=$Gate3Mode"

if (
    @(
        Compare-Object `
            $ExpectedObservedPaths `
            $ObservedPaths
    ).Count -ne 0
) {
    Write-Host "EXPECTED:"

    $ExpectedObservedPaths |
        ForEach-Object {
            Write-Host "  $_"
        }

    Write-Host "OBSERVED:"

    $ObservedPaths |
        ForEach-Object {
            Write-Host "  $_"
        }

    throw "FAIL D10-GATE-3: phase-aware source surface differs."
}

Write-Host "PASS D10-GATE-3: phase-aware mutation/commit surface passes."

$Workflow =
    Get-Content `
        -LiteralPath ".github/workflows/deploy.yml" `
        -Raw

foreach ($Required in @(
    "push:",
    "- main",
    "contents: read",
    "id-token: write",
    "group: meridian-production-deploy",
    "cancel-in-progress: false",
    "actions/checkout@11d5960a326750d5838078e36cf38b85af677262",
    "aws-actions/configure-aws-credentials@7474bc4690e29a8392af63c5b98e7449536d5c3a",
    "EC2_SSH_PRIVATE_KEY",
    "github-actions-production-deploy.sh",
    'if: ${{ always() }}',
    "describe-security-groups",
    "DEFENSE_IN_DEPTH_CLEANUP=COMPLETE"
)) {
    Assert-Contains `
        -Text $Workflow `
        -Expected $Required `
        -Gate "D10-GATE-4"
}

foreach ($Forbidden in @(
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "ssh-keyscan",
    "workflow_dispatch:",
    "pull_request:",
    "describe-security-group-rules"
)) {
    Assert-NotContains `
        -Text $Workflow `
        -Forbidden $Forbidden `
        -Gate "D10-GATE-4"
}

$ActionUses =
    [regex]::Matches(
        $Workflow,
        '(?m)^\s*uses:\s*([^\s#]+)\s*$'
    )

if ($ActionUses.Count -eq 0) {
    throw "FAIL D10-GATE-4: workflow contains no action references."
}

foreach ($ActionUse in $ActionUses) {

    $Reference =
        [string]$ActionUse.Groups[1].Value

    if (
        $Reference -notmatch
        '^[^/@]+/[^/@]+@[0-9a-f]{40}$'
    ) {
        throw (
            "FAIL D10-GATE-4: action reference is not pinned " +
            "to a full Git commit SHA: " +
            $Reference
        )
    }
}

Write-Host "PASS D10-GATE-4: workflow security, trigger, and full-SHA action-pin contracts pass."

$Helper =
    Get-Content `
        -LiteralPath "ops/deployment/github-actions-production-deploy.sh" `
        -Raw

foreach ($Required in @(
    "set -Eeuo pipefail",
    "umask 077",
    "batch-get-image",
    "PARTIAL_ECR_SHA_SET",
    "ECR_ALL_FOUR_RELEASE_IMAGES=QUALIFIED",
    "checkip.amazonaws.com",
    "RUNNER_CIDR",
    "describe-security-groups",
    "authorize-security-group-ingress",
    "SecurityGroupRuleId",
    "revoke-security-group-ingress",
    "StrictHostKeyChecking=yes",
    "UserKnownHostsFile=",
    "CheckHostIP=yes",
    "UpdateHostKeys=no",
    "ops/deployment/deploy-production.sh",
    "sha256sum",
    "REMOTE_DEPLOY_SCRIPT_SHA256=QUALIFIED",
    "ops/deployment/docker-compose.production.yml",
    "/opt/meridian/app/docker-compose.production.yml",
    "PRODUCTION_COMPOSE_DRIFT_CHECK=PASS",
    "production Compose drift detected; deployment blocked.",
    'if [[ "${remote_compose_sha}" != "${local_compose_sha}" ]]; then',
    "MERIDIAN_PRODUCTION_DEPLOYMENT=SUCCESS",
    "MERIDIAN_GITHUB_ACTIONS_DEPLOYMENT=SUCCESS"
)) {
    Assert-Contains `
        -Text $Helper `
        -Expected $Required `
        -Gate "D10-GATE-5"
}

foreach ($Forbidden in @(
    "ecr describe-images",
    "describe-security-group-rules",
    "ssh-keyscan",
    "StrictHostKeyChecking=no",
    "0.0.0.0/0",
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "docker compose down",
    "meridian-postgres-data"
)) {
    Assert-NotContains `
        -Text $Helper `
        -Forbidden $Forbidden `
        -Gate "D10-GATE-5"
}

$ComposePathReferenceCount =
    [regex]::Matches(
        $Helper,
        [regex]::Escape("docker-compose.production.yml")
    ).Count

if ($ComposePathReferenceCount -ne 2) {
    throw (
        "FAIL D10-GATE-5: expected exactly two production " +
        "Compose-path references in helper."
    )
}

$ComposeShaValidationCount =
    [regex]::Matches(
        $Helper,
        [regex]::Escape('^[0-9a-f]{64}$')
    ).Count

if ($ComposeShaValidationCount -lt 2) {
    throw (
        "FAIL D10-GATE-5: both local and remote Compose " +
        "SHA-256 values must be format-validated."
    )
}

$ComposeDriftPassIndex =
    $Helper.IndexOf(
        "PRODUCTION_COMPOSE_DRIFT_CHECK=PASS"
    )

$DeployTransportIndex =
    $Helper.IndexOf(
        'LOCAL_DEPLOY_SCRIPT="ops/deployment/deploy-production.sh"'
    )

if (
    $ComposeDriftPassIndex -lt 0 -or
    $DeployTransportIndex -lt 0 -or
    $ComposeDriftPassIndex -ge $DeployTransportIndex
) {
    throw (
        "FAIL D10-GATE-5: production Compose drift check " +
        "must complete before deployment-script transport."
    )
}

Write-Host "PASS D10-GATE-5A: production Compose drift interlock passes."
Write-Host "PASS D10-GATE-5: helper matches qualified IAM and fail-closed contracts."

$KnownHosts =
    (
        Get-Content `
            -LiteralPath "ops/ssh/known_hosts.production" `
            -Raw
    ).Trim()

$ExpectedKnownHosts =
    "98.88.168.236 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGgooQIRL2eR6rfOeFQW7AV6J8d02WAwITf33h3EXxFc"

if ($KnownHosts -ne $ExpectedKnownHosts) {
    throw "FAIL D10-GATE-6: pinned known_hosts entry changed."
}

$FingerprintRows = @(
    $KnownHosts |
        ssh-keygen -lf -
)

if (
    $LASTEXITCODE -ne 0 -or
    $FingerprintRows.Count -ne 1
) {
    throw "FAIL D10-GATE-6: host-key fingerprint failed."
}

$Fingerprint =
    ($FingerprintRows[0] -split '\s+')[1]

if (
    $Fingerprint -ne
    "SHA256:ik98Tz3p5Zb00VTC3J1CznxEGpH1xFRBu5fBculmYEU"
) {
    throw "FAIL D10-GATE-6: pinned host fingerprint changed."
}

Write-Host "PASS D10-GATE-6: pinned production SSH identity passes."

$TerraformIam =
    Get-Content `
        -LiteralPath "terraform/github_oidc.tf" `
        -Raw

foreach ($Required in @(
    "ecr:BatchGetImage",
    "ec2:DescribeSecurityGroups",
    "ec2:AuthorizeSecurityGroupIngress",
    "ec2:RevokeSecurityGroupIngress"
)) {
    Assert-Contains `
        -Text $TerraformIam `
        -Expected $Required `
        -Gate "D10-GATE-7"
}

Assert-NotContains `
    -Text $Helper `
    -Forbidden "ecr:DescribeImages" `
    -Gate "D10-GATE-7"

Assert-NotContains `
    -Text $Helper `
    -Forbidden "ec2:DescribeSecurityGroupRules" `
    -Gate "D10-GATE-7"

Write-Host "PASS D10-GATE-7: helper operations remain inside frozen IAM discovery surface."

$Docs =
    Get-Content `
        -LiteralPath "docs/ci-cd.md" `
        -Raw

foreach ($Required in @(
    "full 40-character Git commit SHA",
    "partial SHA set",
    "EC2_SSH_PRIVATE_KEY",
    "/opt/meridian/config/.env.production",
    'temporary `/32`',
    "automatic rollback",
    "host-resident"
)) {
    Assert-Contains `
        -Text $Docs `
        -Expected $Required `
        -Gate "D10-GATE-8"
}

foreach ($Required in @(
    "Production Compose drift interlock",
    "ops/deployment/docker-compose.production.yml",
    "/opt/meridian/app/docker-compose.production.yml",
    "PRODUCTION_COMPOSE_DRIFT_CHECK=PASS"
)) {
    Assert-Contains `
        -Text $Docs `
        -Expected $Required `
        -Gate "D10-GATE-8"
}
$Readme =
    Get-Content `
        -LiteralPath "README.md" `
        -Raw

foreach ($Required in @(
    "## D10 Production CI/CD",
    ".github/workflows/deploy.yml",
    "docs/ci-cd.md"
)) {
    Assert-Contains `
        -Text $Readme `
        -Expected $Required `
        -Gate "D10-GATE-8"
}

Write-Host "PASS D10-GATE-8: documentation contract passes."

git diff --quiet `
    $D9Merge `
    -- `
    ops/deployment/deploy-production.sh

if ($LASTEXITCODE -ne 0) {
    throw "FAIL D10-GATE-9: qualified production deploy script changed."
}

git diff --check

if ($LASTEXITCODE -ne 0) {
    throw "FAIL D10-GATE-9: git diff --check failed."
}

Write-Host "PASS D10-GATE-9: existing deploy entry point unchanged and diff integrity clean."

Write-Host ""
Write-Host "=== MERIDIAN D10 SOURCE QUALIFICATION GATE: PASS ===" `
    -ForegroundColor Green
