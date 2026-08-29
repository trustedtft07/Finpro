"""Generate the Undead Forest map: terrain, props, collision.

Produces an in-memory description that can be rendered to PNG for review and
written out as a Godot scene.
"""
import random
import math
from collections import defaultdict

import tmxlib as T
import stamps as S

# ---------------------------------------------------------------- dimensions
# GreenForest is 160x100 tiles; 1.5x on each axis.
MAP_W, MAP_H = 240, 150
TILE = 16

# ------------------------------------------------------------- tile handles
# (source_key, col, row)
GR = 'ground_rocks'
WC = 'water_coasts'
WD = 'water_detail'
OB = 'objects'
DT = 'details'

GROUND_BASE = (GR, 2, 2)          # flat (111,115,106) - matches the backdrop colour
COLLIDER = (GR, 0, 59)            # empty atlas cell, used purely as a collision shape

# Cliff tiling, read off the island stamp at Ground_rocks (0-4, 0-6).
#   columns: 0 = left overhang, 1 = left edge, 2 = middle, 3 = right edge, 4 = right overhang
#   rows:    0 = spike overhang above, 1 = top, 2 = body, 3 = lip,
#            4,5,6 = the cliff face hanging below
CLIFF_COBBLE_OFFSET = 21
CLIFF_FACE_ROWS = (4, 5, 6)

# soft rounded rock mound, purely decorative
MOUND = {
    'TL': (GR, 16, 15), 'T': (GR, 17, 15), 'TR': (GR, 18, 15),
    'L':  (GR, 16, 16), 'C': (GR, 17, 16), 'R':  (GR, 18, 16),
    'BL': (GR, 16, 17), 'B': (GR, 17, 17), 'BR': (GR, 18, 17),
    # inner (concave) corners, from the 3x3 block wrapped round the hole at (23,19)
    'iSE': (GR, 22, 18), 'iSW': (GR, 24, 18),
    'iNE': (GR, 22, 20), 'iNW': (GR, 24, 20),
}
# darker ground patch 9-slice
DARK = {
    'TL': (GR, 12, 56), 'T': (GR, 13, 56), 'TR': (GR, 14, 56),
    'L':  (GR, 12, 57), 'C': (GR, 13, 57), 'R':  (GR, 14, 57),
    'BL': (GR, 12, 58), 'B': (GR, 13, 58), 'BR': (GR, 14, 58),
}

WATER_FILL = (WC, 22, 0)

# Shore tiles keyed by which neighbours are water.
# island block (1-3,1-3) = ground island in water; ring block (5-8,1-4) = water hole;
# single-hole block (16-18,1-3) = water on one side only.
SHORE = {
    # side + both diagonals on that side
    'N':   (WC, 2, 1), 'S':   (WC, 2, 3), 'W':   (WC, 1, 2), 'E':   (WC, 3, 2),
    # side + only the left/right diagonal
    'N_NW': (WC, 7, 4), 'N_NE': (WC, 6, 4),
    'S_SW': (WC, 7, 1), 'S_SE': (WC, 6, 1),
    'W_NW': (WC, 8, 3), 'W_SW': (WC, 8, 2),
    'E_NE': (WC, 5, 3), 'E_SE': (WC, 5, 2),
    # side only, no diagonals
    'N_only': (WC, 17, 3), 'S_only': (WC, 17, 1),
    'W_only': (WC, 18, 2), 'E_only': (WC, 16, 2),
    # two sides (concave pool corner)
    'NW': (WC, 1, 1), 'NE': (WC, 3, 1), 'SW': (WC, 1, 3), 'SE': (WC, 3, 3),
    # diagonal only (convex pool corner)
    'd_NW': (WC, 8, 4), 'd_NE': (WC, 5, 4), 'd_SW': (WC, 8, 1), 'd_SE': (WC, 5, 1),
}

DIRS8 = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]


# ------------------------------------------------------------------- shapes
def in_bounds(x, y, pad=0):
    return pad <= x < MAP_W - pad and pad <= y < MAP_H - pad


