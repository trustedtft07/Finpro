"""Render the Green Forest map to a PNG for review."""
from PIL import Image
import ftiles as F
from undead_gen import MAP_W, MAP_H

ORDER = ['dirtdetail', 'grass', 'dark', 'water', 'rocks', 'decor']
DIRT_RGB = (164, 97, 43, 255)


def render(layers, sprites, out='fprev.png'):
    ts = F.sheet(F.TILES)
    dec = F.sheet(F.DECOR)
    W, H = MAP_W * 16, MAP_H * 16
    cv = Image.new('RGBA', (W, H), DIRT_RGB)
    for name in ORDER:
        for (x, y), t in layers.get(name, {}).items():
            if t[0] == 'decor':
                _, c, r, tw, th = t
                im = dec.crop((c * 16, r * 16, (c + tw) * 16, (r + th) * 16))
            else:
                c, r = t
                im = ts.crop((c * 16, r * 16, c * 16 + 16, r * 16 + 16))
            cv.alpha_composite(im, (x * 16, y * 16))
    for sp in sorted(sprites, key=lambda s: s['y'] + s['th']):
        s = sp['s']
        im = dec.crop((s['px'], s['py'], s['px'] + s['pw'], s['py'] + s['ph']))
        if sp['fh']:
            im = im.transpose(Image.FLIP_LEFT_RIGHT)
        # bottom-centred inside the tile box
        px = sp['x'] * 16 + (sp['tw'] * 16 - s['pw']) // 2
        py = (sp['y'] + sp['th']) * 16 - s['ph']
        cv.alpha_composite(im, (px, py))
    cv.save(out)
    print(out, cv.size)
    return cv
