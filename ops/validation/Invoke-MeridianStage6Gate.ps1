$ErrorActionPreference = "Stop"

$ComposeRel = "ops/deployment/docker-compose.production.yml"
$DeployRel = "ops/deployment/deploy-production.sh"
$EnvRel = "ops/deployment/.env.production.example"
$InvariantRel = "ops/validation/stage6-invariants.json"

$RootOutput = @(git rev-parse --show-toplevel)
$RootExit = $LASTEXITCODE

if ($RootExit -ne 0) {
    throw "BLOCKED STAGE6-GATE: cannot determine repository root."
}

if ($RootOutput.Count -ne 1) {
    throw "BLOCKED STAGE6-GATE: unexpected repository-root result."
}

$Root = $RootOutput[0].Trim()

$ComposePath = Join-Path $Root $ComposeRel
$DeployPath = Join-Path $Root $DeployRel
$EnvPath = Join-Path $Root $EnvRel
$InvariantPath = Join-Path $Root $InvariantRel
$RealEnvPath = Join-Path $Root "ops/deployment/.env.production"

foreach ($Path in @(
    $ComposePath,
    $DeployPath,
    $EnvPath,
    $InvariantPath
)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "BLOCKED STAGE6-GATE: required Stage 6 contract file is absent."
    }
}


# ============================================================
# 1. MIR COVERAGE
# ============================================================

try {
    $RegistryText = Get-Content -LiteralPath $InvariantPath -Raw
    $Registry = $RegistryText | ConvertFrom-Json
}
catch {
    throw "BLOCKED STAGE6-GATE: invariant registry is invalid."
}

$Coverage = @($Registry.mir_coverage)

if ($Coverage.Count -ne 26) {
    throw "BLOCKED STAGE6-GATE: MIR-001 through MIR-026 coverage is incomplete."
}

$Unknown = @(
    $Coverage |
    Where-Object {
        [string]$_.applicability -eq "unknown"
    }
)

if ($Unknown.Count -ne 0) {
    throw "BLOCKED STAGE6-GATE: unknown MIR applicability exists."
}

$MissingControls = @(
    $Coverage |
    Where-Object {
        [string]$_.applicability -eq "applicable" -and
        [string]::IsNullOrWhiteSpace([string]$_.control)
    }
)

if ($MissingControls.Count -ne 0) {
    throw "BLOCKED STAGE6-GATE: applicable MIR control is missing."
}

Write-Host "PASS STAGE6-GATE-1: MIR-001 through MIR-026 coverage contains no unknown or uncontrolled applicable rule." -ForegroundColor Green


# ============================================================
# 2. APPLICATION BUILD CONTEXTS
# ============================================================

$ApplicationStatus = @(
    git status --porcelain -- auth-service catalog-service orders-service frontend
)
$ApplicationStatusExit = $LASTEXITCODE

if ($ApplicationStatusExit -ne 0) {
    throw "BLOCKED STAGE6-GATE: cannot inspect application build contexts."
}

if ($ApplicationStatus.Count -ne 0) {
    throw "BLOCKED STAGE6-GATE: application build context is dirty."
}

Write-Host "PASS STAGE6-GATE-2: application build contexts are clean." -ForegroundColor Green


# ============================================================
# 3. CONFIGURATION-SOURCE HIERARCHY
# ============================================================

if (Test-Path -LiteralPath $RealEnvPath) {
    throw "BLOCKED STAGE6-GATE: real production environment file exists inside repository."
}

$ExpectedRuntimeKeys = @(
    "DB_NAME",
    "DB_USER",
    "DB_PASSWORD",
    "JWT_SECRET",
    "JWT_EXPIRY_MINUTES"
)

$EnvLines = @(Get-Content -LiteralPath $EnvPath)

$EnvKeys = @(
    $EnvLines |
    ForEach-Object {
        if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=') {
            $Matches[1]
        }
    } |
    Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    }
)

if ($EnvKeys.Count -ne 5) {
    throw "BLOCKED STAGE6-GATE: runtime environment key count changed."
}

$EnvDifference = @(
    Compare-Object `
      -ReferenceObject ($ExpectedRuntimeKeys | Sort-Object) `
      -DifferenceObject ($EnvKeys | Sort-Object)
)