def open2x2(region):
    """Morphological opening with a 2x2 element: guarantees a minimum width of 2."""
    eroded = set()
    for (x, y) in region:
        if (x + 1, y) in region and (x, y + 1) in region and (x + 1, y + 1) in region:
            eroded.add((x, y))
    out = set()
    for (x, y) in eroded:
        out.update([(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)])
    return out


def smooth(region, passes=3, thr=5):
    """Majority smoothing. Rounds off spurs and concave notches so that after
    `tidy` every cell matches one of the nine 9-slice pieces exactly."""
    region = set(region)
    for _ in range(passes):
        new = set()
        for y in range(MAP_H):
            for x in range(MAP_W):
                n = sum(1 for dx, dy in [(0, 0)] + DIRS8 if (x + dx, y + dy) in region)
                if n >= thr:
                    new.add((x, y))
        region = new
    return region


def fill_holes(region, rounds=3, thr=6):
    region = set(region)
    for _ in range(rounds):
        add = set()
        for y in range(MAP_H):
            for x in range(MAP_W):
                if (x, y) in region:
                    continue
                if sum(1 for dx, dy in DIRS8 if (x + dx, y + dy) in region) >= thr:
                    add.add((x, y))
        if not add:
            break
        region |= add
    return region


def tidy(region, passes=3, thr=5):
    r = fill_holes(open2x2(smooth(region, passes, thr)))
    return {p for p in r if in_bounds(*p)}


def mask_of(region, x, y):
    m = 0
    for i, (dx, dy) in enumerate(DIRS8):
        if (x + dx, y + dy) in region:
            m |= 1 << i
    return m


def nine_slice(region, x, y, table):
    m = mask_of(region, x, y)
    N, E, S, W = (m >> 1) & 1, (m >> 4) & 1, (m >> 6) & 1, (m >> 3) & 1
    if N and E and S and W:
        for key, bit in (('iNW', 0), ('iNE', 2), ('iSW', 5), ('iSE', 7)):
            if not (m >> bit) & 1 and key in table:
                return table[key]
        return table['C']
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
    return None      # degenerate; caller drops the cell


def shore_tile(water, x, y):
    """Tile for a ground cell next to `water`. None when nothing is adjacent."""
    def w(dx, dy):
        return (x + dx, y + dy) in water
    N, E, S, W = w(0, -1), w(1, 0), w(0, 1), w(-1, 0)
    NW, NE, SW, SE = w(-1, -1), w(1, -1), w(-1, 1), w(1, 1)
    if N and W:
        return SHORE['NW']
    if N and E:
        return SHORE['NE']
    if S and W:
        return SHORE['SW']
    if S and E:
        return SHORE['SE']
    if N:
        if NW and NE:
            return SHORE['N']
        if NW:
            return SHORE['N_NW']
        if NE:
            return SHORE['N_NE']
        return SHORE['N_only']
    if S:
        if SW and SE:
            return SHORE['S']
        if SW:
            return SHORE['S_SW']
        if SE:
            return SHORE['S_SE']
        return SHORE['S_only']
    if W:
        if NW and SW:
            return SHORE['W']
        if NW:
            return SHORE['W_NW']
        if SW:
            return SHORE['W_SW']
        return SHORE['W_only']
    if E:
        if NE and SE:
            return SHORE['E']
        if NE:
            return SHORE['E_NE']
        if SE:
            return SHORE['E_SE']
        return SHORE['E_only']
    if NW:
        return SHORE['d_NW']
    if NE:
        return SHORE['d_NE']
    if SW:
        return SHORE['d_SW']
    if SE:
        return SHORE['d_SE']
    return None


