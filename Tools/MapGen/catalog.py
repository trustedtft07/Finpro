"""Render a catalogue sheet of stamps so they can be eyeballed for correctness."""
from PIL import Image, ImageDraw
import tmxlib as T


def render_catalog(stamps, out, cols=12, cell_tiles=11, scale=2, label=True):
    TT = 16
    cw = cell_tiles * TT * scale
    rows = (len(stamps) + cols - 1) // cols
    hdr = 12
    canvas = Image.new('RGBA', (cols * cw, rows * (cw + hdr)), (46, 48, 54, 255))
    d = ImageDraw.Draw(canvas)
    for i, st in enumerate(stamps):
        w, h, body = st[0], st[1], st[2]
        tile = Image.new('RGBA', (w * TT, h * TT), (0, 0, 0, 0))
        for dx, dy, gid in body:
            tile.alpha_composite(T.tile_image(gid), (dx * TT, dy * TT))
        tile = tile.resize((w * TT * scale, h * TT * scale), Image.NEAREST)
        x = (i % cols) * cw
        y = (i // cols) * (cw + hdr) + hdr
        d.rectangle([x, y - hdr, x + cw - 2, y + cw - 2], outline=(90, 95, 110, 255))
        canvas.alpha_composite(tile, (x + 2, y + 2))
        if label:
            d.text((x + 3, y - hdr + 1), f"{i}:{w}x{h}", fill=(255, 220, 90))
    canvas.save(out)
    print(out, canvas.size)