if ($EnvDifference.Count -ne 0) {
    throw "BLOCKED STAGE6-GATE: runtime environment schema changed."
}

if ($EnvKeys -contains "ECR_REGISTRY") {
    throw "BLOCKED STAGE6-GATE: ECR_REGISTRY leaked into runtime env schema."
}

if ($EnvKeys -contains "IMAGE_TAG") {
    throw "BLOCKED STAGE6-GATE: IMAGE_TAG leaked into runtime env schema."
}

Write-Host "PASS STAGE6-GATE-3: configuration-source hierarchy remains exact." -ForegroundColor Green


# ============================================================
# 4. SOURCE DEPLOYMENT CONTRACTS
# ============================================================

$ComposeText = [System.IO.File]::ReadAllText($ComposePath).Replace("`r`n", "`n")
$DeployText = [System.IO.File]::ReadAllText($DeployPath).Replace("`r`n", "`n")

$ApplicationImagePatterns = @(
    'image: ${ECR_REGISTRY:?ECR_REGISTRY is required}/meridian/auth:${IMAGE_TAG:?IMAGE_TAG is required}',
    'image: ${ECR_REGISTRY:?ECR_REGISTRY is required}/meridian/catalog:${IMAGE_TAG:?IMAGE_TAG is required}',
    'image: ${ECR_REGISTRY:?ECR_REGISTRY is required}/meridian/orders:${IMAGE_TAG:?IMAGE_TAG is required}',
    'image: ${ECR_REGISTRY:?ECR_REGISTRY is required}/meridian/frontend:${IMAGE_TAG:?IMAGE_TAG is required}'
)

foreach ($Pattern in $ApplicationImagePatterns) {
    $Count = [regex]::Matches(
        $ComposeText,
        [regex]::Escape($Pattern)
    ).Count

    if ($Count -ne 1) {
        throw "BLOCKED STAGE6-GATE: application image interpolation contract changed."
    }
}

$PostgresDigestCount = [regex]::Matches(
    $ComposeText,
    '(?m)^\s*image:\s*(?:docker\.io/library/)?postgres@sha256:[0-9a-f]{64}\s*$'
).Count

if ($PostgresDigestCount -ne 1) {
    throw "BLOCKED STAGE6-GATE: PostgreSQL is not pinned to exactly one immutable digest."
}

$PlatformCount = [regex]::Matches(
    $ComposeText,
    '(?m)^\s*platform:\s*linux/amd64\s*$'
).Count

if ($PlatformCount -ne 5) {
    throw "BLOCKED STAGE6-GATE: all five runtime services are not explicitly linux/amd64."
}

$FullShaContract = 'if [[ ! "${IMAGE_TAG}" =~ ^[0-9a-f]{40}$ ]]; then'

if (-not $DeployText.Contains($FullShaContract)) {
    throw "BLOCKED STAGE6-GATE: deploy script does not require full 40-character SHA."
}

if ($DeployText.Contains('^[0-9a-f]{7,40}$')) {
    throw "BLOCKED STAGE6-GATE: abbreviated SHA acceptance returned."
}

if (-not $DeployText.Contains("    pull \`n    --policy always")) {
    throw "BLOCKED STAGE6-GATE: explicit image acquisition contract is absent."
}

