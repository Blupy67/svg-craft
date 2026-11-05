<#
.SYNOPSIS
  Checks SVG files for mechanical problems: shapes drawn outside the viewBox (they get clipped), tiny floating
  specks, and separate pieces. Uses the Chrome or Edge already installed.
.DESCRIPTION
  Each file is drawn again with a margin around its viewBox, so anything outside the box shows up. Connected
  pixels are then measured. Coordinates are in the file's own viewBox units. Exit code 1 means at least one
  file has an error, so the script can gate a build. Overhangs shallower than -Tolerance units (default 0.5,
  under a pixel at 1x) are warnings, not errors.
.EXAMPLE
  pwsh -File check-svg.ps1 plants\*.svg
.EXAMPLE
  pwsh -File check-svg.ps1 new-icon.svg -Speck 2 -Json
#>
param(
    [Parameter(Mandatory)] [string[]] $Path,
    [double] $Speck = 3,
    [double] $Tolerance = 0.5,
    [switch] $Json,
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
$profileDir = Join-Path $env:LOCALAPPDATA 'svg-tools\browser-profile'
New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

$files = @(foreach ($p in $Path) { Get-ChildItem -Path $p -File -ErrorAction Stop })
if ($files.Count -eq 0) { throw 'No SVG files matched.' }

# the SVG text travels inside the page as JSON, so nothing needs to be read from disk by the browser
$items = foreach ($f in $files) {
    $name = $f.Name | ConvertTo-Json -Compress
    $svg = (Get-Content -Raw -LiteralPath $f.FullName) | ConvertTo-Json -Compress
    "{`"name`":$name,`"svg`":$svg}"
}
$inputJson = ('[' + ($items -join ',') + ']').Replace('</', '<\/')
$speckText = $Speck.ToString([Globalization.CultureInfo]::InvariantCulture)
$tolText = $Tolerance.ToString([Globalization.CultureInfo]::InvariantCulture)

$checkJs = @'
const ALPHA = 40;        // a pixel counts as drawn when its alpha is at least this (0-255)
const TARGET = 1000;     // rough width of the analysis canvas in pixels, so small icons still get detail
const SPECK = __SPECK__; // a detached piece smaller than this many units on both sides is a floating speck
const TOL = __TOL__;     // an overhang shallower than this many units is only a warning (under a pixel at 1x)

function viewBoxOf(svg) {
  const root = svg.match(/<svg\b[^>]*>/i);
  if (!root) throw new Error('no <svg> element found');
  const vb = root[0].match(/\bviewBox\s*=\s*"([^"]+)"/i);
  if (!vb) throw new Error('the root <svg> has no viewBox');
  const n = vb[1].trim().split(/[\s,]+/).map(Number);
  if (n.length !== 4 || n.some(v => !Number.isFinite(v)) || n[2] <= 0 || n[3] <= 0) {
    throw new Error('viewBox "' + vb[1] + '" needs four numbers and a positive size');
  }
  return { root: root[0], x: n[0], y: n[1], w: n[2], h: n[3] };
}

// the same SVG with a new viewBox and pixel size written onto the root tag
function resized(svg, root, viewBox, width, height) {
  let tag = root.replace(/\s(width|height|viewBox)\s*=\s*"[^"]*"/gi, '');
  tag = tag.replace(/\s*(\/?>)$/, ' width="' + width + '" height="' + height + '" viewBox="' + viewBox + '" $1');
  return svg.replace(root, () => tag);
}

function loadImage(text) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(new Blob([text], { type: 'image/svg+xml' }));
    const img = new Image();
    img.onload = () => { URL.revokeObjectURL(url); resolve(img); };
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('the browser could not parse this SVG')); };
    img.src = url;
  });
}

const round1 = v => Math.round(v * 10) / 10;
const round2 = v => Math.round(v * 100) / 100;

