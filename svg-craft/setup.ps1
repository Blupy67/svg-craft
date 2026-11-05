#requires -Version 7
<#
.SYNOPSIS
  Installs svg-craft on a Windows PC: the Claude Code skill, the SVG tools, a portable Node.js and the
  exact npm packages the tools use. Needs no admin rights, and does not change PATH.
.DESCRIPTION
  1. Copies skills\svg-craft and svg-tools into -Target. Running it again updates those copies.
  2. Downloads the portable Node.js zip from nodejs.org, checks its SHA-256 against the SHASUMS256.txt
     that nodejs.org publishes for that version, and unpacks it into svg-tools\node-v<version>-win-x64.
  3. Restores the npm packages from svg-tools\package-lock.json with `npm ci --ignore-scripts`, so no
     package install scripts run. Then checks every version against the rows in svg-tools\LIBRARIES.md.
.PARAMETER Target
  Folder that receives skills\svg-craft and svg-tools. Default: $HOME\.claude
.PARAMETER NodeVersion
  Portable Node.js version to install. Default: 26.13.0
.EXAMPLE
  pwsh -File .\setup.ps1
#>
[CmdletBinding()]
param(
    [string] $Target = (Join-Path $HOME '.claude'),
    [string] $NodeVersion = '26.13.0'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # the progress bar slows large downloads a lot

$repo = $PSScriptRoot
$Target = [IO.Path]::GetFullPath($Target).TrimEnd('\')
if ($Target -ieq $repo.TrimEnd('\')) { throw '-Target must be a different folder from the repository.' }

$toolsDir = Join-Path $Target 'svg-tools'
$skillDir = Join-Path $Target 'skills\svg-craft'
$nodeName = "node-v$NodeVersion-win-x64"
$nodeDir  = Join-Path $toolsDir $nodeName
$node     = Join-Path $nodeDir 'node.exe'
$npmCli   = Join-Path $nodeDir 'node_modules\npm\bin\npm-cli.js'

# Copies the items in $From into $To. Names in $Skip (wildcards allowed) are left out.
function Copy-Tree([string] $From, [string] $To, [string[]] $Skip = @()) {
    New-Item -ItemType Directory -Force -Path $To | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $From -Force) {
        if ($Skip | Where-Object { $item.Name -like $_ }) { continue }
        Copy-Item -LiteralPath $item.FullName -Destination $To -Recurse -Force
    }
}

Write-Host "Installing svg-craft into $Target"

# 1. The skill and the tools. The Node runtime and node_modules are never copied from the repository.
Copy-Tree (Join-Path $repo 'skills\svg-craft') $skillDir
Copy-Tree (Join-Path $repo 'svg-tools') $toolsDir @('node-v*', 'node_modules')
Write-Host '  copied the skill and the tools'

# 2. Portable Node.js: checksum first, unpacked next to the tools. PATH is not changed.
$have = $null
if (Test-Path -LiteralPath $node) { $have = (& $node --version) }
if ($have -ne "v$NodeVersion") {
    if (Test-Path -LiteralPath $nodeDir) { Remove-Item -LiteralPath $nodeDir -Recurse -Force }
    $base    = "https://nodejs.org/dist/v$NodeVersion"
    $zipName = "$nodeName.zip"
    $zip     = Join-Path ([IO.Path]::GetTempPath()) $zipName
    try {
        $sums  = (Invoke-WebRequest -Uri "$base/SHASUMS256.txt" -UseBasicParsing).Content
        $entry = ($sums -split "`r?`n") | Where-Object { $_ -match ('\s' + [regex]::Escape($zipName) + '$') } | Select-Object -First 1
        if (-not $entry) { throw "$zipName is not listed in SHASUMS256.txt for v$NodeVersion." }
        $expected = ($entry.Trim() -split '\s+')[0]
        Write-Host "  downloading $zipName"
        Invoke-WebRequest -Uri "$base/$zipName" -OutFile $zip -UseBasicParsing
        $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        if ($actual -ine $expected) { throw "SHA-256 mismatch for ${zipName}: expected $expected, got $actual. Nothing was installed." }
        Write-Host '  SHA-256 matches the nodejs.org checksum'
        Expand-Archive -LiteralPath $zip -DestinationPath $toolsDir -Force
    } finally {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    }
    $have = (& $node --version)
    if ($have -ne "v$NodeVersion") { throw "Expected Node v$NodeVersion, found $have." }
}
Write-Host "  Node.js $have at $nodeDir (not on PATH)"

# 3. The npm packages, exactly as locked in package-lock.json. No install scripts run.
Write-Host '  installing the locked npm packages (npm ci --ignore-scripts)'
Push-Location $toolsDir
try {
    & $node $npmCli ci --ignore-scripts --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw "npm ci failed (exit code $LASTEXITCODE)." }
} finally {
    Pop-Location
}

# 4. Each version listed in LIBRARIES.md must match what was installed.
$libraries  = Join-Path $toolsDir 'LIBRARIES.md'
$listedText = Get-Content -Raw -LiteralPath $libraries
$checked  = 0
$problems = @()
foreach ($line in ($listedText -split "`r?`n")) {
    if ($line -notmatch '^\|[^|]*\|\s*`?([^|`]+?)`?\s*\|\s*`?(\d+\.\d+\.\d+)`?\s*\|') { continue }
    $name     = $Matches[1].Trim()
    $want     = $Matches[2]
    $manifest = Join-Path $toolsDir ('node_modules\' + ($name -replace '/', '\') + '\package.json')
    $got      = if (Test-Path -LiteralPath $manifest) { (Get-Content -Raw -LiteralPath $manifest | ConvertFrom-Json).version } else { 'missing' }
    if ($got -ne $want) { $problems += "$name is $got, LIBRARIES.md says $want" }
    $checked++
}
if ($checked -eq 0) { throw 'LIBRARIES.md lists no packages.' }
if ($problems) { throw ('Installed packages do not match LIBRARIES.md: ' + ($problems -join '; ')) }
Write-Host "  $checked packages match LIBRARIES.md"

# 5. Every direct dependency should have a row in LIBRARIES.md (a warning only).
$pkg = Get-Content -Raw -LiteralPath (Join-Path $toolsDir 'package.json') | ConvertFrom-Json
foreach ($dep in $pkg.dependencies.PSObject.Properties.Name) {
    if ($listedText -notmatch ('\|\s*`?' + [regex]::Escape($dep) + '`?\s*\|')) {
        Write-Warning "$dep is in package.json but not in LIBRARIES.md"
    }
}

# 6. Rendering needs Chrome or Edge. svg-geom and svg-minify do not.
$browser = $null
foreach ($root in (@($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA) | Where-Object { $_ })) {
    foreach ($exe in 'Google\Chrome\Application\chrome.exe', 'Microsoft\Edge\Application\msedge.exe') {
        $candidate = Join-Path $root $exe
        if (-not $browser -and (Test-Path -LiteralPath $candidate)) { $browser = $candidate }
    }
}
if ($browser) { Write-Host "  browser: $browser" }
else { Write-Warning 'Chrome or Edge was not found. render-svg and check-svg need one.' }

Write-Host ''
Write-Host 'Installed. Next:'
Write-Host "  1. run the self-test:  pwsh -File `"$toolsDir\selftest.ps1`""
Write-Host '  2. start a new Claude Code session so it loads the svg-craft skill'
