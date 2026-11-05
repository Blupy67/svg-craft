<#
.SYNOPSIS
  Draws SVG files at real pixel sizes onto one PNG contact sheet, using the Chrome or Edge already installed.
.DESCRIPTION
  One row per file, one column per pixel size. -Compare adds reference rows (existing art, such as an icon set)
  above the new art, so style and visual weight can be checked on one sheet. Also keeps <Out>.html, the page
  the sheet was made from. -Silhouette fills every shape solid black, to check whether the silhouette reads.
.EXAMPLE
  pwsh -File render-svg.ps1 -Path new-icon.svg, new-badge.svg -Sizes 16,24,48,96 -Out C:\scratch\sheet.png
.EXAMPLE
  pwsh -File render-svg.ps1 -Path new-icon.svg -Compare samples\my-art\logo.svg -Sizes 24,96 -Out C:\scratch\compare.png
#>
param(
    [Parameter(Mandatory)] [string[]] $Path,
    [string[]] $Compare = @(),
    [int[]] $Sizes = @(16, 24, 48, 96),
    [string] $Out = (Join-Path (Get-Location) 'svg-sheet.png'),
    [string] $Background = '#ffffff',
    [switch] $Silhouette,
    [string] $Browser
)
$ErrorActionPreference = 'Stop'

function Find-Browser {
    $hit = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $hit) { throw 'No Chrome or Edge found. Pass -Browser with the path to chrome.exe or msedge.exe.' }
    return $hit
}

if (-not $Browser) { $Browser = Find-Browser }
$outPath = [IO.Path]::GetFullPath($Out)
$htmlPath = "$outPath.html"
$profileDir = Join-Path $env:LOCALAPPDATA 'svg-tools\browser-profile'
New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

$refFiles = @(foreach ($p in $Compare) { Get-ChildItem -Path $p -File -ErrorAction Stop })
$newFiles = @(foreach ($p in $Path) { Get-ChildItem -Path $p -File -ErrorAction Stop })
if ($newFiles.Count -eq 0) { throw 'No SVG files matched.' }
$rows = @(
    foreach ($f in $refFiles) { [pscustomobject]@{ File = $f; Kind = 'ref' } }
    foreach ($f in $newFiles) { [pscustomobject]@{ File = $f; Kind = 'new' } }
)

$rowHeight = (($Sizes | Measure-Object -Maximum).Maximum) + 44
$sheetW = [Math]::Max(480, 190 + (($Sizes | ForEach-Object { $_ + 28 }) | Measure-Object -Sum).Sum + 24)
$sheetH = $rows.Count * $rowHeight + 24

$rowHtml = foreach ($row in $rows) {
    $f = $row.File
    $uri = 'data:image/svg+xml;base64,' + [Convert]::ToBase64String([IO.File]::ReadAllBytes($f.FullName))
    $cells = foreach ($s in $Sizes) {
        "<div class=""cell""><img src=""$uri"" width=""$s"" height=""$s"" alt=""""><span>$s px</span></div>"
    }
    $tag = if ($row.Kind -eq 'ref') { 'REFERENCE' } else { 'NEW' }
    $label = [Net.WebUtility]::HtmlEncode($f.Name)
    "<div class=""row $($row.Kind)""><div class=""name""><span class=""tag"">$tag</span>$label</div>$($cells -join '')</div>"
}
$bodyClass = if ($Silhouette) { 'silhouette' } else { '' }

$page = @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>svg sheet</title><style>
html, body { margin: 0; background: $Background; }
body { width: ${sheetW}px; height: ${sheetH}px; box-sizing: border-box; padding: 12px; font: 12px "Segoe UI", Arial, sans-serif; color: #333; }
.row { display: flex; align-items: flex-end; height: ${rowHeight}px; box-sizing: border-box; padding-bottom: 8px; border-bottom: 1px solid rgba(127,127,127,.35); }
.row.ref { background: #f4f0e4; border-bottom: 2px solid #a89d78; }
.name { width: 170px; flex: none; align-self: center; font-weight: 600; word-break: break-all; }
.tag { display: block; font-size: 10px; letter-spacing: .08em; opacity: .55; margin-bottom: 2px; }
.cell { display: flex; flex-direction: column; align-items: center; margin-right: 28px; }
.cell img { display: block; }
.cell span { margin-top: 4px; opacity: .6; }
body.silhouette img { filter: brightness(0); }
</style></head>
<body class="$bodyClass">
$($rowHtml -join "`n")
</body></html>
"@
Set-Content -LiteralPath $htmlPath -Value $page -Encoding utf8

Remove-Item -LiteralPath $outPath -ErrorAction SilentlyContinue
$chromeArgs = @(
    '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run', '--no-default-browser-check',
    "--user-data-dir=""$profileDir""", '--force-device-scale-factor=1',
    "--window-size=$sheetW,$sheetH", '--virtual-time-budget=3000',
    "--screenshot=""$outPath""", ([Uri]$htmlPath).AbsoluteUri
)
$log = Join-Path $profileDir 'render.log'
$run = Start-Process -FilePath $Browser -ArgumentList $chromeArgs -Wait -NoNewWindow -PassThru -RedirectStandardError $log
if (-not (Test-Path -LiteralPath $outPath)) { throw "The browser exited with code $($run.ExitCode) and wrote no image. See $log" }
Write-Output "Wrote $outPath (${sheetW} x ${sheetH} px; $($refFiles.Count) reference, $($newFiles.Count) new). Page: $htmlPath"
