$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Write-Host ""
Write-Host "=== MERIDIAN D9 AUTOMATION SOURCE GATE ===" `
    -ForegroundColor Cyan

$RepoRoot = (
    Resolve-Path (
        Join-Path $PSScriptRoot "..\.."
    )
).Path

$ServicePath =
    Join-Path $RepoRoot "ops\systemd\meridian-db-backup.service"

$TimerPath =
    Join-Path $RepoRoot "ops\systemd\meridian-db-backup.timer"

$InstallerPath =
    Join-Path $RepoRoot "ops\systemd\install-d9-backup-systemd.sh"

$DocsPath =
    Join-Path $RepoRoot "docs\backup-strategy.md"

function Fail-Gate {
    param([string]$Message)
    throw "D9-AUTOMATION-GATE FAIL: $Message"
}

function Require-Text {
    param(
        [string]$Content,
        [string]$Pattern,
        [string]$Description
    )

    if ($Content -notmatch $Pattern) {
        Fail-Gate $Description
    }
}

function Forbid-Text {
    param(
        [string]$Content,
        [string]$Pattern,
        [string]$Description
    )

    if ($Content -match $Pattern) {
        Fail-Gate $Description
    }
}

foreach ($Path in @(
    $ServicePath,
    $TimerPath,
    $InstallerPath,
    $DocsPath
)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Fail-Gate "required artifact absent: $Path"
    }

    if ((Get-Item -LiteralPath $Path).Length -eq 0) {
        Fail-Gate "required artifact empty: $Path"
    }
}

foreach ($Path in @(
    $ServicePath,
    $TimerPath,
    $InstallerPath
)) {
    $Bytes = [System.IO.File]::ReadAllBytes($Path)

    if (
        $Bytes.Length -ge 3 -and
        $Bytes[0] -eq 0xEF -and
        $Bytes[1] -eq 0xBB -and
        $Bytes[2] -eq 0xBF
    ) {
        Fail-Gate "$Path contains UTF-8 BOM."
    }

    if ($Bytes -contains 0x0D) {
        Fail-Gate "$Path contains CR/CRLF."
    }
}

$Service =
    Get-Content -LiteralPath $ServicePath -Raw

$Timer =
    Get-Content -LiteralPath $TimerPath -Raw

$Installer =
    Get-Content -LiteralPath $InstallerPath -Raw

$Docs =
    Get-Content -LiteralPath $DocsPath -Raw

# ------------------------------------------------------------
# Service contract
# ------------------------------------------------------------

foreach ($Contract in @(
    @('(?m)^Type=oneshot$', 'service Type=oneshot absent.'),
    @('(?m)^User=ubuntu$', 'service User=ubuntu absent.'),
    @('(?m)^Group=ubuntu$', 'service Group=ubuntu absent.'),
    @('(?m)^SupplementaryGroups=docker$', 'docker group absent.'),
    @('(?m)^WorkingDirectory=/opt/meridian/app$', 'working directory absent.'),
    @('(?m)^Environment=POSTGRES_CONTAINER=meridian-retail-postgres-1$', 'container contract absent.'),
    @('(?m)^Environment=MERIDIAN_ROOT=/opt/meridian$', 'production root absent.'),
    @('(?m)^Environment=BACKUP_DIR=/opt/meridian/backups/d9$', 'backup directory absent.'),
    @('(?m)^ExecStart=/opt/meridian/app/scripts/backup_db\.sh$', 'ExecStart absent.'),
    @('(?m)^UMask=0077$', 'service UMask absent.')
)) {
    Require-Text `
        -Content $Service `
        -Pattern $Contract[0] `
        -Description $Contract[1]
}

# ------------------------------------------------------------
# Timer contract
# ------------------------------------------------------------

foreach ($Contract in @(
    @('(?m)^OnCalendar=daily$', 'daily schedule absent.'),
    @('(?m)^Persistent=true$', 'Persistent=true absent.'),
    @('(?m)^Unit=meridian-db-backup\.service$', 'timer service absent.'),
    @('(?m)^WantedBy=timers\.target$', 'timer install target absent.')
)) {
    Require-Text `
        -Content $Timer `
        -Pattern $Contract[0] `
        -Description $Contract[1]
}

# ------------------------------------------------------------
# Installer path-composition contract
# ------------------------------------------------------------

foreach ($Contract in @(
    @(
        '(?m)^PRODUCTION_APP="/opt/meridian/app"$',
        'installer PRODUCTION_APP contract absent.'
    ),
    @(
        '(?m)^PRODUCTION_SCRIPT_DIR="\$\{PRODUCTION_APP\}/scripts"$',
        'installer PRODUCTION_SCRIPT_DIR composition absent.'
    ),
    @(
        '(?m)^PRODUCTION_BACKUP_SCRIPT="\$\{PRODUCTION_SCRIPT_DIR\}/backup_db\.sh"$',
        'installer backup-script composition absent.'
    ),
    @(
        '(?m)^PRODUCTION_BACKUP_DIR="/opt/meridian/backups/d9"$',
        'installer backup-directory contract absent.'
    ),
    @(
        '(?m)^SERVICE_TARGET="/etc/systemd/system/meridian-db-backup\.service"$',
        'installer service target absent.'
    ),
    @(
        '(?m)^TIMER_TARGET="/etc/systemd/system/meridian-db-backup\.timer"$',
        'installer timer target absent.'
    ),
    @(
        '(?m)^systemctl daemon-reload$',
        'installer daemon-reload absent.'
    ),
    @(
        '(?m)^systemctl enable meridian-db-backup\.timer$',
        'installer timer enable absent.'
    )
)) {
    Require-Text `
        -Content $Installer `
        -Pattern $Contract[0] `
        -Description $Contract[1]
}

