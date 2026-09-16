$ErrorActionPreference = "Stop"

$Base =
    "cbf8a24e78abea6f74f9a3fe380e706a1eaea05e"

$ImmutableFiles = @{
    "auth-service/main.py" =
        "7d716ab7376f46ee1e6a81fb0e609e7a8fc902f6f745266225d2d188d0a32ec5"

    "catalog-service/app.js" =
        "c7ca4f020f1fdc5d2f011b3202d162317f3f0836e937a33989b9d7020fab0ab2"

    "orders-service/main.py" =
        "4ef19748860c36a73025e0415cccea83dfd7b98d277528c53c4516742dc29921"
}

$AllowedChanges = @(
    "ops/database/apply-d8-least-privilege.sh",
    "ops/database/apply-d8-rollback.sh",
    "ops/database/bootstrap-d8-least-privilege.sql",
    "ops/database/rollback-d8-least-privilege.sql",
    "ops/deployment/.env.production.example",
    "ops/deployment/docker-compose.production.yml",
    "ops/validation/Invoke-MeridianD8SourceGate.ps1"
)


function Get-D8ChangedPaths {

    @(
        (
            git diff `
                --name-only `
                $Base
        )

        (
            git ls-files `
                --others `
                --exclude-standard
        )
    ) |
    Where-Object {
        $_
    } |
    ForEach-Object {
        $_.Replace('\','/')
    } |
    Sort-Object -Unique
}


function Require-Text {

    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $Text =
        Get-Content `
            -LiteralPath $Path `
            -Raw

    if ($Text -notmatch $Pattern) {
        throw (
            "D8-SOURCE-GATE FAIL: " +
            $Message
        )
    }
}


function Reject-Text {

    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $Text =
        Get-Content `
            -LiteralPath $Path `
            -Raw

    if ($Text -match $Pattern) {
        throw (
            "D8-SOURCE-GATE FAIL: " +
            $Message
        )
    }
}


# ============================================================
# A. REQUIRED D8 FILES
# ============================================================

foreach ($Path in $AllowedChanges) {

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw (
            "D8-SOURCE-GATE FAIL: required D8 file missing: " +
            $Path
        )
    }
}


# ============================================================
# B. PRE-BUILT APPLICATION IMMUTABILITY
# ============================================================

foreach ($Entry in $ImmutableFiles.GetEnumerator()) {

    $Observed =
        (
            Get-FileHash `
                -LiteralPath $Entry.Key `
                -Algorithm SHA256
        ).Hash.ToLowerInvariant()

    if ($Observed -ne $Entry.Value) {
        throw (
            "D8-SOURCE-GATE FAIL: immutable application changed: " +
            $Entry.Key
        )
    }
}


# ============================================================
# C. HISTORICAL STAGE-6 ARTIFACTS MUST REMAIN UNCHANGED
# ============================================================

foreach ($Historical in @(
    "ops/validation/Invoke-MeridianStage6Gate.ps1",
    "ops/validation/stage6-invariants.json"
)) {

    $HistoricalDiff =
        @(
            git diff `
                --name-only `
                $Base `
                -- `
                $Historical
        )

    if ($HistoricalDiff.Count -ne 0) {
        throw (
            "D8-SOURCE-GATE FAIL: historical Stage-6 artifact changed: " +
            $Historical
        )
    }
}


# ============================================================
# D. EXACT SEVEN-FILE CHANGESET
# ============================================================

$Changed =
    @(Get-D8ChangedPaths)

$Unexpected =
    @(
        $Changed |
        Where-Object {
            $_ -notin $AllowedChanges
        }
    )

if ($Unexpected.Count -ne 0) {

    foreach ($Path in $Unexpected) {
        Write-Host "UNEXPECTED_D8_CHANGE=$Path"
    }

    throw (
        "D8-SOURCE-GATE FAIL: changeset exceeds D8 allowlist."
    )
}

