"""Render generated layers (src,col,row keyed) to a preview PNG."""
from PIL import Image
import tmxlib as T
from undead_gen import MAP_W, MAP_H, GR, WC, WD, OB, DT

IMG = {GR: 'Ground_rocks.png', WC: 'water_coasts.png', WD: 'water_detilazation.png',
       OB: 'Objects.png', DT: 'details.png',
       'anim1': 'Objects_animated.png', 'anim2': 'Objects_animated2.png',
       'anim3': 'Objects_animated3.png'}

GROUND_COLOR = (111, 115, 106, 255)

_cache = {}


def tile(src, c, r, fh=False):
    k = (src, c, r, fh)
    if k not in _cache:
        im = T.sheet(IMG[src]).crop((c * 16, r * 16, c * 16 + 16, r * 16 + 16))
        if fh:
            im = im.transpose(Image.FLIP_LEFT_RIGHT)
        _cache[k] = im
    return _cache[k]


ORDER = ['water', 'waterdetail', 'ground', 'grounddark', 'mound', 'rubble',
         'ridge', 'details', 'objlow']


def render(layers, sprites=(), out='preview.png', scale=1, crop=None):
    W, H = MAP_W * 16, MAP_H * 16
    canvas = Image.new('RGBA', (W, H), GROUND_COLOR)
    for name in ORDER:
        for (x, y), t in layers.get(name, {}).items():
            src, c, r = t[0], t[1], t[2]
            fh = t[3] if len(t) > 3 else False
            canvas.alpha_composite(tile(src, c, r, fh), (x * 16, y * 16))
    for sp in sorted(sprites, key=lambda s: s['y']):
        im = T.sheet(IMG[sp['src']]).crop(
            (sp['col'] * 16, sp['row'] * 16, (sp['col'] + sp['w']) * 16, (sp['row'] + sp['h']) * 16))
        if sp.get('fh'):
            im = im.transpose(Image.FLIP_LEFT_RIGHT)
        canvas.alpha_composite(im, (sp['x'] * 16, sp['ty'] * 16))
    if crop:
        canvas = canvas.crop(crop)
    if scale != 1:
        canvas = canvas.resize((canvas.width * scale // 1, canvas.height * scale // 1),
                               Image.LANCZOS if scale < 1 else Image.NEAREST)
    canvas.save(out)
    print(out, canvas.size)
    return canvas