# ------------------------------------------------------------
# Installer safety contract
# ------------------------------------------------------------

Require-Text `
    -Content $Installer `
    -Pattern '(?m)^set -Eeuo pipefail$' `
    -Description "installer strict Bash contract absent."

Require-Text `
    -Content $Installer `
    -Pattern '(?m)^umask 077$' `
    -Description "installer restrictive umask absent."

Forbid-Text `
    -Content $Installer `
    -Pattern '(?m)^umask 022$' `
    -Description "installer must not use umask 022."

Require-Text `
    -Content $Installer `
    -Pattern '(?m)^primary_group="\$\(id -gn ubuntu\)"$' `
    -Description "installer ubuntu primary-group discovery absent."

Require-Text `
    -Content $Installer `
    -Pattern '(?m)^\[\[ "\$\{primary_group\}" == "ubuntu" \]\] \|\|$' `
    -Description "installer ubuntu primary-group guard absent."

Require-Text `
    -Content $Installer `
    -Pattern '(?m)^\[\[ ! -e "\$\{PRODUCTION_BACKUP_SCRIPT\}" \]\] \|\|$' `
    -Description "installer production backup target guard absent."

Require-Text `
    -Content $Installer `
    -Pattern 'production backup script target already exists:' `
    -Description "installer production backup target fail message absent."

$BackupGuardMatch =
    [regex]::Match(
        $Installer,
        '(?m)^\[\[ ! -e "\$\{PRODUCTION_BACKUP_SCRIPT\}" \]\] \|\|$'
    )

$ServiceGuardMatch =
    [regex]::Match(
        $Installer,
        '(?m)^\[\[ ! -e "\$\{SERVICE_TARGET\}" \]\] \|\|$'
    )

$TimerGuardMatch =
    [regex]::Match(
        $Installer,
        '(?m)^\[\[ ! -e "\$\{TIMER_TARGET\}" \]\] \|\|$'
    )

$FirstInstallMatch =
    [regex]::Match(
        $Installer,
        '(?m)^install \\$'
    )

if (-not $FirstInstallMatch.Success) {
    Fail-Gate "installer first write operation cannot be located."
}

foreach ($Guard in @(
    $BackupGuardMatch,
    $ServiceGuardMatch,
    $TimerGuardMatch
)) {
    if (-not $Guard.Success) {
        Fail-Gate "installer target guard cannot be located."
    }

    if ($Guard.Index -ge $FirstInstallMatch.Index) {
        Fail-Gate "installer target guard occurs after first write."
    }
}
Forbid-Text `
    -Content $Installer `
    -Pattern '(?i)systemctl\s+enable\s+--now\s+meridian-db-backup\.timer' `
    -Description "installer must not use enable --now."

Forbid-Text `
    -Content $Installer `
    -Pattern '(?i)systemctl\s+(?:start|restart)\s+meridian-db-backup\.(?:timer|service)' `
    -Description "installer must not start/restart backup automation."

# ------------------------------------------------------------
# Documentation contract
# ------------------------------------------------------------

foreach ($Marker in @(
    "meridian-db-backup.service",
    "meridian-db-backup.timer",
    "OnCalendar=daily",
    "Persistent=true",
    "/opt/meridian",
    "/opt/meridian/backups/d9"
)) {
    if ($Docs -notmatch [regex]::Escape($Marker)) {
        Fail-Gate "documentation marker absent: $Marker"
    }
}

Push-Location $RepoRoot

try {
    git diff --check

    if ($LASTEXITCODE -ne 0) {
        Fail-Gate "git diff --check failed."
    }
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "PASS D9-AUTOMATION-GATE: daily systemd source contract passes." `
    -ForegroundColor Green

Write-Host "=== MERIDIAN D9 AUTOMATION SOURCE GATE: PASS ===" `
    -ForegroundColor Green
