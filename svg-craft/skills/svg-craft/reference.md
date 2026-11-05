# SVG reference

Read this before drawing or fixing SVG. Each entry is a rule that is easy to get wrong, with the fix. After any change, render the art with `render-svg`, read the PNG, and run `check-svg`.

## Canvas and coordinates

- Set `viewBox` to the size you design on (`0 0 24 24` for icons). The viewBox scales the art to any display size, so set `width` and `height` only when a fixed size is required.
- Keep art at least 2 units inside the viewBox edges. A stroke extends half its width beyond its path, so include strokes when you measure margins.
- The y axis points down. `rotate(a)` turns clockwise on screen for positive `a`.

## Shapes and paths

- Use primitives (`rect` with `rx`, `circle`, `ellipse`, `polygon`, `line`) when they fit. They are easier to measure and edit than path data.
- Path commands: `M` move, `L` line, `H` and `V` horizontal and vertical lines, `C` and `S` cubic curves, `Q` and `T` quadratic curves, `A` arc, `Z` close. Uppercase is absolute, lowercase is relative.
- Arc flags: `A rx ry rotation large-arc sweep x y`. `large-arc` 1 takes the longer of the two possible arcs. `sweep` 1 draws clockwise on screen.
- Holes: with the default `fill-rule="nonzero"`, overlapping subpaths drawn in the same direction stay filled. Use `fill-rule="evenodd"` to cut holes where subpaths overlap.
- A fill closes its path automatically, but a stroke does not. Add `Z` when a closed outline must be stroked.

## Strokes

- A stroke is centred on its path, so half of it lies outside the fill geometry.
- `stroke-linecap="round"` and `stroke-linejoin="round"` give clean line ends and corners. A round cap extends half the stroke width past its end point.
- Keep one stroke width per icon set. At 16 px, 1 or 2 units reads best. Check the smallest size you ship.
- `vector-effect="non-scaling-stroke"` keeps a stroke's width fixed when the art is scaled. Browsers support it; check other renderers before you rely on it.

## Transforms

- Transforms apply right to left. In `translate(12 12) rotate(30)`, the shape is rotated about the origin first and then moved to the centre.
- To rotate or scale a shape about its own centre, draw it around the origin, transform it, then translate it into place.
- On SVG elements, `transform-origin` defaults to `0 0` (the top left of the user space), not to the centre as it does for HTML elements.

## Clipping and masking

- `clipPath` cuts art to a hard-edged shape. Its content is geometry only: shapes, `text` or `use`, with fills and strokes ignored.
- `mask` uses luminance: white shows, black hides, grey fades. Use it for soft edges.
- To keep a gradient or pattern inside a shape, clip it instead of drawing extra shapes over the edge.

## Gradients

- By default gradient coordinates use the shape's own box (`gradientUnits="objectBoundingBox"`). `x1="0" y1="0" x2="0" y2="1"` runs from the top to the bottom of the shape.
- Each `stop` has an `offset` from 0 to 1 and a `stop-color`, with an optional `stop-opacity`.
- Reference a gradient with `fill="url(#id)"`, and give each gradient an id that no other element uses.

## Filters and glows

- The default filter region is the shape's box plus 10% on each side, so a blur larger than that is cut off. Set the region yourself. `x="-100%" y="-100%" width="300%" height="300%"` is a safe start for a glow.
- A glow is `feGaussianBlur` merged under the original with `feMerge`: `feMergeNode in="blur"` first, then `feMergeNode in="SourceGraphic"`.
- Filters cost render time. Use them sparingly, and avoid large blur radii in art that is drawn many times.
- Renderers differ on blur tails. The Chrome render is the reference; resvg is only for shapes.

## Text and reuse

- Convert text to paths for icons and logos. Fonts differ between machines, so live text changes shape.
- `<use href="#id">` repeats a shape. Browsers draw it, but `svg-geom` does not measure `use`, so inline the shape when exact checks matter.

## Colour

- `fill="currentColor"` makes an inline icon take the text colour of the page it sits in.
- Hard-coded colours are right for stored art and sprites.

## Accessibility

- Put `<title>` as the first child of the root element to name the image, for example `<title>Save</title>`.
- A decorative icon next to a text label can be hidden from screen readers with `aria-hidden="true"` on the inline `svg`.

## Pixel crispness

- Edges that fall on whole pixels at the target size look sharp. A 1-pixel line centred on `x.5` is crisp at 16 px.
- Check every icon at the smallest size it will be shown at, and at 96 px to see the shape clearly.

## Cleaning up

- Remove editor metadata (Inkscape or Illustrator namespaces and attributes) and unused `defs`. `svg-minify` does this and checks the pixels.
- Keep every `id` that another element refers to (`url(#id)`, `href="#id"`). `svg-minify` keeps ids.
- Round numbers to 2 or 3 decimals. `svg-minify --precision auto` tries each setting and keeps the smallest one that draws the same.

## Before a file goes into a project

1. `check-svg`: no errors (clipped shapes, floating specks). Read the warnings.
2. `svg-geom bounds`: exit code 0 for every solid shape.
3. `render-svg` at the smallest and largest sizes, and read the PNG.
4. `svg-minify`, then `check-svg` again on the minified file.
