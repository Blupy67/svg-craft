<#
.SYNOPSIS
  Adds one npm package to svg-tools under our download rules: an exact pinned version, a minimum age,
  an allowed licence, no install scripts, and a row in LIBRARIES.md. npm does the downloading and checks
  each package's integrity hash; this script adds the rules npm does not enforce.
.EXAMPLE
  pwsh -File add-lib.ps1 -Package polygon-clipping -Version 0.15.7 -Purpose 'boolean ops on shapes'
#>
param(
    [Parameter(Mandatory)] [string] $Package,
    [string] $Version,
    [string] $Purpose = '',
    [int] $MinAgeDays = 14,
    [switch] $AllowNew,
    [string[]] $AllowLicense = @()
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = $PSScriptRoot
$nodeDir = Join-Path $root 'node-v26.13.0-win-x64'
$node = Join-Path $nodeDir 'node.exe'
$npmCli = Join-Path $nodeDir 'node_modules\npm\bin\npm-cli.js'
if (-not (Test-Path -LiteralPath $node)) { throw "Node runtime not found at $node" }
$allowed = @('MIT', 'ISC', 'BSD-2-Clause', 'BSD-3-Clause', 'Apache-2.0', 'MPL-2.0', '0BSD', 'Unlicense', 'BSL-1.0') + $AllowLicense

$doc = Invoke-RestMethod -Uri ('https://registry.npmjs.org/' + $Package.Replace('/', '%2f')) -TimeoutSec 60
if (-not $Version) { $Version = [string]$doc.'dist-tags'.latest }
$meta = $doc.versions.$Version
if (-not $meta) { throw "$Package@$Version is not on the registry." }
$published = ([datetime]$doc.time.$Version).ToUniversalTime()
$ageDays = ([datetime]::UtcNow - $published).TotalDays
if ($ageDays -lt $MinAgeDays -and -not $AllowNew) {
    throw ('{0}@{1} was published {2:N1} days ago; the minimum is {3}. Pass -AllowNew to override.' -f $Package, $Version, $ageDays, $MinAgeDays)
}
$license = [string]$meta.license
if ($allowed -notcontains $license) {
    throw "Licence '$license' is not on the allowed list. Pass -AllowLicense '$license' to accept it."
}
$depCount = if ($meta.dependencies) { @($meta.dependencies.PSObject.Properties).Count } else { 0 }
$size = if ($meta.dist.unpackedSize) { '{0:N0} KB' -f ($meta.dist.unpackedSize / 1KB) } else { 'size not published' }
"package:     $Package@$Version"
"licence:     $license"
"published:   $($published.ToString('yyyy-MM-dd')) ($([int]$ageDays) days ago)"
"unpacked:    $size, $depCount direct dependencies"
"description: $($meta.description)"

Push-Location $root
try {
    & $node $npmCli install --ignore-scripts --save-exact --no-fund "$Package@$Version"
    if ($LASTEXITCODE -ne 0) { throw 'npm install failed; nothing was recorded.' }
    $ls = (& $node $npmCli ls $Package --depth=0 --json) | ConvertFrom-Json
    $installed = [string]$ls.dependencies.$Package.version
    if ($installed -ne $Version) { throw "Installed $installed, expected $Version." }
} finally {
    Pop-Location
}

$manifest = Join-Path $root 'LIBRARIES.md'
if (-not (Test-Path -LiteralPath $manifest)) {
    Set-Content -LiteralPath $manifest -Encoding utf8 -Value @(
        '# Libraries in svg-tools',
        '',
        'Added with add-lib.ps1, which pins exact versions and checks age and licence before installing.',
        '',
        '| Added (UTC) | Package | Version | Licence | Published | Purpose |',
        '|---|---|---|---|---|---|')
}
$row = '| {0} | {1} | {2} | {3} | {4} | {5} |' -f [DateTime]::UtcNow.ToString('yyyy-MM-dd'), $Package, $Version, $license, $published.ToString('yyyy-MM-dd'), $Purpose
Add-Content -LiteralPath $manifest -Encoding utf8 -Value $row
"installed $Package@$Version and recorded it in LIBRARIES.md"
