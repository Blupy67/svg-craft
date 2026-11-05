---
name: svg-craft
description: Draws, edits and reviews SVG artwork (icons, sprites, illustrations, and SVG built in code). Use whenever SVG drawing quality matters. Renders PNG sheets at real pixel sizes, with existing art alongside new art for comparison, checks for shapes clipped outside the viewBox and for floating specks, measures exact geometry, merges silhouettes and draws outlines, and minifies the final SVG with a pixel check.
---

# SVG craft

Drawing SVG blind produces lopsided shapes and clipped edges. Work in a loop: plan, draw, render, check, critique, fix. All tools live in `$HOME\.claude\svg-tools` and run from any folder. Run these commands in PowerShell: `$HOME` is a PowerShell variable for the user's profile folder, so the same commands work on any machine. Every Node command uses the full path to `node.exe`, because Node is not on PATH.

If `$HOME\.claude\svg-tools` does not exist, ask the user to run `setup.ps1` from the svg-craft repository before you use these tools.

Before a drawing, read `$HOME\.claude\skills\svg-craft\reference.md` for SVG techniques and the mistakes that come up most often.

## Tools

- **Render a contact sheet, then Read the PNG** (Chrome, the reference renderer):
  `pwsh -File "$HOME\.claude\svg-tools\render-svg.ps1" -Path <new files> -Sizes 16,24,48,96 -Out <scratchpad>\sheet.png`
  `-Compare <reference files>` puts existing art in REFERENCE rows above the NEW rows, so style and visual weight can be compared on one sheet. Use it only when the project already has art the new art must match, or when the user has put reference SVGs in `$HOME\.claude\svg-tools\samples\`. Otherwise leave it out. Example: `-Compare "$HOME\.claude\svg-tools\samples\my-art\logo.svg"`.
  `-Silhouette` fills every shape solid black (does the outline read alone?). `-Background '#hex'` tests on the real background.
- **Check for mechanical problems:** `pwsh -File "$HOME\.claude\svg-tools\check-svg.ps1" -Path <files>`
  Errors: shapes outside the viewBox (clipped) and floating specks. Warnings: ink touching the box edge, or overhangs under half a unit. Options: `-Speck <units>`, `-Tolerance <units>`, `-Json`. Exit code 1 when a file fails. It sees everything visible, including glows and blurs.
- **Exact geometry, no browser:** `& "$HOME\.claude\svg-tools\node-v26.13.0-win-x64\node.exe" "$HOME\.claude\svg-tools\svg-geom.mjs" <command>`
  - `bounds <in.svg> [--json]`: the exact box of every shape, and which solid shapes leave the viewBox (exit 1 if any do).
  - `silhouette <in.svg> <out.svg> [--effects]`: the solid shapes merged into one clean path.
  - `outline <in.svg> <out.svg> [--width 2] [--color #1d2a1f] [--effects]`: that silhouette as a solid outline under the art.
  It measures shapes, strokes, clip-paths, transforms and gradient edges. It does not measure filters (glows, blurs), masks, `<use>`, `<text>` or `<image>`; use check-svg for those.
- **Shrink the final SVG before it goes into a project:** `& "$HOME\.claude\svg-tools\node-v26.13.0-win-x64\node.exe" "$HOME\.claude\svg-tools\svg-minify.mjs" <in.svg> <out.svg> [--precision auto|2|3|4]`
  It rounds numbers to fewer decimals and drops redundant markup (svgo). Before anything is written, the original and each candidate are drawn at 512 px with resvg, and a candidate passes only if at most 0.05% of pixels differ by more than 4/255. The smallest passing candidate is written; if none is smaller, the original is copied. The viewBox and ids are kept. Run check-svg on the result before it goes in.
- **Quick PNG without a browser:** `& "$HOME\.claude\svg-tools\node-v26.13.0-win-x64\node.exe" "$HOME\.claude\svg-tools\render-resvg.mjs" <out-dir> 16,96 <files> [--silhouette]`. resvg draws soft glows differently from Chrome, so use it for shapes only.
- **Libraries:** see `$HOME\.claude\svg-tools\LIBRARIES.md` (polygon-clipping for geometry, svgo for minifying). Add one with `pwsh -File "$HOME\.claude\svg-tools\add-lib.ps1" -Package <name> -Version <exact> -Purpose "<why>"`. It refuses packages younger than 14 days and licences outside its allowlist, and it never runs install scripts.
- **Self-test:** `pwsh -File "$HOME\.claude\svg-tools\selftest.ps1"` (16 tests). Run it after changing any tool. It is self-contained: it writes its own geometric test SVGs to a temporary folder, runs the checks on them, and deletes that folder afterward. It never reads `samples\` or your project files.

Put renders in the scratchpad or a working folder, not in the project, unless asked.

## Process

1. **Anatomy first.** List the parts with rough boxes and their back-to-front order before writing any path data.
2. **Silhouette first.** Draw the big shapes, then render with `-Silhouette` at 16 and 24 px. If it does not read, redesign before adding detail.
3. **Details second.** Highlights, veins, shading. Fewer, clearer elements beat many small ones.
4. **Compare when there is existing art to match.** Render the new art with `-Compare` next to that art, and check size and visual weight, not just the shape. With nothing to match, skip the comparison and judge the art from its renders.
5. **Outlines.** For a thick outline, `svg-geom outline` draws the merged silhouette under the art, so overlapping shapes get one outline with no seams. Or draw each shape with a dark stroke at double the outline width, then the same shapes filled with no stroke.
6. **Helpers over hand-typed coordinates.** Write small functions (leaf, petal, radial rays, fruit silhouette) and tune their numbers, instead of redrawing path strings.
7. **Render and check after every change.** Read the sheet and critique in specific terms: where the problem is, what is wrong, what it should look like. Then fix and repeat.

## Rules of thumb

- Keep everything inside the viewBox unless the project says otherwise. Remove stray specks unless they are deliberate (sparkles are fine when intended).
- Keep one viewBox size and one stroke width per icon set.
- Before a file goes into a project: check-svg, then svg-minify, then check-svg again on the minified file.
- If the project has its own art or style rules (memory notes, CLAUDE.md, a spec file), follow them over these defaults. If the project says its art is code-drawn, do not substitute generated images.
- Claude cannot see SVG output without a render. Never judge art from the source alone.
