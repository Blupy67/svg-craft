// svg-geom.mjs - exact geometry for SVG files, no browser needed.
//   node svg-geom.mjs bounds <in.svg> [--json]
//       exact box of every drawn shape. A solid shape reaching 0.5+ units past the viewBox makes it exit 1.
//   node svg-geom.mjs silhouette <in.svg> <out.svg> [--effects]
//       the solid shapes merged into one clean path (--effects also merges gradient and faint shapes)
//   node svg-geom.mjs outline <in.svg> <out.svg> [--width 2] [--color #1d2a1f] [--effects]
//       the silhouette as a solid outline, drawn under the art
// Libraries (see LIBRARIES.md): polygon-clipping (boolean ops), svgpath (arcs to curves), @xmldom/xmldom (reads SVG).
// Handled: transforms, nested groups, clip-paths (exact intersection), inherited fill, stroke and opacity.
// Not handled: masks, filters (glows, blurs), <use>, <text>, <image>. check-svg.ps1 covers those by rendering.
// Gradient fills and faint fills (opacity under 0.15) are "effects": reported, but not counted as solid art.
import fs from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const polygonClipping = require('polygon-clipping');
const svgpath = require('svgpath');
const { DOMParser } = require('@xmldom/xmldom');

const SHAPES = new Set(['path', 'rect', 'circle', 'ellipse', 'line', 'polyline', 'polygon']);
const GROUPS = new Set(['g', 'a', 'svg']);
const NOT_DRAWN = new Set(['defs', 'clipPath', 'mask', 'pattern', 'symbol', 'marker', 'linearGradient',
    'radialGradient', 'filter', 'style', 'title', 'desc', 'metadata', 'script']);
const UNMEASURED = new Set(['use', 'image', 'text', 'foreignObject']);
const IDENTITY = [1, 0, 0, 1, 0, 0];
const STEP = 0.5;     // sample curves about every half a unit
const TOL = 0.5;      // a solid shape must reach this far past the viewBox to count as outside
const FAINT = 0.15;   // a fill with less opacity than this is an effect, not solid art
const NOTE = {
    filter: label => `filter on ${label} is not applied, so glows and blurs past the geometry are not measured`,
    mask: label => `mask on ${label} is not applied, so parts it hides are measured`,
};
const usage = 'usage:\n  svg-geom.mjs bounds <in.svg> [--json]\n  svg-geom.mjs silhouette <in.svg> <out.svg> [--effects]\n' +
    '  svg-geom.mjs outline <in.svg> <out.svg> [--width 2] [--color #1d2a1f] [--effects]';

// ---- matrices as [a, b, c, d, e, f], the same order SVG uses ----
const mul = (m, n) => [
    m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1],
    m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3],
    m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5],
];
const apply = (m, [x, y]) => [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];
const scaleOf = m => Math.sqrt(Math.abs(m[0] * m[3] - m[1] * m[2]));
const round = v => Math.round(v * 1000) / 1000;
const show = v => Math.round(v * 100) / 100;

function parseTransform(str) {
    let m = IDENTITY;
    if (!str) return m;
    const re = /(matrix|translate|scale|rotate|skewX|skewY)\s*\(([^)]*)\)/g;
    let t;
    while ((t = re.exec(str))) {
        const a = t[2].trim().split(/[\s,]+/).filter(Boolean).map(Number);
        let n;
        switch (t[1]) {
            case 'matrix': n = a; break;
            case 'translate': n = [1, 0, 0, 1, a[0], a[1] || 0]; break;
            case 'scale': n = [a[0], 0, 0, a[1] ?? a[0], 0, 0]; break;
            case 'rotate': {
                const r = a[0] * Math.PI / 180, c = Math.cos(r), s = Math.sin(r);
                n = [c, s, -s, c, 0, 0];
                if (a.length === 3) {   // rotate about a point: move it to the origin, rotate, move back
                    n = mul(mul([1, 0, 0, 1, a[1], a[2]], n), [1, 0, 0, 1, -a[1], -a[2]]);
                }
                break;
            }
            case 'skewX': n = [1, 0, Math.tan(a[0] * Math.PI / 180), 1, 0, 0]; break;
            case 'skewY': n = [1, Math.tan(a[0] * Math.PI / 180), 0, 1, 0, 0]; break;
        }
        m = mul(m, n);
    }
    return m;
}

const num = (el, name, fallback = 0) => {
    const v = parseFloat(el.getAttribute(name));
    return Number.isFinite(v) ? v : fallback;
};