async function checkOne(file) {
  const vb = viewBoxOf(file.svg);
  const pad = Math.max(2, Math.round(Math.max(vb.w, vb.h) * 0.1));                              // margin, in units
  const S = Math.max(2, Math.min(40, Math.floor(TARGET / (Math.max(vb.w, vb.h) + 2 * pad))));   // pixels per unit
  const W = Math.round((vb.w + 2 * pad) * S), H = Math.round((vb.h + 2 * pad) * S);
  const padded = resized(file.svg, vb.root, `${vb.x - pad} ${vb.y - pad} ${vb.w + 2 * pad} ${vb.h + 2 * pad}`, W, H);
  const img = await loadImage(padded);
  const canvas = document.createElement('canvas');
  canvas.width = W; canvas.height = H;
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  ctx.drawImage(img, 0, 0, W, H);
  const rgba = ctx.getImageData(0, 0, W, H).data;

  // the real box in pixels; everything outside it is the margin
  const bx0 = Math.round(pad * S), by0 = Math.round(pad * S);
  const bx1 = Math.round((pad + vb.w) * S), by1 = Math.round((pad + vb.h) * S);
  const on = new Uint8Array(W * H);
  for (let i = 0; i < on.length; i++) on[i] = rgba[i * 4 + 3] >= ALPHA ? 1 : 0;

  // connected pieces (8 neighbours): size, extent, and how much of each lies outside the box
  const label = new Int32Array(on.length), stack = new Int32Array(on.length), pieces = [];
  for (let start = 0; start < on.length; start++) {
    if (!on[start] || label[start]) continue;
    const id = pieces.length + 1;
    const p = { area: 0, minX: W, minY: H, maxX: -1, maxY: -1, out: 0, oMinX: W, oMinY: H, oMaxX: -1, oMaxY: -1 };
    let top = 0;
    stack[top++] = start; label[start] = id;
    while (top > 0) {
      const q = stack[--top];
      const x = q % W, y = (q - x) / W;
      p.area++;
      p.minX = Math.min(p.minX, x); p.maxX = Math.max(p.maxX, x);
      p.minY = Math.min(p.minY, y); p.maxY = Math.max(p.maxY, y);
      if (x < bx0 || x >= bx1 || y < by0 || y >= by1) {
        p.out++;
        p.oMinX = Math.min(p.oMinX, x); p.oMaxX = Math.max(p.oMaxX, x);
        p.oMinY = Math.min(p.oMinY, y); p.oMaxY = Math.max(p.oMaxY, y);
      }
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          const nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue;
          const n = ny * W + nx;
          if (on[n] && !label[n]) { label[n] = id; stack[top++] = n; }
        }
      }
    }
    pieces.push(p);
  }
  pieces.sort((a, b) => b.area - a.area);

  // pixel -> viewBox units
  const ux = px => vb.x - pad + px / S;
  const uy = py => vb.y - pad + py / S;
  const range = (lo, hi, f) => round1(f(lo)) + '..' + round1(f(hi + 1));

  const issues = [];
  if (pieces.length === 0) issues.push({ level: 'error', text: 'nothing is drawn' });

  // ink on the outer ring of the margin means it runs past what this check can see
  let runsPastMargin = false;
  for (let x = 0; x < W && !runsPastMargin; x++) {
    if (on[x] || on[(H - 1) * W + x]) runsPastMargin = true;
  }
  for (let y = 0; y < H && !runsPastMargin; y++) {
    if (on[y * W] || on[y * W + W - 1]) runsPastMargin = true;
  }
  if (runsPastMargin) issues.push({ level: 'error', text: 'runs past the checked margin, so it is clipped' });

  pieces.forEach((p, i) => {
    if (p.out > 0) {
      const depth = Math.max(bx0 - p.oMinX, p.oMaxX - (bx1 - 1), by0 - p.oMinY, p.oMaxY - (by1 - 1)) / S;  // how far it reaches past the box, in units
      const where = range(p.oMinX, p.oMaxX, ux) + ' x ' + range(p.oMinY, p.oMaxY, uy);
      if (depth < TOL) issues.push({ level: 'warn', text: 'overhangs the box by ' + round2(depth) + ' units at ' + where + ' (under a pixel)' });
      else issues.push({ level: 'error', text: 'outside the viewBox: ' + round1(p.out / (S * S)) + ' units² reach ' + where + ' (it gets clipped)' });
    } else if (i > 0) {
      const w = (p.maxX - p.minX + 1) / S, h = (p.maxY - p.minY + 1) / S;
      const at = '(' + round1(ux((p.minX + p.maxX + 1) / 2)) + ', ' + round1(uy((p.minY + p.maxY + 1) / 2)) + ')';
      const what = round1(w) + ' x ' + round1(h) + ' units at ' + at;
      if (Math.max(w, h) < SPECK) issues.push({ level: 'error', text: 'floating speck ' + what + ', not joined to the main shape' });
      else issues.push({ level: 'info', text: 'separate piece ' + what });
    }
  });

  // ink on the box edge is allowed, but it is tight: any shift or scale-up will clip it
  const sides = [];
  let left = 0, right = 0, top = 0, bottom = 0;
  for (let y = by0; y < by1; y++) { if (on[y * W + bx0]) left++; if (on[y * W + bx1 - 1]) right++; }
  for (let x = bx0; x < bx1; x++) { if (on[by0 * W + x]) top++; if (on[(by1 - 1) * W + x]) bottom++; }
  if (left) sides.push('left');
  if (right) sides.push('right');
  if (top) sides.push('top');
  if (bottom) sides.push('bottom');
  if (sides.length) issues.push({ level: 'warn', text: 'touches the ' + sides.join(', ') + ' edge of the box (tight; fine if intended)' });

  return {
    name: file.name,
    ok: !issues.some(i => i.level === 'error'),
    viewBox: vb.x + ' ' + vb.y + ' ' + vb.w + ' ' + vb.h,
    pixelsPerUnit: S,
    issues
  };
}

