// svg-minify.mjs - shrinks an SVG with svgo: rounds numbers to fewer decimals and drops redundant markup.
// Each candidate (precision, with or without mergePaths) is checked by drawing the original and the result with
// the same engine (512 px wide). The smallest candidate that draws the same is written; if none is smaller,
// the original is copied unchanged.
//   node svg-minify.mjs <in.svg> <out.svg> [--precision auto|2|3|4] [--tolerance 4]
// Keeps the viewBox and every id. Off-canvas shapes stay in place, so check-svg.ps1 can still report them.
import fs from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { Resvg } = require('@resvg/resvg-js');
const { optimize } = await import('svgo');

const args = process.argv.slice(2);
const flagValue = (name, fallback) => {
    const i = args.indexOf(name);
    return i >= 0 && args[i + 1] !== undefined ? args[i + 1] : fallback;
};
const positional = args.filter((a, i) => !a.startsWith('--') && !['--precision', '--tolerance'].includes(args[i - 1]));
const [inFile, outFile] = positional;
if (!inFile || !outFile) {
    console.error('usage: node svg-minify.mjs <in.svg> <out.svg> [--precision auto|2|3|4] [--tolerance 4]');
    process.exit(2);
}
const precisionArg = flagValue('--precision', 'auto');
const candidates = precisionArg === 'auto' ? [2, 3, 4] : [Number(precisionArg)];
const tolerance = Number(flagValue('--tolerance', 4));
const MAX_SHARE = 0.0005;   // at most 0.05% of pixels may differ by more than the tolerance

const original = fs.readFileSync(inFile, 'utf8');

function minify(svg, precision, merge) {
    return optimize(svg, {
        multipass: true,
        floatPrecision: precision,
        plugins: [{
            name: 'preset-default',
            // keep ids (references to them must not break), and keep transforms as written: svgo's
            // convertTransform rewrites them and shifts glow edges. mergePaths can change how overlapping
            // subpaths fill, so the pixel check decides whether it stays on
            params: { overrides: { cleanupIds: false, convertTransform: false, mergePaths: merge } },
        }],
    }).data.trimEnd() + '\n';
}

function render(svg) {
    const img = new Resvg(svg, { fitTo: { mode: 'width', value: 512 } }).render();
    return { width: img.width, height: img.height, data: img.pixels };
}

// both files are drawn by the same engine at 512 px wide; the share of pixels that differ is reported
function pixelCheck(svgA, svgB) {
    const a = render(svgA), b = render(svgB);
    if (a.width !== b.width || a.height !== b.height) return { passed: false, text: 'the two renders differ in size' };
    let worst = 0, differing = 0;
    for (let i = 0; i < a.data.length; i += 4) {
        let d = 0;
        for (let k = 0; k < 4; k++) d = Math.max(d, Math.abs(a.data[i + k] - b.data[i + k]));
        if (d > worst) worst = d;
        if (d > tolerance) differing++;
    }
    const share = differing / (a.width * a.height);
    return {
        passed: share <= MAX_SHARE,
        text: `worst difference ${worst}/255, ${differing} pixel(s) over tolerance ${tolerance} (${(share * 100).toFixed(3)}%)`,
    };
}

const before = Buffer.byteLength(original);
// every setting that draws the same is a candidate, and the smallest one is written.
// If none is smaller than the original, the original is copied unchanged.
let chosen = { label: 'the original, unchanged', minified: original };
for (const merge of [true, false]) {
    for (const precision of candidates) {
        const minified = minify(original, precision, merge);
        const check = pixelCheck(original, minified);
        const size = Buffer.byteLength(minified);
        console.log(`precision ${precision}, mergePaths ${merge}: ${size} bytes, ${check.text} -> ${check.passed ? 'accepted' : 'rejected'}`);
        if (check.passed && size < Buffer.byteLength(chosen.minified)) {
            chosen = { label: `precision ${precision}, mergePaths ${merge}`, minified };
        }
    }
}
fs.writeFileSync(outFile, chosen.minified);
const after = Buffer.byteLength(chosen.minified);
console.log(`wrote ${outFile} using ${chosen.label}: ${before} -> ${after} bytes (${Math.round(100 * (1 - after / before))}% smaller)`);
