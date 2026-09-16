param()

$ErrorActionPreference = "Stop"

$Root =
    (
        Resolve-Path `
            (Join-Path $PSScriptRoot "..\..")
    ).Path

$Fqdn =
    "meridian-retail-temi.duckdns.org"

$Paths = @{
    Acme =
        Join-Path $Root "nginx\meridian-acme.conf"

    Https =
        Join-Path $Root "nginx\meridian-https.conf"

    Installer =
        Join-Path $Root "ops\routing\install-nginx-d7.sh"

    Hook =
        Join-Path $Root "ops\routing\reload-nginx-after-renewal.sh"

    Docs =
        Join-Path $Root "docs\tls-explained.md"
}


function Assert-True {

    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "D7-SOURCE-GATE: $Message"
    }
}


function Read-Utf8Lf {

    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Assert-True `
        (Test-Path -LiteralPath $Path -PathType Leaf) `
        "missing source file: $Path"

    $Bytes =
        [IO.File]::ReadAllBytes($Path)

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
        -Condition (-not ($Bytes -contains 13)) `
        -Message "CR/CRLF forbidden: $Path"

    [Text.Encoding]::UTF8.GetString($Bytes)
}


$Acme =
    Read-Utf8Lf $Paths.Acme

$Https =
    Read-Utf8Lf $Paths.Https

$Installer =
    Read-Utf8Lf $Paths.Installer

$Hook =
    Read-Utf8Lf $Paths.Hook

$Docs =
    Read-Utf8Lf $Paths.Docs


# ACME contract.

Assert-True `
    ($Acme.Contains("server_name $Fqdn;")) `
    "ACME exact hostname missing."

Assert-True `
    ($Acme.Contains(
        'location ^~ /.well-known/acme-challenge/'
    )) `
    "ACME challenge route missing."

Assert-True `
    ($Acme.Contains(
        'root /var/www/meridian-acme;'
    )) `
    "ACME webroot missing."

Assert-True `
    (-not ($Acme -match '(?m)^\s*listen\s+443\b')) `
    "ACME state must not listen on 443."

Assert-True `
    (-not ($Acme -match '(?i)\bssl_certificate\b')) `
    "ACME state must not require a certificate."


# Final HTTPS contract.

Assert-True `
    ($Https.Contains("server_name $Fqdn;")) `
    "HTTPS exact hostname missing."

Assert-True `
    ($Https -match '(?m)^\s*listen 443 ssl;\s*$') `
    "named IPv4 HTTPS listener missing."

Assert-True `
    ($Https -match '(?m)^\s*listen \[::\]:443 ssl;\s*$') `
    "named IPv6 HTTPS listener missing."

Assert-True `
    ($Https.Contains(
        'ssl_certificate /etc/letsencrypt/live/meridian-retail-temi.duckdns.org/fullchain.pem;'
    )) `
    "fullchain path missing."

Assert-True `
    ($Https.Contains(
        'ssl_certificate_key /etc/letsencrypt/live/meridian-retail-temi.duckdns.org/privkey.pem;'
    )) `
    "private-key path missing."

Assert-True `
    ($Https.Contains(
        'ssl_protocols TLSv1.2 TLSv1.3;'
    )) `
    "TLS protocol policy missing."

Assert-True `
    ($Https.Contains(
        'return 301 https://meridian-retail-temi.duckdns.org$request_uri;'
    )) `
    "fixed canonical redirect missing."

Assert-True `
    (-not $Https.Contains(
        'return 301 https://$host$request_uri;'
    )) `
    "redirect must not trust arbitrary Host input."

Assert-True `
    ($Https.Contains(
        'location ^~ /.well-known/acme-challenge/'
    )) `
    "renewal challenge path missing."


# Routing contract exists in both states.

$RoutingFragments = @(
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
    'proxy_pass http://127.0.0.1:8080;'
)


foreach ($Config in @(
    $Acme,
    $Https
)) {

    foreach ($Fragment in $RoutingFragments) {

        Assert-True `
            ($Config.Contains($Fragment)) `
            "routing fragment missing: $Fragment"
    }


    Assert-True `
        (-not ($Config -match ':5432')) `
        "PostgreSQL must never be an Nginx upstream."


    Assert-True `
        (-not (
            $Config -match
            'proxy_pass\s+http://(?!127\.0\.0\.1)'
        )) `
        "application upstreams must remain loopback-only."
}


# Installer contract.

foreach ($Fragment in @(
    'acme|https',
    '/etc/nginx/sites-available/meridian',
    '/etc/nginx/sites-enabled/meridian',
    '/var/www/meridian-acme',
    '/etc/letsencrypt/live/${FQDN}/fullchain.pem',
    '/etc/letsencrypt/live/${FQDN}/privkey.pem',
    '/usr/local/sbin/meridian-certbot-deploy-hook',
    '/var/lib/meridian/nginx-rollback',
    'openssl x509',
    'nginx -t',
    'systemctl reload nginx',
    'rollback',
    'ROLLBACK=PASS',
    'MERIDIAN_D7_INSTALL=SUCCESS'
)) {

    Assert-True `
        ($Installer.Contains($Fragment)) `
        "installer contract missing: $Fragment"
}


Assert-True `
    ($Installer.Contains(
        '# Every filesystem mutation occurs after rollback has been armed.'
    )) `
    "rollback must be armed before mutation."

Assert-True `
    (-not $Installer.Contains(
        'systemctl restart nginx'
    )) `
    "installer must reload, not restart."


# Deploy hook contract.

foreach ($Fragment in @(
    'command -v nginx',
    'command -v systemctl',
    '"${NGINX}" -t',
    '"${SYSTEMCTL}" reload nginx',
    'MERIDIAN_CERTBOT_DEPLOY_HOOK=SUCCESS'
)) {

    Assert-True `
        ($Hook.Contains($Fragment)) `
        "deploy hook incomplete: $Fragment"
}


Assert-True `
    (-not $Hook.Contains('restart nginx')) `
    "deploy hook must never restart Nginx."


# Documentation contract.

foreach ($Fragment in @(
    'meridian-retail-temi.duckdns.org',
    '98.88.168.236',
    'nginx/meridian-http.conf',
    'nginx/meridian-acme.conf',
    'nginx/meridian-https.conf',
    'certbot certonly --webroot',
    '/var/www/meridian-acme',
    '--deploy-hook /usr/local/sbin/meridian-certbot-deploy-hook',
    '/etc/letsencrypt/live/meridian-retail-temi.duckdns.org/',
    'TLS 1.2',
    'TLS 1.3',
    'certbot renew',
    '--dry-run',
    '--run-deploy-hooks',
    'PostgreSQL',
    'Terraform remains zero-drift',
    'protected backup stash'
)) {

    Assert-True `
        ($Docs.Contains($Fragment)) `
        "TLS documentation incomplete: $Fragment"
}


Write-Host `
    "PASS D7-SOURCE-GATE: source-controlled ACME + HTTPS contract is valid." `
    -ForegroundColor Green
