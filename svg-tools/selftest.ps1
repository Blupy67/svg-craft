<#
.SYNOPSIS
  Checks that the SVG tools still work. The test is self-contained: it writes its own geometric test SVGs to a
  temporary folder, runs 16 checks on them, and deletes that folder afterward. It never reads samples\ or your
  project files.
.EXAMPLE
  pwsh -File selftest.ps1
#>
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$node = Join-Path $root 'node-v26.13.0-win-x64\node.exe'
$results = New-Object System.Collections.Generic.List[object]

function Add-Test([string]$name, [bool]$ok, [string]$detail) {
    $results.Add([pscustomobject]@{ Test = $name; Result = $(if ($ok) { 'PASS' } else { 'FAIL' }); Detail = $detail })
}

# Every test file and output goes in this folder. It is deleted at the end, even if a check fails.
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('svg-craft-selftest-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null

try {
    # The geometric test files, built from simple shapes and written to $tmp.
    $generated = [ordered]@{
        'icons\circle.svg'               = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8" fill="#1e88e5"/></svg>'
        'icons\square.svg'               = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="3" fill="#43a047"/></svg>'
        'icons\triangle.svg'             = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><polygon points="12,3 21,20 3,20" fill="#fb8c00"/></svg>'
        'icons\plus.svg'                 = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#8e24aa" d="M10 4h4v6h6v4h-6v6h-4v-6H4v-4h6z"/></svg>'
        'illustrations\scene.svg'        = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96"><circle cx="70" cy="28" r="9" fill="#ffca28"/><polygon points="4,80 30,36 46,60 58,46 92,80" fill="#5c6bc0"/><rect x="4" y="80" width="88" height="12" fill="#66bb6a"/></svg>'
        'illustrations\flower.svg'       = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96"><g fill="#f06292"><circle cx="66" cy="48" r="10"/><circle cx="53.6" cy="65.1" r="10"/><circle cx="33.4" cy="58.6" r="10"/><circle cx="33.4" cy="37.4" r="10"/><circle cx="53.6" cy="30.9" r="10"/></g><circle cx="48" cy="48" r="10" fill="#ffca28"/></svg>'
        'effects\glow.svg'               = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96"><defs><filter id="glow" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="6" result="blur"/><feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs><circle cx="48" cy="48" r="18" fill="#ffd54f" filter="url(#glow)"/></svg>'
        'effects\gradient-disc.svg'      = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96"><defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4fc3f7"/><stop offset="1" stop-color="#0d47a1"/></linearGradient><clipPath id="disc"><circle cx="48" cy="48" r="36"/></clipPath></defs><g clip-path="url(#disc)"><rect width="96" height="96" fill="url(#sky)"/><path fill="#2e7d32" d="M0 66C20 56 40 60 60 66S84 72 96 64V96H0z"/></g><circle cx="48" cy="48" r="36" fill="none" stroke="#263238" stroke-width="3"/></svg>'
        'effects\transforms.svg'         = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96"><g transform="translate(48 48) rotate(15)"><g transform="scale(1.6)"><rect x="-14" y="-10" width="28" height="20" rx="3" fill="#ffb74d" stroke="#e65100" stroke-width="1.5" transform="rotate(-30)"/></g></g><circle cx="48" cy="48" r="5" fill="#37474f"/></svg>'
        'problems\clipped-and-speck.svg' = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect x="4" y="6" width="16" height="12" rx="2" fill="#1565c0"/><rect x="20" y="8" width="8" height="8" fill="#1565c0"/><circle cx="2.2" cy="21.5" r="0.6" fill="#1565c0"/></svg>'
        'problems\edge-touch.svg'        = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect x="0" y="4" width="24" height="16" fill="#2e7d32"/></svg>'
        'problems\slight-overhang.svg'   = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><circle cx="12" cy="12" r="12.3" fill="#6a1b9a"/></svg>'
    }
    foreach ($rel in $generated.Keys) {
        $path = Join-Path $tmp $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
        Set-Content -LiteralPath $path -Value $generated[$rel] -Encoding utf8
    }

    $icons    = @(Get-ChildItem -LiteralPath (Join-Path $tmp 'icons') -Filter *.svg | Sort-Object Name)
    $pictures = @(Get-ChildItem -LiteralPath (Join-Path $tmp 'illustrations') -Filter *.svg | Sort-Object Name)
    $effects  = @(Get-ChildItem -LiteralPath (Join-Path $tmp 'effects') -Filter *.svg | Sort-Object Name)
    $problems = @(Get-ChildItem -LiteralPath (Join-Path $tmp 'problems') -Filter *.svg | Sort-Object Name)
    $circle   = Join-Path $tmp 'icons\circle.svg'
    $square   = Join-Path $tmp 'icons\square.svg'
    $plus     = Join-Path $tmp 'icons\plus.svg'
    $clipped  = Join-Path $tmp 'problems\clipped-and-speck.svg'
    $edge     = Join-Path $tmp 'problems\edge-touch.svg'
    $overhang = Join-Path $tmp 'problems\slight-overhang.svg'
    $glow     = Join-Path $tmp 'effects\glow.svg'
    $checker  = Join-Path $root 'check-svg.ps1'
    $geomJs   = Join-Path $root 'svg-geom.mjs'

    # 1. checker: every icon passes
    $r = @(((& $checker -Path $icons.FullName -Json) -join "`n") | ConvertFrom-Json)
    $passed = @($r | Where-Object { $_.ok }).Count
    Add-Test "checker: all $($icons.Count) icons pass" (($r.Count -eq $icons.Count) -and ($passed -eq $icons.Count)) "pass=$passed of $($r.Count)"

    # 2. checker: the sample with a shape past the edge and a floating speck fails for both
    $c = @(((& $checker -Path $clipped -Json) -join "`n") | ConvertFrom-Json)[0]
    $clippedIssues = @($c.issues | Where-Object { $_.text -like 'outside the viewBox*' }).Count
    $specks = @($c.issues | Where-Object { $_.text -like 'floating speck*' }).Count
    Add-Test 'checker: clipped sample fails for clipping and a speck' (($c.ok -eq $false) -and ($clippedIssues -ge 1) -and ($specks -ge 1)) "clipped=$clippedIssues specks=$specks"

    # 3. checker: an edge touch and a slight overhang pass with warnings only
    $w = @(((& $checker -Path $edge, $overhang -Json) -join "`n") | ConvertFrom-Json)
    $warnOnly = @($w | Where-Object { $_.ok -and @($_.issues | Where-Object { $_.level -eq 'warn' }).Count -gt 0 }).Count
    Add-Test 'checker: edge touch and slight overhang pass with warnings' ($warnOnly -eq 2) "files that pass with warnings=$warnOnly of 2"

    # 4. checker: every illustration and effect passes, glows and gradients included
    $both = @($pictures + $effects)
    $p = @(((& $checker -Path $both.FullName -Json) -join "`n") | ConvertFrom-Json)
    $pPassed = @($p | Where-Object { $_.ok }).Count
    Add-Test "checker: all $($both.Count) illustrations and effects pass" (($p.Count -eq $both.Count) -and ($pPassed -eq $both.Count)) "pass=$pPassed of $($p.Count)"

    # 5. the Chrome sheet renderer writes a non-empty PNG
    $sheet = Join-Path $tmp 'sheet.png'
    & (Join-Path $root 'render-svg.ps1') -Path $icons.FullName -Sizes 16,48 -Out $sheet | Out-Null
    $sheetBytes = if (Test-Path -LiteralPath $sheet) { (Get-Item -LiteralPath $sheet).Length } else { 0 }
    Add-Test 'render-svg (Chrome): writes a sheet PNG' ($sheetBytes -gt 1000) "bytes=$sheetBytes"

    # 6. the resvg renderer (Node) writes one PNG per size, plus a silhouette
    $rdir = Join-Path $tmp 'resvg'
    & $node (Join-Path $root 'render-resvg.mjs') $rdir '16,48' $circle $clipped | Out-Null
    & $node (Join-Path $root 'render-resvg.mjs') $rdir '16' $circle --silhouette | Out-Null
    $expected = @('circle-16.png', 'circle-48.png', 'clipped-and-speck-16.png', 'clipped-and-speck-48.png', 'circle-16-silhouette.png')
    $missing = @($expected | Where-Object { -not (Test-Path -LiteralPath (Join-Path $rdir $_)) })
    Add-Test 'render-resvg (Node): writes every PNG' ($missing.Count -eq 0) ('missing: ' + ($missing -join ', '))

    # 7. svg-geom: the shape past the edge is reported and exits 1; every icon is inside its box and exits 0
    $gb = @(& $node $geomJs bounds $clipped)
    $gbExit = $LASTEXITCODE
    Add-Test 'svg-geom bounds: shape past the edge reported, exit 1' (($gbExit -eq 1) -and (($gb -join "`n") -match 'past the edge')) "exit=$gbExit"
    $iconExits = @(foreach ($i in $icons) { & $node $geomJs bounds $i.FullName | Out-Null; $LASTEXITCODE })
    Add-Test "svg-geom bounds: all $($icons.Count) icons inside, exit 0" (@($iconExits | Where-Object { $_ -ne 0 }).Count -eq 0) "exit codes: $($iconExits -join ' ')"

    # 8. svg-geom: the silhouette is one black path, and the outline adds one underlay path to the original art
    $sil = Join-Path $tmp 'circle-silhouette.svg'
    & $node $geomJs silhouette $circle $sil | Out-Null
    $silText = if (Test-Path -LiteralPath $sil) { Get-Content -Raw -LiteralPath $sil } else { '' }
    $silPaths = ([regex]::Matches($silText, '<path')).Count
    Add-Test 'svg-geom silhouette: one black path' (($silPaths -eq 1) -and ($silText -match 'fill="#000"')) "paths=$silPaths"
    $outl = Join-Path $tmp 'plus-outline.svg'
    & $node $geomJs outline $plus $outl --width 1.5 --color '#1d4a12' | Out-Null
    $outText = if (Test-Path -LiteralPath $outl) { Get-Content -Raw -LiteralPath $outl } else { '' }
    $plusPaths = ([regex]::Matches((Get-Content -Raw -LiteralPath $plus), '<path')).Count
    $outPaths = ([regex]::Matches($outText, '<path')).Count
    Add-Test 'svg-geom outline: one underlay path plus the original art' (($outPaths -eq ($plusPaths + 1)) -and ($outText -match 'stroke-width="3"')) "paths=$outPaths expected=$($plusPaths + 1)"

    # 9. svg-geom agrees with the checker on every icon, illustration and problem file
    #    (svg-geom does not measure glows, so the effects files are left out)
    $checked = @($icons + $pictures + $problems)
    $verdicts = @{}
    foreach ($x in @(((& $checker -Path $checked.FullName -Json) -join "`n") | ConvertFrom-Json)) {
        $verdicts[$x.name] = (@($x.issues | Where-Object { $_.level -eq 'error' -and ($_.text -like 'outside the viewBox*' -or $_.text -like 'runs past*') }).Count -gt 0)
    }
    $agree = 0
    foreach ($f in $checked) {
        $j = ((& $node $geomJs bounds $f.FullName --json) -join "`n") | ConvertFrom-Json
        if ((@($j.outside).Count -gt 0) -eq $verdicts[$f.Name]) { $agree++ }
    }
    Add-Test "svg-geom agrees with the checker on all $($checked.Count) icons, illustrations and problem files" ($agree -eq $checked.Count) "agree=$agree of $($checked.Count)"

    # 10. render-svg -Compare: the reference rows sit above the new rows on one sheet
    $cmpSheet = Join-Path $tmp 'compare-sheet.png'
    & (Join-Path $root 'render-svg.ps1') -Path $clipped, $edge -Compare $circle, $square -Sizes 24,96 -Out $cmpSheet | Out-Null
    $cmpHtml = Get-Content -Raw -LiteralPath ($cmpSheet + '.html')
    $refRows = ([regex]::Matches($cmpHtml, 'class="row ref"')).Count
    $newRows = ([regex]::Matches($cmpHtml, 'class="row new"')).Count
    $refFirst = $cmpHtml.IndexOf('class="row ref"') -lt $cmpHtml.IndexOf('class="row new"')
    Add-Test 'render-svg -Compare: 2 reference rows above 2 new rows' (($refRows -eq 2) -and ($newRows -eq 2) -and $refFirst) "ref=$refRows new=$newRows refFirst=$refFirst"

    # 11. svg-minify: an icon is written, keeps its viewBox, and is never larger than the original
    $minOut = Join-Path $tmp 'circle.min.svg'
    & $node (Join-Path $root 'svg-minify.mjs') $circle $minOut | Out-Null
    $minExit = $LASTEXITCODE
    $minText = if (Test-Path -LiteralPath $minOut) { Get-Content -Raw -LiteralPath $minOut } else { '' }
    $circleSize = (Get-Item -LiteralPath $circle).Length
    $minSize = if ($minText) { (Get-Item -LiteralPath $minOut).Length } else { -1 }
    Add-Test 'svg-minify: icon written, viewBox kept, not larger' (($minExit -eq 0) -and ($minText -match 'viewBox="0 0 24 24"') -and ($minSize -le $circleSize)) "exit=$minExit bytes $circleSize -> $minSize"

    # 12. svg-minify: a file with a glow is written and is never larger than the original
    $glowOut = Join-Path $tmp 'glow.min.svg'
    & $node (Join-Path $root 'svg-minify.mjs') $glow $glowOut | Out-Null
    $glowExit = $LASTEXITCODE
    $glowSize = (Get-Item -LiteralPath $glow).Length
    $glowMin = if (Test-Path -LiteralPath $glowOut) { (Get-Item -LiteralPath $glowOut).Length } else { -1 }
    Add-Test 'svg-minify: file with a glow written, not larger' (($glowExit -eq 0) -and ($glowMin -gt 0) -and ($glowMin -le $glowSize)) "exit=$glowExit bytes $glowSize -> $glowMin"

    # 13. the docs run every Node script through its full node.exe path, so nothing depends on PATH
    $skillPath = Join-Path (Split-Path $root -Parent) 'skills\svg-craft\SKILL.md'
    $docText = (Get-Content -Raw -LiteralPath $skillPath) + "`n" + (Get-Content -Raw -LiteralPath (Join-Path $root 'README.md'))
    $bareNode = ([regex]::Matches($docText, '(?m)(^|[\s"`&])node\s+\S*\.mjs')).Count
    Add-Test 'docs: every Node script runs through the full node.exe path' ($bareNode -eq 0) "bare node script commands=$bareNode"

    # 14. portable: no script or doc hardcodes a user's folder; paths come from $HOME, $PSScriptRoot or the environment
    $portable = @(Get-ChildItem -LiteralPath $root -File | Where-Object { $_.Extension -in '.ps1', '.mjs', '.md', '.json' -and $_.Name -ne 'selftest.ps1' })
    $portable += Get-Item -LiteralPath $skillPath
    $hardcoded = @($portable | Where-Object { (Get-Content -Raw -LiteralPath $_.FullName) -match '[A-Za-z]:\\Users\\' } | ForEach-Object { $_.Name })
    Add-Test 'portable: no script or doc hardcodes a user folder' ($hardcoded.Count -eq 0) ('files with a hardcoded user folder: ' + ($hardcoded -join ', '))
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$results | Format-Table -AutoSize -Wrap | Out-String -Width 240 | Write-Output
if (@($results | Where-Object { $_.Result -eq 'FAIL' }).Count -gt 0) { exit 1 }
