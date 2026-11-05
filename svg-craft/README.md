# svg-craft

**Give Claude Code a way to see the SVG it draws.** Claude writes SVG as text, so it cannot see the result. svg-craft gives it a drawing process, tools that render its work at real pixel sizes, a checker for clipped shapes and stray specks, exact geometry, and a minifier that only accepts a smaller file if it draws the same. Claude reads the renders and fixes what it sees.

## What you get

- **A skill** (`skills/svg-craft`): tells Claude how to work (plan, draw, render, check, critique, fix) and points to `reference.md`, a guide to SVG techniques and the mistakes that come up most often.
- **Contact sheets**: each file rendered in Chrome at the pixel sizes you choose, with existing art beside new art for comparison.
- **A checker**: finds shapes outside the viewBox, floating specks and edge problems.
- **Exact geometry**, with no browser needed: bounds, one-path silhouettes and outlines.
- **A minifier** that rounds numbers and drops redundant markup, then checks the pixels before it writes the file.
- **A self-test** of 16 checks. It creates its own test files and deletes them afterward.
- **An empty `samples` folder** for your own reference SVGs, if you want Claude to match them.

## Requirements

- Windows 10 or 11. The tools use PowerShell and Windows browser paths.
- PowerShell 7 or later: `winget install --id Microsoft.PowerShell --exact`
- Google Chrome or Microsoft Edge, for the contact sheets and the checker
- An internet connection for setup
- [Claude Code](https://claude.com/claude-code)

No admin rights are needed, and setup does not change PATH.

## Install

```powershell
git clone https://github.com/Blupy67/svg-craft.git
cd svg-craft
pwsh -File .\setup.ps1
pwsh -File "$HOME\.claude\svg-tools\selftest.ps1"
```

No Git? Download the ZIP from the repository page, extract it, and run the same commands in that folder.

Setup copies the skill to `~\.claude\skills\svg-craft` and the tools to `~\.claude\svg-tools`. It downloads a portable Node.js 26.13.0, checks it against the SHA-256 checksums nodejs.org publishes, and unpacks it into `svg-tools`. It then installs the exact npm packages from `package-lock.json` with install scripts turned off. Running setup again updates the install. Pass `-Target <folder>` to install somewhere else.

When the self-test passes, start a new Claude Code session. Claude uses the skill when you ask for SVG art, and you can call it with `/svg-craft`.

## Try it

Ask Claude:

> Draw a watering can as an SVG icon. Check it with svg-craft, fix anything it finds, and minify it.

## Tools

These commands use the default install location. Run them in PowerShell.

| Task | Command |
|---|---|
| Contact sheet at real sizes (Chrome) | `pwsh -File "$HOME\.claude\svg-tools\render-svg.ps1" -Path <files> -Sizes 16,24,96 -Out <png>` |
| Check for clipped shapes and specks (Chrome) | `pwsh -File "$HOME\.claude\svg-tools\check-svg.ps1" -Path <files>` |
| Exact bounds of every shape | `& "$HOME\.claude\svg-tools\node-v26.13.0-win-x64\node.exe" "$HOME\.claude\svg-tools\svg-geom.mjs" bounds <in.svg>` |
| Shrink the final SVG, with a pixel check | `& "$HOME\.claude\svg-tools\node-v26.13.0-win-x64\node.exe" "$HOME\.claude\svg-tools\svg-minify.mjs" <in.svg> <out.svg>` |
| Add a library, with a download guard | `pwsh -File "$HOME\.claude\svg-tools\add-lib.ps1" -Package <name> -Version <exact> -Purpose "<why>"` |
| Run the self-test | `pwsh -File "$HOME\.claude\svg-tools\selftest.ps1"` |

`svg-tools/README.md` lists every option.

## How the minifier decides

`svg-minify` tries rounding to 2, 3 and 4 decimals, with and without `mergePaths`. It draws the original and each candidate with resvg at 512 px. A candidate passes only if at most 0.05% of pixels differ by more than 4/255. The smallest passing candidate is written; otherwise the original is copied. The viewBox and every id are kept.

## Your reference art

The `svg-tools/samples` folder is empty on purpose. If you want Claude to match an existing style, put your reference SVGs there, or in a subfolder, and point `-Compare` at them. The tools and the self-test don't need anything in that folder. Claude uses `-Compare` only when there is existing art to match.

## Limits

- Windows only.
- The checker and the renderers work on pixels. They see glows and blurs but do not give exact coordinates.
- `svg-geom` gives exact coordinates for shapes, strokes, clip paths, transforms and gradient edges. It does not measure filters, masks, `use`, text or images.
- resvg, which the minifier's check uses, draws glows differently from Chrome. Chrome is the reference.

## Troubleshooting

- **"Chrome or Edge was not found"**: install Chrome or Edge, then run the self-test again.
- **"This script requires PowerShell 7"**: install PowerShell 7 (see Requirements) and run the commands with `pwsh`, not `powershell`.
- **Setup cannot reach nodejs.org or the npm registry**: check your internet connection or proxy settings, then run setup again.
- **A self-test check fails**: the failing line names the tool. Run that tool's command on its own to see its full output.

## Uninstall

```powershell
Remove-Item -Recurse "$HOME\.claude\skills\svg-craft", "$HOME\.claude\svg-tools"
```

## Licence

MIT. See [LICENSE](LICENSE). Third-party libraries keep their own licences, and `svg-tools/LIBRARIES.md` lists each one with its licence. Node.js is installed from nodejs.org under its own licence.