// a style="" declaration beats the presentation attribute, as in the browser
function prop(el, name) {
    const style = el.getAttribute('style') || '';
    const hit = style.match(new RegExp('(?:^|;)\\s*' + name + '\\s*:\\s*([^;]+)'));
    if (hit) return hit[1].trim();
    return el.hasAttribute(name) ? el.getAttribute(name).trim() : null;
}

// ---- shapes become path data ----
const ellipseD = (cx, cy, rx, ry) => (rx > 0 && ry > 0)
    ? `M${cx - rx} ${cy}A${rx} ${ry} 0 1 0 ${cx + rx} ${cy}A${rx} ${ry} 0 1 0 ${cx - rx} ${cy}Z` : '';

function shapeToPath(el, tag) {
    switch (tag) {
        case 'path': return el.getAttribute('d') || '';
        case 'rect': {
            const x = num(el, 'x'), y = num(el, 'y'), w = num(el, 'width'), h = num(el, 'height');
            let rx = num(el, 'rx', NaN), ry = num(el, 'ry', NaN);
            if (Number.isNaN(rx)) rx = ry;
            if (Number.isNaN(ry)) ry = rx;
            if (Number.isNaN(rx)) rx = ry = 0;
            rx = Math.min(rx, w / 2); ry = Math.min(ry, h / 2);
            if (!(rx > 0 && ry > 0)) return `M${x} ${y}H${x + w}V${y + h}H${x}Z`;
            return `M${x + rx} ${y}H${x + w - rx}A${rx} ${ry} 0 0 1 ${x + w} ${y + ry}V${y + h - ry}` +
                `A${rx} ${ry} 0 0 1 ${x + w - rx} ${y + h}H${x + rx}A${rx} ${ry} 0 0 1 ${x} ${y + h - ry}` +
                `V${y + ry}A${rx} ${ry} 0 0 1 ${x + rx} ${y}Z`;
        }
        case 'circle': { const r = num(el, 'r'); return ellipseD(num(el, 'cx'), num(el, 'cy'), r, r); }
        case 'ellipse': return ellipseD(num(el, 'cx'), num(el, 'cy'), num(el, 'rx'), num(el, 'ry'));
        case 'line': return `M${num(el, 'x1')} ${num(el, 'y1')}L${num(el, 'x2')} ${num(el, 'y2')}`;
        case 'polyline':
        case 'polygon': {
            const v = (el.getAttribute('points') || '').trim().split(/[\s,]+/).map(Number).filter(Number.isFinite);
            let d = '';
            for (let i = 0; i + 1 < v.length; i += 2) d += (i ? 'L' : 'M') + v[i] + ' ' + v[i + 1];
            return tag === 'polygon' && d ? d + 'Z' : d;
        }
    }
    return '';
}

// ---- path data -> subpaths of sampled points (arcs become curves first, curves are sampled) ----
const dist = (a, b) => Math.hypot(b[0] - a[0], b[1] - a[1]);

function sampleCubic(p0, p1, p2, p3) {
    const n = Math.min(160, Math.max(6, Math.ceil((dist(p0, p1) + dist(p1, p2) + dist(p2, p3)) / STEP)));
    const out = [];
    for (let i = 1; i <= n; i++) {
        const t = i / n, u = 1 - t;
        out.push([0, 1].map(k => u * u * u * p0[k] + 3 * u * u * t * p1[k] + 3 * u * t * t * p2[k] + t * t * t * p3[k]));
    }
    return out;
}

function sampleQuad(p0, p1, p2) {
    const n = Math.min(160, Math.max(6, Math.ceil((dist(p0, p1) + dist(p1, p2)) / STEP)));
    const out = [];
    for (let i = 1; i <= n; i++) {
        const t = i / n, u = 1 - t;
        out.push([0, 1].map(k => u * u * p0[k] + 2 * u * t * p1[k] + t * t * p2[k]));
    }
    return out;
}

