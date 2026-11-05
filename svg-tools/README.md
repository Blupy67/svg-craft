# svg-tools

Tools for drawing and checking SVG art. They run from any folder: use the full paths below. Run the commands in PowerShell.

Node is the portable copy at `$HOME\.claude\svg-tools\node-v26.13.0-win-x64\node.exe`. It is not on PATH, and no admin rights are needed. Every Node command below uses that full path.

## Commands

| Task | Command |
|---|---|
| Contact sheet at real sizes (Chrome) | `pwsh -File "$HOME\.claude\svg-tools\render-svg.ps1" -Path <files> -Sizes 16,24,96 -Out <png>` (add `-Compare <reference files>` only when there is existing art to match, and `-Silhouette` or `-Background '#hex'`) |
| Clipping and speck checker (Chrome) | `pwsh -File "$HOME\.claude\svg-tools\check-svg.ps1" -Path <files>` (`-Speck`, `-Tolerance`, `-Json`; exit 1 on errors) |
| Exact bounds of every shape | `& "$HOME\.claude\svg-tools\node-v26.13.0-win-x64\node.exe" "$HOME\.claude\svg-tools\svg-geom.mjs" bounds <in.svg> [--json]` (exit 1 if a solid shape leaves the viewBox) |
| Silhouette: solid shapes as one path | `& "$HOME\.claude\svg-tools\node-v26.13.0-win-x64\node.exe" "$HOME\.claude\svg-tools\svg-geom.mjs" silhouette <in.svg> <out.svg> [--effects]` |
| Outline drawn under the art | `& "$HOME\.claude\svg-tools\node-v26.13.0-win-x64\node.exe" "$HOME\.claude\svg-tools\svg-geom.mjs" outline <in.svg> <out.svg> [--width 2] [--color #1d2a1f] [--effects]` |
| Shrink the final SVG (svgo, with a pixel check) | `& "$HOME\.claude\svg-tools\node-v26.13.0-win-x64\node.exe" "$HOME\.claude\svg-tools\svg-minify.mjs" <in.svg> <out.svg> [--precision auto\|2\|3\|4] [--tolerance 4]` |
| Quick PNG without a browser (resvg) | `& "$HOME\.claude\svg-tools\node-v26.13.0-win-x64\node.exe" "$HOME\.claude\svg-tools\render-resvg.mjs" <out-dir> 16,96 <files> [--silhouette] [--bg '#hex']` |
| Add a library | `pwsh -File "$HOME\.claude\svg-tools\add-lib.ps1" -Package <name> -Version <exact> -Purpose "<why>"` |
| Test everything | `pwsh -File "$HOME\.claude\svg-tools\selftest.ps1"` (16 tests; self-contained: it creates and deletes its own test files) |

## Files

- `samples\`: empty and optional. Put your own reference SVGs here, or in a subfolder, to match them with `-Compare`. See `samples\README.md`.
- `LIBRARIES.md`: every library installed here, with licence and publish date.

## How the minifier decides

`svg-minify` tries rounding to 2, 3 and 4 decimals, with and without `mergePaths`. It draws the original and each candidate with resvg at 512 px, and a candidate passes only if at most 0.05% of pixels differ by more than 4/255. The smallest passing candidate is written. If none is smaller, the original is copied. It keeps the viewBox and every id, and it leaves `convertTransform` off because that rewrite moved glow edges. A file that fails the check is never written over.

## Limits

- The checker and the renderers work on pixels, so they see glows and blurs. They do not give exact coordinates.
- `svg-geom` gives exact coordinates for shapes, strokes, clip-paths, transforms and gradient edges. It does not measure filters, masks, `<use>`, `<text>` or `<image>`.
- On the self-test's own test files, `svg-geom` and the checker give the same verdict for every icon, illustration and problem file (the self-test checks this). Glows from filters are where the two can differ.
- The minifier's pixel check uses resvg. It catches differences that resvg draws, so re-check the minified file with `check-svg` before it goes into a project.
