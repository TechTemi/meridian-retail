$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Write-Host ""
Write-Host "=== MERIDIAN D9 - SOURCE QUALIFICATION GATE ===" `
    -ForegroundColor Cyan

$ScriptFile = $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($ScriptFile)) {
    throw "D9-SOURCE-GATE FAIL: unable to resolve source-gate script path."
}

$ValidationDir = Split-Path -Parent $ScriptFile

$RepositoryRoot = [System.IO.Path]::GetFullPath(
    (Join-Path -Path $ValidationDir -ChildPath "..\..")
)

if (-not (Test-Path -LiteralPath $RepositoryRoot -PathType Container)) {
    throw "D9-SOURCE-GATE FAIL: repository root not found: $RepositoryRoot"
}

$BackupScript = Join-Path $RepositoryRoot "scripts\backup_db.sh"
$RestoreScript = Join-Path $RepositoryRoot "scripts\restore_db.sh"
$StrategyDoc = Join-Path $RepositoryRoot "docs\backup-strategy.md"

function Fail-Gate {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    throw "D9-SOURCE-GATE FAIL: $Message"
}

function Require-File {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Fail-Gate "required file is absent: $Path"
    }

    $item = Get-Item -LiteralPath $Path

    if ($item.Length -eq 0) {
        Fail-Gate "required file is empty: $Path"
    }
}

function Require-Text {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [string]$Description
    )

    if ($Content -notmatch $Pattern) {
        Fail-Gate $Description
    }
}

function Forbid-Text {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [string]$Description
    )

    if ($Content -match $Pattern) {
        Fail-Gate $Description
    }
}

function Assert-UnixShellText {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)

    if (
        $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF
    ) {
        Fail-Gate "$Path contains a UTF-8 BOM."
    }

    if ($bytes -contains 0x0D) {
        Fail-Gate "$Path contains CR/CRLF line endings; LF-only is required."
    }

    $firstLine = (
        Get-Content -LiteralPath $Path -TotalCount 1
    )

    if ($firstLine -ne "#!/usr/bin/env bash") {
        Fail-Gate "$Path does not start with the governed Bash shebang."
    }
}

# ------------------------------------------------------------
# Gate 1 - required artifacts
# ------------------------------------------------------------

Require-File $BackupScript
Require-File $RestoreScript
Require-File $StrategyDoc

Write-Host "PASS D9-GATE-1: required D9 artifacts exist and are non-empty." `
    -ForegroundColor Green

# ------------------------------------------------------------
# Gate 2 - shell encoding / line endings
# ------------------------------------------------------------

Assert-UnixShellText $BackupScript
Assert-UnixShellText $RestoreScript

Write-Host "PASS D9-GATE-2: shell scripts are UTF-8-compatible, BOM-free, LF-only." `
    -ForegroundColor Green

$backup = Get-Content -LiteralPath $BackupScript -Raw
$restore = Get-Content -LiteralPath $RestoreScript -Raw
$docs = Get-Content -LiteralPath $StrategyDoc -Raw

# ------------------------------------------------------------
# Gate 3 - strict execution and permissions
# ------------------------------------------------------------

Require-Text `
    -Content $backup `
    -Pattern '(?m)^set -Eeuo pipefail$' `
    -Description "backup script does not enable strict Bash execution."

Require-Text `
    -Content $backup `
    -Pattern '(?m)^umask 077$' `
    -Description "backup script does not enforce umask 077."

Require-Text `
    -Content $restore `
    -Pattern '(?m)^set -Eeuo pipefail$' `
    -Description "restore script does not enable strict Bash execution."

Require-Text `
    -Content $restore `
    -Pattern '(?m)^umask 077$' `
    -Description "restore script does not enforce umask 077."

Write-Host "PASS D9-GATE-3: strict Bash and restrictive permission contracts pass." `
    -ForegroundColor Green

# ------------------------------------------------------------
# Gate 4 - backup contract
# ------------------------------------------------------------

Require-Text `
    -Content $backup `
    -Pattern 'pg_dump' `
    -Description "backup implementation does not invoke pg_dump."

Require-Text `
    -Content $backup `
    -Pattern '--format=custom' `
    -Description "backup is not PostgreSQL custom format."

Require-Text `
    -Content $backup `
    -Pattern 'pg_restore\s+--list' `
    -Description "backup archive is not structurally validated with pg_restore --list."

Require-Text `
    -Content $backup `
    -Pattern 'sha256sum' `
    -Description "backup implementation does not create SHA-256 evidence."

Require-Text `
    -Content $backup `
    -Pattern '\.partial' `
    -Description "backup does not use a temporary partial artifact."

Require-Text `
    -Content $backup `
    -Pattern 'trap\s+cleanup\s+EXIT' `
    -Description "backup does not clean partial artifacts on failure."

Require-Text `
    -Content $backup `
    -Pattern 'BACKUP PASS' `
    -Description "backup success marker is absent."

Forbid-Text `
    -Content $backup `
    -Pattern '--no-owner' `
    -Description "backup unexpectedly suppresses PostgreSQL ownership metadata."

Forbid-Text `
    -Content $backup `
    -Pattern '--no-acl|--no-privileges' `
    -Description "backup unexpectedly suppresses PostgreSQL privilege metadata."

Write-Host "PASS D9-GATE-4: custom-format backup and integrity contracts pass." `
    -ForegroundColor Green

# ------------------------------------------------------------
# Gate 5 - restore integrity contract
# ------------------------------------------------------------

Require-Text `
    -Content $restore `
    -Pattern 'sha256sum\s+-c' `
    -Description "restore does not validate SHA-256 before recovery."

Require-Text `
    -Content $restore `
    -Pattern 'pg_restore\s+--list' `
    -Description "restore does not validate the archive before mutation."

