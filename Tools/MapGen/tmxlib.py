"""Shared helpers: parse the Undead_land.tmx reference map and render tile layers to PNG."""
import xml.etree.ElementTree as ET
import os
from PIL import Image

DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "..", "..", "Art", "UndeadForest", "Tiled_files")
TMX = os.path.join(DIR, "Undead_land.tmx")

FLIP_H = 0x80000000
FLIP_V = 0x40000000
FLIP_D = 0x20000000
GID_MASK = 0x1FFFFFFF

# Order matters: the two 'details' tilesets are identical images; we keep both firstgids.
def load_tilesets():
    root = ET.parse(TMX).getroot()
    out = []
    for ts in root.findall('tileset'):
        fg = int(ts.get('firstgid'))
        if ts.get('source'):
            node = ET.parse(os.path.join(DIR, ts.get('source'))).getroot()
        else:
            node = ts
        img = node.find('image')
        anims = {}
        for tile in node.findall('tile'):
            a = tile.find('animation')
            if a is not None:
                anims[int(tile.get('id'))] = [(int(f.get('tileid')), int(f.get('duration')))
                                              for f in a.findall('frame')]
        out.append(dict(
            firstgid=fg, name=node.get('name'), columns=int(node.get('columns')),
            count=int(node.get('tilecount')), image=img.get('source'),
            iw=int(img.get('width')), ih=int(img.get('height')), anims=anims,
        ))
    return out


TILESETS = load_tilesets()


def ts_for_gid(gid):
    best = None
    for t in TILESETS:
        if gid >= t['firstgid'] and (best is None or t['firstgid'] > best['firstgid']):
            best = t
    return best


def decode(gid):
    """gid -> (tileset dict, col, row, flip_h, flip_v, flip_d)"""
    fh = bool(gid & FLIP_H); fv = bool(gid & FLIP_V); fd = bool(gid & FLIP_D)
    g = gid & GID_MASK
    ts = ts_for_gid(g)
    lid = g - ts['firstgid']
    return ts, lid % ts['columns'], lid // ts['columns'], fh, fv, fd


def load_layers():
    root = ET.parse(TMX).getroot()
    layers = []
    for layer in root.findall('layer'):
        cells = {}
        for chunk in layer.find('data').findall('chunk'):
            cx, cy = int(chunk.get('x')), int(chunk.get('y'))
            cw = int(chunk.get('width'))
            vals = [int(v) for v in chunk.text.replace('\n', '').split(',') if v.strip()]
            for i, v in enumerate(vals):
                if v:
                    cells[(cx + i % cw, cy + i // cw)] = v
        layers.append(dict(name=layer.get('name'), id=int(layer.get('id')), cells=cells))
    return layers


_img_cache = {}


def sheet(name):
    if name not in _img_cache:
        _img_cache[name] = Image.open(os.path.join(DIR, name)).convert('RGBA')
    return _img_cache[name]


def tile_image(gid, T=16):
    ts, c, r, fh, fv, fd = decode(gid)
    im = sheet(ts['image']).crop((c * T, r * T, c * T + T, r * T + T))
    if fd:
        im = im.transpose(Image.TRANSPOSE)
    if fh:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    if fv:
        im = im.transpose(Image.FLIP_TOP_BOTTOM)
    return im


def render(layers, out_path, bg=(20, 20, 24, 255), T=16, bounds=None, scale=1):
    """layers: list of dicts with 'cells' {(x,y): gid}, drawn in order."""
    xs, ys = [], []
    for L in layers:
        for (x, y) in L['cells']:
            xs.append(x); ys.append(y)
    if bounds:
        minx, miny, maxx, maxy = bounds
    else:
        minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
    W = (maxx - minx + 1) * T
    H = (maxy - miny + 1) * T
    canvas = Image.new('RGBA', (W, H), bg)
    for L in layers:
        for (x, y), gid in L['cells'].items():
            if not (minx <= x <= maxx and miny <= y <= maxy):
                continue
            im = tile_image(gid, T)
            canvas.alpha_composite(im, ((x - minx) * T, (y - miny) * T))
    if scale != 1:
        canvas = canvas.resize((W * scale, H * scale), Image.NEAREST)
    canvas.save(out_path)
    return canvas
