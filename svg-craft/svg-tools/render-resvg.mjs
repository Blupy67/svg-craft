// render-resvg.mjs - renders SVG files to PNG with resvg (no browser needed).
// Usage:  node render-resvg.mjs <out-dir> <sizes> <file.svg>... [--silhouette] [--bg <css colour>]
//   <sizes> is a comma list of widths in pixels, for example 16,24,96
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const { Resvg } = createRequire(import.meta.url)('@resvg/resvg-js');

const argv = process.argv.slice(2);
const silhouetteMode = argv.includes('--silhouette');
const bgAt = argv.indexOf('--bg');
const background = bgAt >= 0 ? argv[bgAt + 1] : undefined;
const positional = argv.filter((a, i) => !a.startsWith('--') && (bgAt < 0 || i !== bgAt + 1));
const [outDir, sizeList, ...files] = positional;

if (!outDir || !sizeList || files.length === 0) {
    console.error('usage: node render-resvg.mjs <out-dir> <sizes> <file.svg>... [--silhouette] [--bg <colour>]');
    process.exit(2);
}

const sizes = sizeList.split(',').map(Number);
fs.mkdirSync(outDir, { recursive: true });

// silhouette: every fill and stroke becomes solid black (fill="none" is left alone)
const toSilhouette = svg => svg.replace(/(fill|stroke)="(?!none")[^"]*"/g, '$1="#000"');

for (const file of files) {
    const source = fs.readFileSync(file, 'utf8');
    const svg = silhouetteMode ? toSilhouette(source) : source;
    const base = path.basename(file, path.extname(file));
    for (const size of sizes) {
        const options = { fitTo: { mode: 'width', value: size } };
        if (background) options.background = background;
        const png = new Resvg(svg, options).render().asPng();
        const target = path.join(outDir, `${base}-${size}${silhouetteMode ? '-silhouette' : ''}.png`);
        fs.writeFileSync(target, png);
        console.log(target);
    }
}
