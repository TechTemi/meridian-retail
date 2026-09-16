param()

$ErrorActionPreference = "Stop"

$Root =
    (
        Resolve-Path `
            (Join-Path $PSScriptRoot "..\..")
    ).Path

$ConfigPath =
    Join-Path `
        $Root `
        "nginx\meridian-http.conf"

$InstallerPath =
    Join-Path `
        $Root `
        "ops\routing\install-nginx-routing.sh"

$DocumentationPath =
    Join-Path `
        $Root `
        "docs\routing-explained.md"

$LegacyServerSetupPath =
    Join-Path `
        $Root `
        "scripts\server_setup.sh"


function Assert-True {

    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "STAGE7-SOURCE-GATE: $Message"
    }
}


function Get-Utf8LfText {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Assert-True `
        -Condition (
            Test-Path `
                -LiteralPath $Path `
                -PathType Leaf
        ) `
        -Message "missing file: $Path"

    $Bytes =
        [System.IO.File]::ReadAllBytes(
            $Path
        )

    Assert-True `
        -Condition (
            -not (
                $Bytes.Length -ge 3 -and
                $Bytes[0] -eq 0xEF -and
                $Bytes[1] -eq 0xBB -and
                $Bytes[2] -eq 0xBF
            )
        ) `
        -Message "UTF-8 BOM forbidden: $Path"

    Assert-True `
        -Condition (
            -not ($Bytes -contains 13)
        ) `
        -Message "CR/CRLF forbidden; LF required: $Path"

    [Text.Encoding]::UTF8.GetString(
        $Bytes
    )
}


$Config =
    Get-Utf8LfText `
        -Path $ConfigPath

$Installer =
    Get-Utf8LfText `
        -Path $InstallerPath

$Documentation =
    Get-Utf8LfText `
        -Path $DocumentationPath


# ------------------------------------------------------------
# Preserve legacy placeholder.
# ------------------------------------------------------------

Assert-True `
    -Condition (
        Test-Path `
            -LiteralPath $LegacyServerSetupPath `
            -PathType Leaf
    ) `
    -Message "legacy scripts/server_setup.sh disappeared."

$LegacyBytes =
    [System.IO.File]::ReadAllBytes(
        $LegacyServerSetupPath
    )

Assert-True `
    -Condition (
        $LegacyBytes.Length -eq 0
    ) `
    -Message (
        "legacy scripts/server_setup.sh must remain the " +
        "untouched empty placeholder."
    )


# ------------------------------------------------------------
# HTTP listener ownership.
# ------------------------------------------------------------

Assert-True `
    -Condition (
        $Config -match
        '(?m)^\s*listen 80 default_server;\s*$'
    ) `
    -Message "IPv4 HTTP default listener missing."

Assert-True `
    -Condition (
        $Config -match
        '(?m)^\s*listen \[::\]:80 default_server;\s*$'
    ) `
    -Message "IPv6 HTTP default listener missing."

Assert-True `
    -Condition (
        $Config -match
        '(?m)^\s*server_name _;\s*$'
    ) `
    -Message "catch-all server_name missing."


# ------------------------------------------------------------
# Exact route/upstream contract.
# ------------------------------------------------------------

$RequiredFragments = @(
    'location = /api/auth/healthz',
    'proxy_pass http://127.0.0.1:8001/healthz;',
    'location = /api/catalog/healthz',
    'proxy_pass http://127.0.0.1:8002/healthz;',
    'location = /api/orders/healthz',
    'proxy_pass http://127.0.0.1:8003/healthz;',
    'location ^~ /api/auth/',
    'proxy_pass http://127.0.0.1:8001;',
    'location ^~ /api/catalog/',
    'proxy_pass http://127.0.0.1:8002;',
    'location ^~ /api/orders',
    'proxy_pass http://127.0.0.1:8003;',
    'location / {',
    'proxy_pass http://127.0.0.1:8080;'
)


foreach ($Fragment in $RequiredFragments) {

    Assert-True `
        -Condition (
            $Config.Contains(
                $Fragment
            )
        ) `
        -Message (
            "required routing fragment missing: $Fragment"
        )
}


# ------------------------------------------------------------
# No premature TLS / public database exposure.
# ------------------------------------------------------------

Assert-True `
    -Condition (
        -not (
            $Config -match
            '(?m)^\s*listen\s+443\b'
        )
    ) `
    -Message "TLS listener forbidden in HTTP-only slice."

Assert-True `
    -Condition (
        -not (
            $Config -match
            '(?i)\bssl_certificate\b'
        )
    ) `
    -Message "certificate directives forbidden in HTTP-only slice."

Assert-True `
    -Condition (
        -not (
            $Config -match
            'proxy_pass\s+http://(?!127\.0\.0\.1)'
        )
    ) `
    -Message "all Stage-7 upstreams must use loopback."

Assert-True `
    -Condition (
        -not (
            $Config -match ':5432'
        )
    ) `
    -Message "PostgreSQL must not be an Nginx upstream."


# ------------------------------------------------------------
# Forwarded request identity.
# ------------------------------------------------------------

foreach ($Header in @(
    'proxy_set_header Host $host;',
    'proxy_set_header X-Real-IP $remote_addr;',
    'proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;',
    'proxy_set_header X-Forwarded-Proto $scheme;'
)) {

    Assert-True `
        -Condition (
            $Config.Contains(
                $Header
            )
        ) `
        -Message (
            "required proxy header missing: $Header"
        )
}


# ------------------------------------------------------------
# Installer safety contract.
# ------------------------------------------------------------

foreach ($Fragment in @(
    '/etc/nginx/sites-available/meridian',
    '/etc/nginx/sites-enabled/meridian',
    '/etc/nginx/sites-enabled/default',
    '/var/lib/meridian/nginx-rollback',
    'nginx -t',
    'systemctl reload nginx',
    'rollback',
    'ROLLBACK=PASS',
    'MERIDIAN_NGINX_INSTALL=SUCCESS'
)) {

    Assert-True `
        -Condition (
            $Installer.Contains(
                $Fragment
            )
        ) `
        -Message (
            "installer safety fragment missing: $Fragment"
        )
}


Assert-True `
    -Condition (
        -not (
            $Installer.Contains(
                'systemctl restart nginx'
            )
        )
    ) `
    -Message "installer must reload rather than restart Nginx."


# ------------------------------------------------------------
# Documentation contract.
# ------------------------------------------------------------

foreach ($Fragment in @(
    '/api/auth/healthz',
    '/api/catalog/healthz',
    '/api/orders/healthz',
    '127.0.0.1:8001',
    '127.0.0.1:8002',
    '127.0.0.1:8003',
    '127.0.0.1:8080',
    '5432',
    'PostgreSQL',
    'HTTPS is deliberately outside this HTTP routing slice',
    'scripts/server_setup.sh',
    'ops/bootstrap/bootstrap-host.sh'
)) {

    Assert-True `
        -Condition (
            $Documentation.Contains(
                $Fragment
            )
        ) `
        -Message (
            "routing documentation incomplete: $Fragment"
        )
}


Write-Host `
    "PASS STAGE7-SOURCE-GATE: HTTP routing contract is valid." `
    -ForegroundColor Green