async function run() {
  const files = JSON.parse(document.getElementById('inputs').textContent);
  const results = [];
  for (const file of files) {
    try {
      results.push(await checkOne(file));
    } catch (e) {
      results.push({ name: file.name, ok: false, viewBox: '', issues: [{ level: 'error', text: String(e.message || e) }] });
    }
  }
  document.getElementById('result').textContent = JSON.stringify(results);
}
window.addEventListener('load', run);
'@
$checkJs = $checkJs.Replace('__SPECK__', $speckText).Replace('__TOL__', $tolText)

$page = @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>svg check</title></head>
<body>
<script id="inputs" type="application/json">$inputJson</script>
<script id="result" type="application/json">[]</script>
<script>
$checkJs
</script>
</body></html>
"@

$pagePath = Join-Path $profileDir 'check.html'
$dumpPath = Join-Path $profileDir 'check-dump.html'
$log = Join-Path $profileDir 'check.log'
Set-Content -LiteralPath $pagePath -Value $page -Encoding utf8
Remove-Item -LiteralPath $dumpPath -ErrorAction SilentlyContinue
$chromeArgs = @(
    '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    "--user-data-dir=""$profileDir""", '--virtual-time-budget=20000', '--dump-dom',
    ([Uri]$pagePath).AbsoluteUri
)
Start-Process -FilePath $Browser -ArgumentList $chromeArgs -Wait -NoNewWindow -RedirectStandardOutput $dumpPath -RedirectStandardError $log | Out-Null

$dump = if (Test-Path -LiteralPath $dumpPath) { Get-Content -Raw -LiteralPath $dumpPath } else { '' }
$match = [regex]::Match($dump, '<script id="result" type="application/json">(.*?)</script>', 'Singleline')
if (-not $match.Success) { throw "The browser returned no results. See $log" }
$results = @($match.Groups[1].Value | ConvertFrom-Json)

if ($Json) {
    ConvertTo-Json -InputObject $results -Depth 6
} else {
    foreach ($r in $results) {
        $verdict = if ($r.ok) { 'PASS' } else { 'FAIL' }
        Write-Output ('{0}  {1}   viewBox {2}' -f $verdict, $r.name, $r.viewBox)
        foreach ($i in @($r.issues)) { Write-Output ('      {0,-5} {1}' -f $i.level.ToUpper(), $i.text) }
    }
}
if (@($results | Where-Object { -not $_.ok }).Count -gt 0) { exit 1 }