foreach ($Path in $AllowedChanges) {

    if ($Path -notin $Changed) {
        throw (
            "D8-SOURCE-GATE FAIL: expected D8 artifact absent from changeset: " +
            $Path
        )
    }
}


# ============================================================
# E. ENVIRONMENT TEMPLATE CONTRACT
# ============================================================

$EnvTemplate =
    "ops/deployment/.env.production.example"

foreach ($Pattern in @(
    '(?m)^DB_NAME=meridian_db$',
    '(?m)^DB_ADMIN_USER=meridian$',
    '(?m)^DB_ADMIN_PASSWORD=',
    '(?m)^AUTH_DB_USER=meridian_auth_app$',
    '(?m)^AUTH_DB_PASSWORD=',
    '(?m)^CATALOG_DB_USER=meridian_catalog_app$',
    '(?m)^CATALOG_DB_PASSWORD=',
    '(?m)^ORDERS_DB_USER=meridian_orders_app$',
    '(?m)^ORDERS_DB_PASSWORD=',
    '(?m)^JWT_SECRET=',
    '(?m)^JWT_EXPIRY_MINUTES=60$'
)) {

    Require-Text `
        -Path $EnvTemplate `
        -Pattern $Pattern `
        -Message (
            "environment template missing contract: " +
            $Pattern
        )
}

foreach ($Pattern in @(
    '(?m)^DB_USER=',
    '(?m)^DB_PASSWORD='
)) {

    Reject-Text `
        -Path $EnvTemplate `
        -Pattern $Pattern `
        -Message (
            "legacy shared runtime credential remains in environment template: " +
            $Pattern
        )
}


# ============================================================
# F. COMPOSE RENDER
#
# Controlled process environment is used rather than a nested
# validation here-string.
# ============================================================

$ValidationEnvironment = [ordered]@{
    "DB_NAME"               = "meridian_validation"
    "DB_ADMIN_USER"         = "meridian"
    "DB_ADMIN_PASSWORD"     = "admin-validation-placeholder"
    "AUTH_DB_USER"          = "meridian_auth_app"
    "AUTH_DB_PASSWORD"      = "auth-validation-placeholder"
    "CATALOG_DB_USER"       = "meridian_catalog_app"
    "CATALOG_DB_PASSWORD"   = "catalog-validation-placeholder"
    "ORDERS_DB_USER"        = "meridian_orders_app"
    "ORDERS_DB_PASSWORD"    = "orders-validation-placeholder"
    "JWT_SECRET"            = "jwt-validation-placeholder"
    "JWT_EXPIRY_MINUTES"    = "60"
    "ECR_REGISTRY"          = "example.invalid"
    "IMAGE_TAG"             = ("a" * 40)
}

$PriorEnvironment = @{}

foreach ($Key in $ValidationEnvironment.Keys) {

    $PriorEnvironment[$Key] =
        [Environment]::GetEnvironmentVariable(
            $Key,
            "Process"
        )
}