# ---------------------------------------------------------------- generators
def blob(rng, cx, cy, radius, wobble=0.45, lobes=3):
    """An organic filled blob around (cx,cy)."""
    phases = [rng.uniform(0, math.tau) for _ in range(lobes)]
    freqs = [rng.choice((2, 3, 4, 5)) for _ in range(lobes)]
    amps = [wobble * radius * rng.uniform(0.25, 0.6) for _ in range(lobes)]
    out = set()
    r_int = int(radius * (1 + wobble)) + 2
    for y in range(cy - r_int, cy + r_int + 1):
        for x in range(cx - r_int, cx + r_int + 1):
            dx, dy = x - cx, y - cy
            d = math.hypot(dx, dy)
            a = math.atan2(dy, dx)
            rr = radius
            for ph, fq, am in zip(phases, freqs, amps):
                rr += am * math.sin(fq * a + ph)
            if d <= rr:
                out.add((x, y))
    return out


def ridge_path(rng, x, y, length, thickness=2):
    """A winding thick line - the dark spiky ridges that carve the map into rooms."""
    ang = rng.uniform(0, math.tau)
    out = set()
    for _ in range(length):
        ang += rng.gauss(0, 0.35)
        x += math.cos(ang)
        y += math.sin(ang)
        if not in_bounds(int(x), int(y), 4):
            ang += math.pi          # bounce back inside
            x += 2 * math.cos(ang)
            y += 2 * math.sin(ang)
        cx, cy = int(round(x)), int(round(y))
        t = thickness + (1 if rng.random() < 0.25 else 0)
        for dy in range(-t, t + 1):
            for dx in range(-t, t + 1):
                if dx * dx + dy * dy <= t * t + 1:
                    out.add((cx + dx, cy + dy))
    return out


def components(cells, conn=4):
    return S._components(cells, conn)


def cliff_tiles(region, cobble=False):
    """Tile a plateau region with the tall cliff stamp.

    Returns {(x, y): (src, col, row)} covering the plateau top, the spike overhang
    above it, the side slivers, and the cliff face hanging below, plus the set of
    cells the face occupies (needed for collision).
    """
    off = CLIFF_COBBLE_OFFSET if cobble else 0
    out = {}
    face = set()

    def put(x, y, c, r, over=False):
        if not in_bounds(x, y):
            return
        if not over and (x, y) in out:
            return
        out[(x, y)] = (GR, c, r + off)

    # vertical runs, column by column
    cols = defaultdict(list)
    for (x, y) in region:
        cols[x].append(y)
    for x, ys in cols.items():
        ys.sort()
        runs = []
        start = prev = ys[0]
        for y in ys[1:]:
            if y == prev + 1:
                prev = y
                continue
            runs.append((start, prev))
            start = prev = y
        runs.append((start, prev))

        for (y0, y1) in runs:
            left = (x - 1, y0) not in region and (x - 1, y1) not in region
            right = (x + 1, y0) not in region and (x + 1, y1) not in region
            for y in range(y0, y1 + 1):
                l = (x - 1, y) not in region
                r_ = (x + 1, y) not in region
                ac = 1 if l else (3 if r_ else 2)
                ar = 1 if y == y0 else (3 if y == y1 else 2)
                put(x, y, ac, ar, over=True)
                if l:
                    put(x - 1, y, 0, ar)
                if r_:
                    put(x + 1, y, 4, ar)
            # spikes hanging above the top row
            ac0 = 1 if (x - 1, y0) not in region else (3 if (x + 1, y0) not in region else 2)
            if (x, y0 - 1) not in region:
                put(x, y0 - 1, ac0, 0)
            # cliff face below the bottom row
            acb = 1 if (x - 1, y1) not in region else (3 if (x + 1, y1) not in region else 2)
            for k, ar in enumerate(CLIFF_FACE_ROWS, start=1):
                cy = y1 + k
                if (x, cy) in region:
                    break
                put(x, cy, acb, ar, over=True)
                if acb == 1:
                    put(x - 1, cy, 0, ar)
                if acb == 3:
                    put(x + 1, cy, 4, ar)
                if ar < 6 and in_bounds(x, cy):
                    face.add((x, cy))
    return out, face


def dilate(region, r=1):
    out = set()
    for (x, y) in region:
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                out.add((x + dx, y + dy))
    return out