function subpathsOf(d, note) {
    if (!d || !d.trim()) return [];
    const sp = svgpath(d).abs().unarc().unshort();
    if (sp.err) note(`path data is malformed (${sp.err}); the rest of it is skipped`);
    const tokens = sp.toString().match(/[A-Z]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?/g) || [];
    const count = { M: 2, L: 2, H: 1, V: 1, C: 6, Q: 4, Z: 0 };
    const subs = [];
    let cur = null, x = 0, y = 0, sx = 0, sy = 0;
    const start = () => { if (!cur) { cur = [[x, y]]; subs.push(cur); } };
    let k = 0;
    while (k < tokens.length) {
        const c = tokens[k];
        if (!/^[A-Z]$/.test(c)) { k++; continue; }     // a stray number is dropped
        k++;
        if (!(c in count)) break;                       // unknown command: keep what came before
        if (c === 'Z') { cur = null; x = sx; y = sy; continue; }
        let firstGroup = true;
        while (k < tokens.length && !/^[A-Z]$/.test(tokens[k])) {
            if (k + count[c] > tokens.length) { k = tokens.length; break; }
            const v = tokens.slice(k, k + count[c]).map(Number);
            k += count[c];
            if (c === 'M') {
                if (firstGroup) { cur = [[v[0], v[1]]]; subs.push(cur); sx = x = v[0]; sy = y = v[1]; }
                else { cur.push([v[0], v[1]]); x = v[0]; y = v[1]; }   // extra pairs after M are lineto
            } else if (c === 'L') {
                start(); cur.push([v[0], v[1]]); x = v[0]; y = v[1];
            } else if (c === 'H') {
                start(); cur.push([v[0], y]); x = v[0];
            } else if (c === 'V') {
                start(); cur.push([x, v[0]]); y = v[0];
            } else if (c === 'C') {
                start(); cur.push(...sampleCubic([x, y], [v[0], v[1]], [v[2], v[3]], [v[4], v[5]])); x = v[4]; y = v[5];
            } else if (c === 'Q') {
                start(); cur.push(...sampleQuad([x, y], [v[0], v[1]], [v[2], v[3]])); x = v[2]; y = v[3];
            }
            firstGroup = false;
        }
    }
    return subs;
}

// ---- polygons for the boolean library ----
function closeRing(pts) {
    if (pts.length < 3) return null;
    const ring = pts.map(p => [p[0], p[1]]);
    const a = ring[0], b = ring[ring.length - 1];
    if (a[0] !== b[0] || a[1] !== b[1]) ring.push([a[0], a[1]]);
    return ring;
}

// one element's fill: its subpaths combined even-odd, so a hole stays a hole. Returned as a MultiPolygon.
function fillOf(subs, m) {
    const polys = subs.map(s => closeRing(s.map(p => apply(m, p)))).filter(Boolean).map(r => [r]);
    if (!polys.length) return null;
    return polys.length === 1 ? [polys[0]] : polygonClipping.xor(...polys);
}

const unionOf = list => (list.length ? polygonClipping.union(...list) : []);

function geomToPath(geom) {
    return geom.map(poly => poly.map(ring => 'M' + ring.map(([x, y]) => round(x) + ' ' + round(y)).join('L') + 'Z')
        .join('')).join('');
}

function boxOf(rings) {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const ring of rings) {
        for (const [x, y] of ring) {
            if (x < x0) x0 = x;
            if (x > x1) x1 = x;
            if (y < y0) y0 = y;
            if (y > y1) y1 = y;
        }
    }
    return Number.isFinite(x0) ? [x0, y0, x1, y1] : null;
}

const outsideBy = (box, [vx, vy, vw, vh]) =>
    Math.max(0, vx - box[0], box[2] - (vx + vw), vy - box[1], box[3] - (vy + vh));