try {

    foreach ($Key in $ValidationEnvironment.Keys) {

        [Environment]::SetEnvironmentVariable(
            $Key,
            $ValidationEnvironment[$Key],
            "Process"
        )
    }


    $SavedErrorActionPreference =
        $ErrorActionPreference

    try {

        $ErrorActionPreference = "Continue"

        $ComposeOutput =
            @(
                & docker compose `
                    -f "ops/deployment/docker-compose.production.yml" `
                    config `
                    --format json `
                    2>&1
            )

        $ComposeExit =
            $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference =
            $SavedErrorActionPreference
    }


    if ($ComposeExit -ne 0) {

        foreach ($Line in $ComposeOutput) {
            Write-Host $Line
        }

        throw (
            "D8-SOURCE-GATE FAIL: production Compose does not render."
        )
    }


    $ComposeText =
        (
            $ComposeOutput |
            ForEach-Object {
                $_.ToString()
            }
        ) -join "`n"


    $Config =
        $ComposeText |
        ConvertFrom-Json


    if (
        [string]$Config.services.postgres.environment.POSTGRES_USER -ne
            "meridian"
    ) {
        throw (
            "D8-SOURCE-GATE FAIL: PostgreSQL admin identity is incorrect."
        )
    }


    if (
        [string]$Config.services.'auth-service'.environment.DB_USER -ne
            "meridian_auth_app" -or

        [string]$Config.services.'catalog-service'.environment.DB_USER -ne
            "meridian_catalog_app" -or

        [string]$Config.services.'orders-service'.environment.DB_USER -ne
            "meridian_orders_app"
    ) {
        throw (
            "D8-SOURCE-GATE FAIL: application runtime identities are not separated."
        )
    }


    if (
        $Config.services.'auth-service'.environment.DB_USER -eq
            $Config.services.postgres.environment.POSTGRES_USER -or

        $Config.services.'catalog-service'.environment.DB_USER -eq
            $Config.services.postgres.environment.POSTGRES_USER -or

        $Config.services.'orders-service'.environment.DB_USER -eq
            $Config.services.postgres.environment.POSTGRES_USER
    ) {
        throw (
            "D8-SOURCE-GATE FAIL: an application still uses the PostgreSQL admin identity."
        )
    }


    if ($null -ne $Config.services.postgres.ports) {
        throw (
            "D8-SOURCE-GATE FAIL: PostgreSQL unexpectedly publishes a host port."
        )
    }


    if (
        [string]$Config.volumes.postgres_data.name -ne
            "meridian-postgres-data"
    ) {
        throw (
            "D8-SOURCE-GATE FAIL: canonical PostgreSQL volume changed."
        )
    }


    if (
        [string]$Config.networks.'meridian-net'.name -ne
            "meridian-net"
    ) {
        throw (
            "D8-SOURCE-GATE FAIL: canonical network changed."
        )
    }
}
finally {

    foreach ($Key in $ValidationEnvironment.Keys) {

        [Environment]::SetEnvironmentVariable(
            $Key,
            $PriorEnvironment[$Key],
            "Process"
        )
    }
}


# ============================================================
# G. FORWARD SQL CONTRACT
# ============================================================

$Forward =
    "ops/database/bootstrap-d8-least-privilege.sql"

foreach ($Pattern in @(
    'NOSUPERUSER',
    'NOCREATEDB',
    'NOCREATEROLE',
    'NOREPLICATION',
    'NOBYPASSRLS',
    'CREATE SCHEMA IF NOT EXISTS auth',
    'CREATE SCHEMA IF NOT EXISTS catalog',
    'CREATE SCHEMA IF NOT EXISTS orders',
    'ALTER TABLE public\.users\s+SET SCHEMA auth',
    'ALTER TABLE public\.products\s+SET SCHEMA catalog',
    'ALTER TABLE public\.orders\s+SET SCHEMA orders',
    'SET search_path = auth, pg_catalog',
    'SET search_path = catalog, pg_catalog',
    'SET search_path = orders, pg_catalog',
    'REVOKE ALL\s+ON DATABASE',
    'GRANT CONNECT',
    'GRANT SELECT, INSERT'
)) {

    Require-Text `
        -Path $Forward `
        -Pattern $Pattern `
        -Message (
            "forward SQL contract missing: " +
            $Pattern
        )
}

foreach ($Pattern in @(
    '(?i)\bDROP\s+DATABASE\b',
    '(?i)\bDROP\s+TABLE\b',
    '(?i)\bDROP\s+SCHEMA\b',
    '(?i)\bDROP\s+ROLE\b',
    '(?i)\bTRUNCATE\b',
    '(?i)\bDELETE\s+FROM\b'
)) {

    Reject-Text `
        -Path $Forward `
        -Pattern $Pattern `
        -Message (
            "forward SQL contains forbidden destructive statement: " +
            $Pattern
        )
}


# ============================================================
# H. FORWARD RUNNER
# ============================================================

$ForwardRunner =
    "ops/database/apply-d8-least-privilege.sh"