Require-Text `
    -Content $restore `
    -Pattern '--exit-on-error' `
    -Description "pg_restore is not configured to fail closed."

Require-Text `
    -Content $restore `
    -Pattern 'RESTORE PASS' `
    -Description "restore success marker is absent."

Write-Host "PASS D9-GATE-5: restore integrity and fail-closed contracts pass." `
    -ForegroundColor Green

# ------------------------------------------------------------
# Gate 6 - live source database protection
# ------------------------------------------------------------

Require-Text `
    -Content $restore `
    -Pattern 'meridian_d9_restore' `
    -Description "isolated default D9 restore target is absent."

Forbid-Text `
    -Content $restore `
    -Pattern 'ALLOW_SOURCE_DB_RESTORE' `
    -Description "source-database restore bypass is forbidden."

Forbid-Text `
    -Content $restore `
    -Pattern 'ALLOW_NON_D9_TARGET' `
    -Description "non-D9 restore-target bypass is forbidden."

Require-Text `
    -Content $restore `
    -Pattern 'TARGET_DB.*SOURCE_DB|SOURCE_DB.*TARGET_DB' `
    -Description "restore does not compare target and live source databases."

Require-Text `
    -Content $restore `
    -Pattern 'refusing to restore over live source database' `
    -Description "live source restore refusal is absent."

Require-Text `
    -Content $restore `
    -Pattern 'meridian_d9_\*' `
    -Description "restore target namespace allowlist is absent."

Require-Text `
    -Content $restore `
    -Pattern 'restore target must begin with meridian_d9_' `
    -Description "non-D9 restore-target refusal is absent."

Write-Host "PASS D9-GATE-6: live source database protection passes." `
    -ForegroundColor Green

# ------------------------------------------------------------
# Gate 7 - D8 structural preservation
# ------------------------------------------------------------

foreach ($requiredRelation in @(
    "auth.users",
    "catalog.products",
    "orders.orders"
)) {
    if ($restore -notmatch [regex]::Escape($requiredRelation)) {
        Fail-Gate "restore validation does not require $requiredRelation."
    }
}

foreach ($legacyRelation in @(
    "public.users",
    "public.products",
    "public.orders"
)) {
    if ($restore -notmatch [regex]::Escape($legacyRelation)) {
        Fail-Gate "restore validation does not reject legacy relation $legacyRelation."
    }
}

Write-Host "PASS D9-GATE-7: D8 schema restoration contract passes." `
    -ForegroundColor Green

# ------------------------------------------------------------
# Gate 8 - forbid destructive volume behavior
# ------------------------------------------------------------

$combinedScripts = $backup + "`n" + $restore

Forbid-Text `
    -Content $combinedScripts `
    -Pattern '(?i)docker\s+volume\s+rm' `
    -Description "D9 scripts contain docker volume rm."

Forbid-Text `
    -Content $combinedScripts `
    -Pattern '(?i)docker\s+compose\s+down\s+.*-v' `
    -Description "D9 scripts contain docker compose down -v."

Forbid-Text `
    -Content $combinedScripts `
    -Pattern '(?i)rm\s+-rf\s+.*postgres' `
    -Description "D9 scripts contain destructive PostgreSQL filesystem removal."

Forbid-Text `
    -Content $combinedScripts `
    -Pattern '(?i)meridian-postgres-data.*(?:rm|remove)|(?:rm|remove).*meridian-postgres-data' `
    -Description "D9 scripts attempt to remove the canonical PostgreSQL volume."

Write-Host "PASS D9-GATE-8: canonical PostgreSQL volume destruction is absent." `
    -ForegroundColor Green

# ------------------------------------------------------------
# Gate 9 - no hard-coded password assignment
# ------------------------------------------------------------

Forbid-Text `
    -Content $combinedScripts `
    -Pattern '(?im)^\s*(?:DB_ADMIN_PASSWORD|POSTGRES_PASSWORD)\s*=\s*["''][^$]' `
    -Description "D9 source appears to hard-code a PostgreSQL password."

Require-Text `
    -Content $combinedScripts `
    -Pattern 'POSTGRES_PASSWORD' `
    -Description "container-provided PostgreSQL password contract is absent."

Write-Host "PASS D9-GATE-9: no hard-coded PostgreSQL password contract detected." `
    -ForegroundColor Green

# ------------------------------------------------------------
# Gate 10 - documentation contract
# ------------------------------------------------------------

foreach ($marker in @(
    "pg_dump --format=custom",
    "SHA-256",
    "meridian_d9_restore",
    "no operator bypass",
    "auth.users",
    "catalog.products",
    "orders.orders",
    "meridian-postgres-data",
    "D9 runtime qualification",
    "Production recovery boundary"
)) {
    if ($docs -notmatch [regex]::Escape($marker)) {
        Fail-Gate "backup strategy documentation is missing marker: $marker"
    }
}

Write-Host "PASS D9-GATE-10: backup strategy documentation contract passes." `
    -ForegroundColor Green

# ------------------------------------------------------------
# Gate 11 - repository diff integrity
# ------------------------------------------------------------

Push-Location $RepositoryRoot

try {
    git diff --check

    if ($LASTEXITCODE -ne 0) {
        Fail-Gate "git diff --check failed."
    }
}
finally {
    Pop-Location
}

Write-Host "PASS D9-GATE-11: repository diff integrity passes." `
    -ForegroundColor Green

Write-Host ""
Write-Host "=== MERIDIAN D9 SOURCE QUALIFICATION GATE: PASS ===" `
    -ForegroundColor Green
