"""Forest tileset tables + a small harness for rendering test patches."""
import os
from PIL import Image

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'Art', 'Forest')
TILES = os.path.join(BASE, 'Tiles', 'Tileset.png')
DECOR = os.path.join(BASE, 'Decorations', 'Decorations.png')

_sheets = {}


def sheet(path):
    if path not in _sheets:
        _sheets[path] = Image.open(path).convert('RGBA')
    return _sheets[path]


def tile(c, r, fh=False):
    im = sheet(TILES).crop((c * 16, r * 16, c * 16 + 16, r * 16 + 16))
    return im.transpose(Image.FLIP_LEFT_RIGHT) if fh else im


# ---- 9-slice tables (col, row) -------------------------------------------
DIRT = (6, 0)
DIRT_VARIANTS = [(6, 0), (7, 0), (6, 1), (7, 1), (6, 2), (7, 2)]

GRASS = {
    'TL': (0, 0), 'T': (1, 0), 'TR': (2, 0),
    'L': (0, 1), 'C': (1, 1), 'R': (2, 1),
    'BL': (0, 2), 'B': (1, 2), 'BR': (2, 2),
    'iSE': (3, 0), 'iSW': (4, 0), 'iNE': (3, 1), 'iNW': (4, 1),
    'iNW_SE': (3, 2), 'iNE_SW': (4, 2),
}
GRASS_DARK = {
    'TL': (0, 3), 'T': (1, 3), 'TR': (2, 3),
    'L': (0, 4), 'C': (1, 4), 'R': (2, 4),
    'BL': (0, 5), 'B': (1, 5), 'BR': (2, 5),
}
ROCK_GRASS = {
    'TL': (3, 3), 'T': (4, 3), 'TR': (5, 3),
    'L': (3, 4), 'C': (4, 4), 'R': (5, 4),
    'BL': (3, 5), 'B': (4, 5), 'BR': (5, 5),
    'iNW': (6, 3), 'iNE': (7, 3), 'iSW': (6, 4), 'iSE': (7, 4),
}
ROCK_DIRT = {
    'TL': (3, 6), 'T': (4, 6), 'TR': (5, 6),
    'L': (3, 7), 'C': (4, 7), 'R': (5, 7),
    'BL': (3, 8), 'B': (4, 8), 'BR': (5, 8),
    'iNW': (6, 6), 'iNE': (7, 6), 'iSW': (6, 7), 'iSE': (7, 7),
}
# (3-5, 10-12) is the same rim with an empty centre - an island inside a pond,
# NOT a set of inner corners. Water has no concave pieces, so pond outlines are
# made convex before tiling.
WATER = {
    'TL': (0, 10), 'T': (1, 10), 'TR': (2, 10),
    'L': (0, 11), 'C': (1, 11), 'R': (2, 11),
    'BL': (0, 12), 'B': (1, 12), 'BR': (2, 12),
}
WATER_ISLAND = {
    'TL': (3, 10), 'T': (4, 10), 'TR': (5, 10),
    'L': (3, 11), 'C': (4, 11), 'R': (5, 11),
    'BL': (3, 12), 'B': (4, 12), 'BR': (5, 12),
}
# plain-grass tiles carrying a small plant, sprinkled over open grass
GRASS_VARIANTS = [(5, 0), (5, 1), (5, 2)]
WATER_FILL = [(6, 10), (7, 10), (6, 11), (7, 11)]
LILY = [(6, 13), (7, 13), (6, 14), (7, 14)]
RAMP_GRASS = [(0, 9), (1, 9), (2, 9), (3, 9)]
RAMP_DIRT = [(4, 9), (5, 9), (6, 9), (7, 9)]

DIRS8 = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]


def mask_of(region, x, y):
    m = 0
    for i, (dx, dy) in enumerate(DIRS8):
        if (x + dx, y + dy) in region:
            m |= 1 << i
    return m


def nine(region, x, y, table):
    m = mask_of(region, x, y)
    N, E, S, W = (m >> 1) & 1, (m >> 4) & 1, (m >> 6) & 1, (m >> 3) & 1
    NW, NE, SW, SE = m & 1, (m >> 2) & 1, (m >> 5) & 1, (m >> 7) & 1
    if N and E and S and W:
        miss = [k for k, v in (('NW', NW), ('NE', NE), ('SW', SW), ('SE', SE)) if not v]
        if not miss:
            return table['C']
        if len(miss) == 2 and 'iNW_SE' in table:
            if set(miss) == {'NW', 'SE'}:
                return table['iNW_SE']
            if set(miss) == {'NE', 'SW'}:
                return table['iNE_SW']
        key = 'i' + miss[0]
        return table.get(key, table['C'])
    if not N and not W and E and S:
        return table['TL']
    if not N and E and S and W:
        return table['T']
    if not N and not E and S and W:
        return table['TR']
    if N and E and S and not W:
        return table['L']
    if N and not E and S and W:
        return table['R']
    if N and E and not S and not W:
        return table['BL']
    if N and E and not S and W:
        return table['B']
    if N and not E and not S and W:
        return table['BR']
    return None


def render_patch(layers, w, h, out, scale=4, bg=(40, 40, 40, 255)):
    """layers: list of dicts {(x,y): (c,r)} drawn in order."""
    cv = Image.new('RGBA', (w * 16, h * 16), bg)
    for L in layers:
        for (x, y), t in L.items():
            if 0 <= x < w and 0 <= y < h:
                cv.alpha_composite(tile(t[0], t[1]), (x * 16, y * 16))
    cv = cv.resize((w * 16 * scale, h * 16 * scale), Image.NEAREST)
    cv.save(out)
    print(out, cv.size)