foreach ($Pattern in @(
    'DB_ADMIN_USER',
    'AUTH_DB_USER',
    'AUTH_DB_PASSWORD',
    'CATALOG_DB_USER',
    'CATALOG_DB_PASSWORD',
    'ORDERS_DB_USER',
    'ORDERS_DB_PASSWORD',
    'meridian-retail-postgres-1',
    'ON_ERROR_STOP=1',
    'MERIDIAN_D8_LEAST_PRIVILEGE_BOOTSTRAP=SUCCESS'
)) {

    Require-Text `
        -Path $ForwardRunner `
        -Pattern $Pattern `
        -Message (
            "forward runner contract missing: " +
            $Pattern
        )
}

foreach ($Pattern in @(
    '(?i)docker\s+rm',
    '(?i)docker\s+volume\s+rm',
    '(?i)docker\s+compose\s+down',
    '(?i)\brm\s+-rf\b'
)) {

    Reject-Text `
        -Path $ForwardRunner `
        -Pattern $Pattern `
        -Message (
            "forward runner contains forbidden cleanup operation: " +
            $Pattern
        )
}


# ============================================================
# I. ROLLBACK SQL CONTRACT
# ============================================================

$Rollback =
    "ops/database/rollback-d8-least-privilege.sql"

foreach ($Pattern in @(
    'ALTER TABLE auth\.users\s+SET SCHEMA public',
    'ALTER TABLE catalog\.products\s+SET SCHEMA public',
    'ALTER TABLE orders\.orders\s+SET SCHEMA public',
    'RESET search_path',
    'REVOKE ALL PRIVILEGES\s+ON DATABASE',
    'public\.products_id_seq',
    'both public\.users and auth\.users exist',
    'both public\.products and catalog\.products exist',
    'both public\.orders and orders\.orders exist'
)) {

    Require-Text `
        -Path $Rollback `
        -Pattern $Pattern `
        -Message (
            "rollback SQL contract missing: " +
            $Pattern
        )
}

foreach ($Pattern in @(
    '(?i)\bDROP\s+DATABASE\b',
    '(?i)\bDROP\s+TABLE\b',
    '(?i)\bDROP\s+SCHEMA\b',
    '(?i)\bDROP\s+ROLE\b',
    '(?i)\bTRUNCATE\b',
    '(?i)\bDELETE\s+FROM\b'
)) {

    Reject-Text `
        -Path $Rollback `
        -Pattern $Pattern `
        -Message (
            "rollback SQL contains forbidden destructive statement: " +
            $Pattern
        )
}


# ============================================================
# J. ROLLBACK RUNNER GUARDS
# ============================================================

$RollbackRunner =
    "ops/database/apply-d8-rollback.sh"

foreach ($Pattern in @(
    'MERIDIAN_D8_ROLLBACK_CONFIRM',
    'ROLLBACK_D8_DATABASE_TO_PUBLIC_SCHEMA',
    'meridian-retail-auth-service-1',
    'meridian-retail-catalog-service-1',
    'meridian-retail-orders-service-1',
    'application container is still running',
    'meridian-retail-postgres-1',
    'State\.Health\.Status',
    'ON_ERROR_STOP=1',
    'MERIDIAN_D8_DATABASE_ROLLBACK=SUCCESS'
)) {

    Require-Text `
        -Path $RollbackRunner `
        -Pattern $Pattern `
        -Message (
            "rollback runner guard missing: " +
            $Pattern
        )
}

foreach ($Pattern in @(
    '(?i)docker\s+rm',
    '(?i)docker\s+volume\s+rm',
    '(?i)docker\s+compose\s+down',
    '(?i)\brm\s+-rf\b'
)) {

    Reject-Text `
        -Path $RollbackRunner `
        -Pattern $Pattern `
        -Message (
            "rollback runner contains forbidden cleanup operation: " +
            $Pattern
        )
}


Write-Host ""
Write-Host `
    "PASS D8-SOURCE-GATE: seven-file least-privilege + rollback contract is valid." `
    -ForegroundColor Green