// the region that clip-path="url(#id)" puts on an element, in root coordinates, intersected with any clip it inherits
function clipFor(el, m, inherited, st, label) {
    const ref = prop(el, 'clip-path');
    const hit = ref && ref.match(/url\(\s*#([^)\s]+)\s*\)/);
    if (!hit) return inherited;
    const clipEl = st.clips.get(hit[1]);
    if (!clipEl) { st.notes.add(`${label} points at a missing clip-path, which is ignored`); return inherited; }
    let region = [];
    for (const kid of Array.from(clipEl.childNodes)) {
        if (kid.nodeType !== 1) continue;
        const tag = kid.localName || kid.tagName;
        if (!SHAPES.has(tag)) continue;
        const g = fillOf(subpathsOf(shapeToPath(kid, tag), () => {}), mul(m, parseTransform(kid.getAttribute('transform'))));
        if (g) region = region.length ? polygonClipping.union(region, g) : g;
    }
    return inherited ? polygonClipping.intersection(inherited, region) : region;
}

// the opacity at a gradient's outer edge: its last stop (the one furthest along); 'transparent' counts as 0
function edgeOpacity(grad) {
    const stops = Array.from(grad.getElementsByTagName('stop'));
    if (!stops.length) return 1;
    const offsetOf = s => {
        const v = s.getAttribute('offset') || '0';
        return v.endsWith('%') ? parseFloat(v) / 100 : parseFloat(v) || 0;
    };
    const last = stops.reduce((a, b) => (offsetOf(b) >= offsetOf(a) ? b : a));
    if ((prop(last, 'stop-color') || '').toLowerCase() === 'transparent') return 0;
    const op = parseFloat(prop(last, 'stop-opacity'));
    return Number.isFinite(op) ? op : 1;
}

// ---- walk the SVG tree, collecting every drawn shape ----
function walk(el, ctx, st) {
    for (const child of Array.from(el.childNodes)) {
        if (child.nodeType !== 1) continue;
        const tag = child.localName || child.tagName;
        const id = child.getAttribute('id') || '';
        const label = `<${tag}>${id ? ' #' + id : ''}`;
        if (NOT_DRAWN.has(tag)) continue;
        if (UNMEASURED.has(tag)) { st.notes.add(`${label} is not measured by svg-geom`); continue; }
        if (prop(child, 'display') === 'none' || prop(child, 'visibility') === 'hidden') continue;

        const m = mul(ctx.m, parseTransform(child.getAttribute('transform')));
        const ownOpacity = parseFloat(prop(child, 'opacity'));
        const ownFillOpacity = parseFloat(prop(child, 'fill-opacity'));
        const fillProp = prop(child, 'fill'), strokeProp = prop(child, 'stroke'), widthProp = prop(child, 'stroke-width');
        const next = {
            m,
            fill: fillProp && fillProp !== 'inherit' ? fillProp : ctx.fill,
            stroke: strokeProp && strokeProp !== 'inherit' ? strokeProp : ctx.stroke,
            strokeWidth: widthProp ? parseFloat(widthProp) : ctx.strokeWidth,
            opacity: ctx.opacity * (Number.isFinite(ownOpacity) ? ownOpacity : 1),
            fillOpacity: Number.isFinite(ownFillOpacity) ? ownFillOpacity : ctx.fillOpacity,
            clip: clipFor(child, m, ctx.clip, st, label),
        };
        if (next.opacity === 0) continue;

        for (const name of ['mask', 'filter']) {
            const v = prop(child, name);
            if (v && v !== 'none') st.notes.add(NOTE[name](label));
        }
        if (GROUPS.has(tag)) {
            if (tag === 'svg' && child !== st.root) st.notes.add(`a nested <svg>${id ? ' #' + id : ''} is treated as a group`);
            walk(child, next, st);
            continue;
        }
        if (!SHAPES.has(tag)) continue;

        const subs = subpathsOf(shapeToPath(child, tag), msg => st.notes.add(`${label}: ${msg}`));
        const pts = subs.flat().map(p => apply(m, p));
        if (!pts.length) continue;

        let kind = 'none';
        if (next.fill && next.fill !== 'none' && next.fill !== 'transparent') {
            const alpha = next.opacity * next.fillOpacity;
            const isUrl = next.fill.startsWith('url(');
            let edge = alpha;   // a gradient is judged by its outer edge, which is its last stop
            if (isUrl) {
                const ref = next.fill.match(/url\(\s*#([^)\s]+)\s*\)/);
                const grad = ref ? st.gradients.get(ref[1]) : null;
                if (grad) edge = alpha * edgeOpacity(grad);
            }
            kind = edge < FAINT ? (isUrl ? 'gradient' : 'faint') : 'solid';
        }
        const strokeVisible = !!next.stroke && next.stroke !== 'none' && next.strokeWidth > 0 && next.opacity >= FAINT;
        if (kind === 'none') {
            if (!strokeVisible) continue;     // neither a fill nor a stroke: nothing is drawn
            kind = 'stroke';
        }
        let geom = kind === 'stroke' ? null : fillOf(subs, m);
        if (!geom && !strokeVisible) continue;                        // no area and no stroke: a zero-size line
        if (geom && next.clip) geom = polygonClipping.intersection(geom, next.clip);
        if (geom && geom.length === 0) continue;                      // clipped away completely: nothing is visible
        if (!geom && next.clip && next.clip.length === 0) continue;   // an empty clip hides strokes too

        let box = geom ? boxOf(geom.flat()) : boxOf([pts]);
        if (next.stroke && next.stroke !== 'none' && next.strokeWidth > 0) {   // a stroke reaches half its width past the path
            const half = next.strokeWidth * scaleOf(m) / 2;
            box = [box[0] - half, box[1] - half, box[2] + half, box[3] + half];
        }
        if (next.clip) {   // strokes are limited to the clip's bounding box (exact for rectangles, a safe limit otherwise)
            const cb = boxOf(next.clip.flat());
            box = [Math.max(box[0], cb[0]), Math.max(box[1], cb[1]), Math.min(box[2], cb[2]), Math.min(box[3], cb[3])];
            if (box[0] > box[2] || box[1] > box[3]) continue;         // entirely outside the clip
        }
        st.shapes.push({ tag, id, kind, box });
        if (geom && kind === 'solid') st.solid.push(geom);
        if (geom && (kind === 'gradient' || kind === 'faint')) st.effects.push(geom);
    }
}

function analyze(file) {
    const text = fs.readFileSync(file, 'utf8');
    const errors = [];
    const doc = new DOMParser({
        onError: (level, message) => { if (level !== 'warning') errors.push(message); },   // @xmldom/xmldom 0.9 API
    }).parseFromString(text, 'image/svg+xml');
    const root = doc.documentElement;
    if (!root || (root.localName || root.tagName) !== 'svg') throw new Error(`${file} is not an SVG document`);
    if (errors.length) throw new Error(`${file} has an XML error: ${errors[0]}`);
    const viewBox = (root.getAttribute('viewBox') || '').trim().split(/[\s,]+/).map(Number);
    if (viewBox.length !== 4 || viewBox.some(v => !Number.isFinite(v)) || viewBox[2] <= 0 || viewBox[3] <= 0) {
        throw new Error(`${file}: the root <svg> needs a viewBox with four numbers`);
    }
    const clips = new Map();
    for (const el of Array.from(root.getElementsByTagName('clipPath'))) {
        if (el.getAttribute('id')) clips.set(el.getAttribute('id'), el);
    }
    const gradients = new Map();
    for (const tagName of ['linearGradient', 'radialGradient']) {
        for (const el of Array.from(root.getElementsByTagName(tagName))) {
            if (el.getAttribute('id')) gradients.set(el.getAttribute('id'), el);
        }
    }
    const st = { root, clips, gradients, shapes: [], solid: [], effects: [], notes: new Set() };
    // the root's own presentation attributes are inherited by everything inside it
    const rootFill = prop(root, 'fill'), rootStroke = prop(root, 'stroke'), rootWidth = prop(root, 'stroke-width');
    const rootOpacity = parseFloat(prop(root, 'opacity')), rootFillOpacity = parseFloat(prop(root, 'fill-opacity'));
    walk(root, {
        m: IDENTITY,
        fill: rootFill && rootFill !== 'inherit' ? rootFill : 'black',
        stroke: rootStroke && rootStroke !== 'inherit' ? rootStroke : 'none',
        strokeWidth: rootWidth ? parseFloat(rootWidth) : 0,
        opacity: Number.isFinite(rootOpacity) ? rootOpacity : 1,
        fillOpacity: Number.isFinite(rootFillOpacity) ? rootFillOpacity : 1,
        clip: null,
    }, st);
    return { text, root, viewBox, shapes: st.shapes, solid: st.solid, effects: st.effects, notes: [...st.notes] };
}

function svgOut(a, inner) {
    const w = a.root.getAttribute('width'), h = a.root.getAttribute('height');
    const size = (w ? ` width="${w}"` : '') + (h ? ` height="${h}"` : '');
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${a.viewBox.join(' ')}"${size}>${inner}</svg>\n`;
}

function cmdBounds(file, asJson) {
    const a = analyze(file);
    const vb = a.viewBox;
    const rows = a.shapes.map(s => ({
        tag: s.tag, id: s.id, kind: s.kind, box: s.box.map(show), outsideBy: show(outsideBy(s.box, vb)),
    }));
    const counted = rows.filter(r => (r.kind === 'solid' || r.kind === 'stroke') && r.outsideBy >= TOL);
    const effectsOut = rows.filter(r => (r.kind === 'gradient' || r.kind === 'faint') && r.outsideBy >= TOL);
    const solidBox = a.solid.length ? boxOf(a.solid.flat()) : null;
    if (asJson) {
        console.log(JSON.stringify({
            file, viewBox: vb, shapes: rows, solidArea: solidBox && solidBox.map(show),
            outside: counted, effectsOutside: effectsOut, notes: a.notes,
        }, null, 2));
    } else {
        const kinds = ['solid', 'stroke', 'gradient', 'faint'].map(k => `${rows.filter(r => r.kind === k).length} ${k}`).join(', ');
        const where = solidBox ? `; solid art spans x ${show(solidBox[0])}..${show(solidBox[2])}, y ${show(solidBox[1])}..${show(solidBox[3])}` : '';
        console.log(`${file}  viewBox ${vb.join(' ')}`);
        console.log(`${rows.length} drawn shape(s): ${kinds}${where}`);
        if (counted.length) {
            console.log(`OUTSIDE the viewBox: ${counted.length} solid shape(s), so they would be clipped`);
            for (const r of counted) {
                console.log(`  <${r.tag}>${r.id ? ' #' + r.id : ''}  x ${r.box[0]}..${r.box[2]}, y ${r.box[1]}..${r.box[3]}  reaches ${r.outsideBy} past the edge`);
            }
        } else {
            console.log('no solid shape reaches past the viewBox');
        }
        if (effectsOut.length) console.log(`not counted: ${effectsOut.length} gradient or faint shape(s) reach past the edge; they may be transparent there`);
        for (const n of a.notes) console.log('note: ' + n);
    }
    return counted.length ? 1 : 0;
}

function cmdSilhouette(inFile, outFile, effects) {
    const a = analyze(inFile);
    const pieces = effects ? [...a.solid, ...a.effects] : a.solid;
    if (!pieces.length) throw new Error(`${inFile} has no solid shapes to merge${effects ? '' : ' (try --effects)'}`);
    fs.writeFileSync(outFile, svgOut(a, `<path d="${geomToPath(unionOf(pieces))}" fill="#000" fill-rule="evenodd"/>`));
    console.log(`wrote ${outFile}: ${pieces.length} piece(s) merged into one path`);
    for (const n of a.notes) console.log('note: ' + n);
    return 0;
}

function cmdOutline(inFile, outFile, width, color, effects) {
    const a = analyze(inFile);
    if (!(width > 0)) throw new Error('--width must be a positive number');
    const pieces = effects ? [...a.solid, ...a.effects] : a.solid;
    if (!pieces.length) throw new Error(`${inFile} has no solid shapes to outline${effects ? '' : ' (try --effects)'}`);
    const union = unionOf(pieces);
    // the silhouette, stroked wide in the outline colour, sits under the art; the stroke's inner half is covered by the art
    const under = `<path d="${geomToPath(union)}" fill="${color}" stroke="${color}" stroke-width="${round(2 * width)}" ` +
        'stroke-linejoin="round" fill-rule="evenodd"/>';
    const at = a.text.indexOf('>', a.text.indexOf('<svg')) + 1;
    fs.writeFileSync(outFile, a.text.slice(0, at) + under + a.text.slice(at));
    const g = boxOf(union.flat());
    const over = outsideBy([g[0] - width, g[1] - width, g[2] + width, g[3] + width], a.viewBox);
    console.log(`wrote ${outFile}: ${width}-unit ${color} outline under ${pieces.length} piece(s)`);
    if (over > 0) console.log(`warning: the outline reaches ${show(over)} units past the viewBox and will be clipped`);
    for (const n of a.notes) console.log('note: ' + n);
    return 0;
}

const [cmd, ...args] = process.argv.slice(2);
const flagValue = (name, fallback) => {
    const i = args.indexOf(name);
    return i >= 0 && args[i + 1] !== undefined ? args[i + 1] : fallback;
};
const positional = args.filter((a, i) => !a.startsWith('--') && !['--width', '--color'].includes(args[i - 1]));
try {
    if (!cmd || !positional[0]) throw new Error(usage);
    if ((cmd === 'silhouette' || cmd === 'outline') && !positional[1]) throw new Error(usage);
    let code;
    if (cmd === 'bounds') code = cmdBounds(positional[0], args.includes('--json'));
    else if (cmd === 'silhouette') code = cmdSilhouette(positional[0], positional[1], args.includes('--effects'));
    else if (cmd === 'outline') {
        code = cmdOutline(positional[0], positional[1], Number(flagValue('--width', 2)), flagValue('--color', '#1d2a1f'), args.includes('--effects'));
    } else throw new Error(usage);
    process.exitCode = code;
} catch (e) {
    console.error('svg-geom: ' + e.message);
    process.exitCode = 1;
}