if (-not $DeployText.Contains("    --no-build \`n    --pull never \`n    --remove-orphans \")) {
    throw "BLOCKED STAGE6-GATE: deployment start is not build/pull disabled."
}

if (-not $DeployText.Contains('trap cleanup_ecr_login EXIT')) {
    throw "BLOCKED STAGE6-GATE: ECR login EXIT cleanup is absent."
}

if (-not $DeployText.Contains('docker logout "${ECR_REGISTRY}"')) {
    throw "BLOCKED STAGE6-GATE: ECR logout contract is absent."
}

$DockerExecCount = [regex]::Matches(
    $DeployText,
    '(?m)^\s*docker\s+exec\b'
).Count

if ($DockerExecCount -ne 0) {
    throw "BLOCKED STAGE6-GATE: unreviewed docker exec dependency exists."
}

Write-Host "PASS STAGE6-GATE-4: immutable image, full-SHA, platform, acquisition, start, and registry-cleanup source contracts pass." -ForegroundColor Green


# ============================================================
# 5. FRONTEND HEALTHCHECK SOURCE CONTRACT
# ============================================================

$FrontendHealthSource = @(
    '          "CMD",',
    '          "/busybox",',
    '          "wget",',
    '          "-q",',
    '          "-O",',
    '          "/dev/null",',
    '          "http://127.0.0.1/"'
)

foreach ($HealthLine in $FrontendHealthSource) {
    if (-not $ComposeText.Contains($HealthLine)) {
        throw "BLOCKED STAGE6-GATE: shell-free frontend healthcheck source contract is incomplete."
    }
}

$FrontendSectionMatch = [regex]::Match(
    $ComposeText,
    '(?ms)^\s{2}frontend:\s*\n(.*?)(?=^\S|\z)'
)

if (-not $FrontendSectionMatch.Success) {
    throw "BLOCKED STAGE6-GATE: frontend Compose section cannot be isolated."
}

$FrontendSection = $FrontendSectionMatch.Value

if ($FrontendSection.Contains('"CMD-SHELL"')) {
    throw "BLOCKED STAGE6-GATE: frontend healthcheck still depends on a shell."
}

Write-Host "PASS STAGE6-GATE-5: frontend healthcheck source contract is shell-free BusyBox exec form." -ForegroundColor Green


# ============================================================
# 6. RENDER COMPOSE SEMANTICS
# ============================================================

$TempEnv = Join-Path `
  ([System.IO.Path]::GetTempPath()) `
  ("meridian-stage6-validation-" + [guid]::NewGuid().ToString("N") + ".env")

$PriorRegistry = [Environment]::GetEnvironmentVariable("ECR_REGISTRY", "Process")
$PriorImageTag = [Environment]::GetEnvironmentVariable("IMAGE_TAG", "Process")

$ConfigObject = $null
$RenderSucceeded = $false

$ValidationLines = @(
    "DB_NAME=meridian_validation",
    "DB_USER=meridian_validation",
    "DB_PASSWORD=validation-only-placeholder",
    "JWT_SECRET=validation-only-placeholder",
    "JWT_EXPIRY_MINUTES=60"
)

try {
    [System.IO.File]::WriteAllText(
        $TempEnv,
        (($ValidationLines -join "`n") + "`n"),
        (New-Object System.Text.UTF8Encoding($false))
    )

    [Environment]::SetEnvironmentVariable(
        "ECR_REGISTRY",
        "example.invalid",
        "Process"
    )

    [Environment]::SetEnvironmentVariable(
        "IMAGE_TAG",
        "0000000000000000000000000000000000000000",
        "Process"
    )

    $ConfigJson = @(
        docker compose `
          --env-file $TempEnv `
          -f $ComposePath `
          config `
          --format json
    )

    $ConfigExit = $LASTEXITCODE

    if ($ConfigExit -ne 0) {
        throw "BLOCKED STAGE6-GATE: production Compose render failed."
    }

    if ($ConfigJson.Count -eq 0) {
        throw "BLOCKED STAGE6-GATE: production Compose render returned no configuration."
    }

    try {
        $ConfigObject = ($ConfigJson -join "`n") | ConvertFrom-Json
    }
    catch {
        throw "BLOCKED STAGE6-GATE: rendered Compose JSON cannot be parsed."
    }

    if ($null -eq $ConfigObject) {
        throw "BLOCKED STAGE6-GATE: rendered Compose object is null."
    }

    $RenderSucceeded = $true
}
finally {
    [Environment]::SetEnvironmentVariable(
        "ECR_REGISTRY",
        $PriorRegistry,
        "Process"
    )

    [Environment]::SetEnvironmentVariable(
        "IMAGE_TAG",
        $PriorImageTag,
        "Process"
    )

    if (Test-Path -LiteralPath $TempEnv) {
        Remove-Item `
          -LiteralPath $TempEnv `
          -Force `
          -ErrorAction SilentlyContinue
    }
}

if (-not $RenderSucceeded) {
    throw "BLOCKED STAGE6-GATE: Compose semantic render did not reach PASS."
}

if (Test-Path -LiteralPath $TempEnv) {
    throw "BLOCKED STAGE6-GATE: temporary Compose validation file remains."
}

Write-Host "PASS STAGE6-GATE-6: production Compose renders and temporary validation state is cleaned." -ForegroundColor Green


# ============================================================
# 7. EXACT FIVE-SERVICE TOPOLOGY
# ============================================================

$ExpectedServices = @(
    "auth-service",
    "catalog-service",
    "frontend",
    "orders-service",
    "postgres"
)

$ActualServices = @(
    $ConfigObject.services.PSObject.Properties.Name |
    Sort-Object
)

if ($ActualServices.Count -ne 5) {
    throw "BLOCKED STAGE6-GATE: rendered service count is not five."
}

$ServiceDifference = @(
    Compare-Object `
      -ReferenceObject $ExpectedServices `
      -DifferenceObject $ActualServices
)

if ($ServiceDifference.Count -ne 0) {
    throw "BLOCKED STAGE6-GATE: rendered service topology changed."
}

foreach ($ServiceName in @(
    "auth-service",
    "catalog-service",
    "orders-service",
    "frontend"
)) {
    $ServiceProperty = $ConfigObject.services.PSObject.Properties[$ServiceName]

    if ($null -eq $ServiceProperty) {
        throw "BLOCKED STAGE6-GATE: expected application service is absent."
    }

    $Service = $ServiceProperty.Value

    if ($Service.PSObject.Properties.Name -contains "build") {
        throw "BLOCKED STAGE6-GATE: production application service contains build configuration."
    }

    if ([string]$Service.platform -ne "linux/amd64") {
        throw "BLOCKED STAGE6-GATE: application runtime platform changed."
    }
}

$PostgresProperty = $ConfigObject.services.PSObject.Properties["postgres"]

if ($null -eq $PostgresProperty) {
    throw "BLOCKED STAGE6-GATE: PostgreSQL service is absent."
}

$Postgres = $PostgresProperty.Value

if ([string]$Postgres.platform -ne "linux/amd64") {
    throw "BLOCKED STAGE6-GATE: PostgreSQL runtime platform changed."
}

if (
    [string]$Postgres.image -notmatch
    '^(?:docker\.io/library/)?postgres@sha256:[0-9a-f]{64}$'
) {
    throw "BLOCKED STAGE6-GATE: rendered PostgreSQL image is not immutable."
}

Write-Host "PASS STAGE6-GATE-7: rendered topology, image-only deployment, platforms, and PostgreSQL identity pass." -ForegroundColor Green


# ============================================================
# 8. PORT / RESOURCE CONTRACTS
# ============================================================

$PortContracts = @(
    [pscustomobject]@{ Service="auth-service"; Published=8001; Target=8000 },
    [pscustomobject]@{ Service="catalog-service"; Published=8002; Target=4000 },
    [pscustomobject]@{ Service="orders-service"; Published=8003; Target=8001 },
    [pscustomobject]@{ Service="frontend"; Published=8080; Target=80 }
)

foreach ($Contract in $PortContracts) {
    $Property = $ConfigObject.services.PSObject.Properties[$Contract.Service]

    if ($null -eq $Property) {
        throw "BLOCKED STAGE6-GATE: expected service is absent from port validation."
    }

    $Service = $Property.Value

    if ($Service.PSObject.Properties.Name -notcontains "ports") {
        throw "BLOCKED STAGE6-GATE: required loopback mapping is absent."
    }

    $Ports = @($Service.ports)

    if ($Ports.Count -ne 1) {
        throw "BLOCKED STAGE6-GATE: unexpected application port count."
    }

    if ([string]$Ports[0].host_ip -ne "127.0.0.1") {
        throw "BLOCKED STAGE6-GATE: application port is not loopback-bound."
    }

    if ([int]$Ports[0].published -ne $Contract.Published) {
        throw "BLOCKED STAGE6-GATE: published application port changed."
    }

    if ([int]$Ports[0].target -ne $Contract.Target) {
        throw "BLOCKED STAGE6-GATE: container application port changed."
    }
}

if ($Postgres.PSObject.Properties.Name -contains "ports") {
    throw "BLOCKED STAGE6-GATE: PostgreSQL exposes a host port."
}

$NetworkProperty = $ConfigObject.networks.PSObject.Properties["meridian-net"]

if ($null -eq $NetworkProperty) {
    throw "BLOCKED STAGE6-GATE: canonical network is absent."
}

if ([string]$NetworkProperty.Value.name -ne "meridian-net") {
    throw "BLOCKED STAGE6-GATE: canonical network name changed."
}

$VolumeProperty = $ConfigObject.volumes.PSObject.Properties["postgres_data"]

if ($null -eq $VolumeProperty) {
    throw "BLOCKED STAGE6-GATE: PostgreSQL volume definition is absent."
}

if ([string]$VolumeProperty.Value.name -ne "meridian-postgres-data") {
    throw "BLOCKED STAGE6-GATE: canonical PostgreSQL volume name changed."
}

Write-Host "PASS STAGE6-GATE-8: loopback ports, internal PostgreSQL, canonical network, and volume contracts pass." -ForegroundColor Green


# ============================================================
# 9. RENDERED FRONTEND HEALTHCHECK
# ============================================================

$FrontendProperty = $ConfigObject.services.PSObject.Properties["frontend"]

if ($null -eq $FrontendProperty) {
    throw "BLOCKED STAGE6-GATE: frontend service is absent."
}

$Frontend = $FrontendProperty.Value

if ($Frontend.PSObject.Properties.Name -notcontains "healthcheck") {
    throw "BLOCKED STAGE6-GATE: frontend healthcheck is absent."
}

$ActualHealth = @($Frontend.healthcheck.test)

$ExpectedHealth = @(
    "CMD",
    "/busybox",
    "wget",
    "-q",
    "-O",
    "/dev/null",
    "http://127.0.0.1/"
)

if ($ActualHealth.Count -ne $ExpectedHealth.Count) {
    throw "BLOCKED STAGE6-GATE: frontend healthcheck argument count changed."
}

for ($Index = 0; $Index -lt $ExpectedHealth.Count; $Index++) {
    if ([string]$ActualHealth[$Index] -ne [string]$ExpectedHealth[$Index]) {
        throw "BLOCKED STAGE6-GATE: rendered frontend healthcheck changed."
    }
}

Write-Host "PASS STAGE6-GATE-9: rendered frontend healthcheck is the exact approved shell-free BusyBox probe." -ForegroundColor Green


# ============================================================
# 10. SECRET / GIT / EOL CONTROLS
# ============================================================

$SensitivePatterns = @(
    'AKIA[0-9A-Z]{16}',
    '-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----',
    'AWS_SECRET_ACCESS_KEY\s*=',
    'AWS_ACCESS_KEY_ID\s*='
)

foreach ($SensitivePattern in $SensitivePatterns) {
    $SensitiveMatch = @(
        Select-String `
          -Path $ComposePath,$DeployPath,$EnvPath,$InvariantPath `
          -Pattern $SensitivePattern `
          -AllMatches
    )

    if ($SensitiveMatch.Count -ne 0) {
        throw "BLOCKED STAGE6-GATE: potential credential material exists in Stage 6 control files."
    }
}

$InvariantBytes = [System.IO.File]::ReadAllBytes($InvariantPath)

$InvariantHasBom = (
    $InvariantBytes.Length -ge 3 -and
    $InvariantBytes[0] -eq 0xEF -and
    $InvariantBytes[1] -eq 0xBB -and
    $InvariantBytes[2] -eq 0xBF
)

if ($InvariantHasBom) {
    throw "BLOCKED STAGE6-GATE: invariant registry contains UTF-8 BOM."
}

if ($InvariantBytes -contains 13) {
    throw "BLOCKED STAGE6-GATE: invariant registry is not canonical LF-only text."
}

$CheckoutAttributeOutput = @(
    git check-attr --cached text eol -- "ops/validation/Invoke-MeridianStage6Gate.ps1" "ops/validation/stage6-invariants.json"
)
$CheckoutAttributeExit = $LASTEXITCODE

if ($CheckoutAttributeExit -ne 0) {
    throw "BLOCKED STAGE6-GATE: cannot validate repository checkout EOL policy."
}

$ExpectedCheckoutAttributes = @(
    "ops/validation/Invoke-MeridianStage6Gate.ps1: text: set",
    "ops/validation/Invoke-MeridianStage6Gate.ps1: eol: lf",
    "ops/validation/stage6-invariants.json: text: set",
    "ops/validation/stage6-invariants.json: eol: lf"
)

if ($CheckoutAttributeOutput.Count -ne 4) {
    throw "BLOCKED STAGE6-GATE: repository checkout EOL policy result count is invalid."
}

$CheckoutAttributeDiff = @(
    Compare-Object -ReferenceObject ($ExpectedCheckoutAttributes | Sort-Object) -DifferenceObject ($CheckoutAttributeOutput | Sort-Object)
)

if ($CheckoutAttributeDiff.Count -ne 0) {
    throw "BLOCKED STAGE6-GATE: repository checkout EOL policy is not explicitly LF for both validation artifacts."
}

$CheckoutEolState = @(
    git ls-files --eol -- "ops/validation/Invoke-MeridianStage6Gate.ps1" "ops/validation/stage6-invariants.json"
)
$CheckoutEolExit = $LASTEXITCODE

if ($CheckoutEolExit -ne 0) {
    throw "BLOCKED STAGE6-GATE: cannot inspect validation-artifact Git EOL state."
}

if ($CheckoutEolState.Count -ne 2) {
    throw "BLOCKED STAGE6-GATE: validation-artifact Git EOL state count is invalid."
}

$ValidatorEolState = @(
    $CheckoutEolState | Where-Object { $_ -match 'Invoke-MeridianStage6Gate\.ps1$' }
)

$InvariantEolState = @(
    $CheckoutEolState | Where-Object { $_ -match 'stage6-invariants\.json$' }
)

if ($ValidatorEolState.Count -ne 1) {
    throw "BLOCKED STAGE6-GATE: validator Git EOL state is ambiguous."
}

if ($InvariantEolState.Count -ne 1) {
    throw "BLOCKED STAGE6-GATE: invariant-registry Git EOL state is ambiguous."
}

if ($ValidatorEolState[0] -notmatch '^i/lf\s+w/lf\s+attr/text eol=lf\s+ops/validation/Invoke-MeridianStage6Gate\.ps1$') {
    throw "BLOCKED STAGE6-GATE: validator is not reproducibly LF in index, worktree, and attributes."
}

if ($InvariantEolState[0] -notmatch '^i/lf\s+w/lf\s+attr/text eol=lf\s+ops/validation/stage6-invariants\.json$') {
    throw "BLOCKED STAGE6-GATE: invariant registry is not reproducibly LF in index, worktree, and attributes."
}

$DiffCheck = @(git diff --check)
$DiffCheckExit = $LASTEXITCODE

if ($DiffCheckExit -ne 0) {
    throw "BLOCKED STAGE6-GATE: Git whitespace validation failed."
}

$AttrOutput = @(
    git check-attr `
      eol `
      -- `
      $ComposeRel `
      $DeployRel
)

$AttrExit = $LASTEXITCODE

if ($AttrExit -ne 0) {
    throw "BLOCKED STAGE6-GATE: Git attribute inspection failed."
}

if ($AttrOutput.Count -ne 2) {
    throw "BLOCKED STAGE6-GATE: unexpected Git attribute result count."
}

$NonLf = @(
    $AttrOutput |
    Where-Object {
        $_ -notmatch ':\s+eol:\s+lf$'
    }
)

if ($NonLf.Count -ne 0) {
    throw "BLOCKED STAGE6-GATE: Linux deployment file EOL policy changed."
}

Write-Host "PASS STAGE6-GATE-10: secret-pattern, whitespace, and LF controls pass." -ForegroundColor Green


Write-Host "PASS STAGE6-GATE: Stage 6 satisfies MIR/invariant regression enforcement." -ForegroundColor Green
