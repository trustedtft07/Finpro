"""Build the Undead Forest map and dump it as a pickle + preview PNG."""
import math
import pickle
import random
from collections import defaultdict

import tmxlib as T
import stamps as S
from undead_gen import (
    MAP_W, MAP_H, GR, WC, WD, OB, DT, GROUND_BASE, COLLIDER, MOUND, DARK,
    WATER_FILL, DIRS8, in_bounds, tidy, smooth, nine_slice, shore_tile, blob,
    ridge_path, components, dilate, cliff_tiles,
)

SEED = 20260829
rng = random.Random(SEED)

SRC_OF = {
    'Ground_rocks': GR,
    'water_coasts': WC,
    'Water_detilazation': WD,
    'Objects': OB,
    'details': DT,
}
ANIM_SHEETS = {'Objects_animated': 'anim1', 'Objects_animated2': 'anim2',
               'Objects_animated3': 'anim3'}

BORDER = 4          # solid frame thickness


def gid_to_tile(gid):
    ts, c, r, fh, fv, fd = T.decode(gid)
    return SRC_OF.get(ts['name']), c, r, fh


# ------------------------------------------------------------------ stamps
def _coverage(w, h, body):
    from PIL import Image
    import numpy as np
    im = Image.new('RGBA', (w * 16, h * 16), (0, 0, 0, 0))
    for dx, dy, g in body:
        im.alpha_composite(T.tile_image(g), (dx * 16, dy * 16))
    return float((np.asarray(im)[:, :, 3] > 8).mean())


def _has_straight_edge(w, h, body):
    occ = {(dx, dy) for dx, dy, _ in body}
    if w < 3 or h < 3:
        return True
    for y in range(h):
        run = [x for x in range(w) if (x, y) in occ]
        if len(run) >= 6 and run == list(range(run[0], run[0] + len(run))):
            above = sum(1 for x in run if (x, y - 1) in occ)
            below = sum(1 for x in run if (x, y + 1) in occ)
            if (above == 0 and below == len(run)) or (below == 0 and above == len(run)):
                return True
    return False


def _dedupe(items, key):
    seen, out = set(), []
    for it in items:
        k = key(it)
        if k in seen:
            continue
        seen.add(k)
        out.append(it)
    return out


def load_stamps():
    L = T.load_layers()
    objs, anims, details, rubble = [], [], [], []

    for nm in ('Objects', 'Objects2', 'Objects3', 'Objects4', 'Objects5',
               'Objects_under_elevated_space'):
        for l in [x for x in L if x['name'] == nm]:
            for w, h, body in S.object_stamps(l['cells']):
                names = {T.decode(g)[0]['name'] for _, _, g in body}
                cov = _coverage(w, h, body)
                if cov < 0.03:
                    continue
                ts0, c0, r0, fh, _, _ = T.decode(body[0][2])
                if fh:
                    continue
                col, row = c0 - body[0][0], r0 - body[0][1]
                if names & set(ANIM_SHEETS):
                    sheet = ANIM_SHEETS[sorted(names & set(ANIM_SHEETS))[0]]
                    anims.append(dict(w=w, h=h, sheet=sheet, col=col, row=row, cov=cov))
                elif names == {'Objects'}:
                    objs.append(dict(w=w, h=h, col=col, row=row, cov=cov,
                                     body=[gid_to_tile(g) + (dx, dy) for dx, dy, g in body]))

    for l in L:
        if l['name'].startswith('detail'):
            for w, h, body in S.object_stamps(l['cells']):
                if _coverage(w, h, body) < 0.02:
                    continue
                details.append(dict(w=w, h=h,
                                    body=[gid_to_tile(g) + (dx, dy) for dx, dy, g in body]))

    for nm in ('bricks', 'bricks2', 'bricks3'):
        for l in [x for x in L if x['name'] == nm]:
            for w, h, body in S.region_stamps(l['cells'], 8):
                cells = [gid_to_tile(g) + (dx, dy) for dx, dy, g in body]
                # the flat cobble fill tiles (row 20) form hard rectangular blocks;
                # keep only the loose pebble-scatter pieces
                if any(t[2] == 20 for t in cells) or _has_straight_edge(w, h, body):
                    continue
                rubble.append(dict(w=w, h=h, body=cells))

    objs = _dedupe(objs, lambda o: (o['col'], o['row'], o['w'], o['h']))
    anims = _dedupe(anims, lambda o: (o['sheet'], o['col'], o['row']))
    details = _dedupe(details, lambda o: repr(sorted(o['body'])))
    return objs, anims, details, rubble


# ------------------------------------------------------------------ terrain
def frame_region():
    r = set()
    for y in range(MAP_H):
        for x in range(MAP_W):
            if x < BORDER or y < BORDER or x >= MAP_W - BORDER or y >= MAP_H - BORDER:
                r.add((x, y))
    return r


def scatter_blobs(rng, count, rmin, rmax, min_gap, avoid, elongate=0.0):
    """Poisson-ish scatter of blobs that stay `min_gap` apart and clear of `avoid`."""
    out = []
    taken = set()
    tries = 0
    while len(out) < count and tries < count * 120:
        tries += 1
        r = rng.uniform(rmin, rmax)
        cx = rng.randint(int(r) + BORDER + 4, MAP_W - int(r) - BORDER - 5)
        cy = rng.randint(int(r) + BORDER + 4, MAP_H - int(r) - BORDER - 10)
        b = blob(rng, cx, cy, r, wobble=0.5)
        if rng.random() < elongate:                # elongate some of them into ridges
            k = rng.randint(3, 12)
            horiz = rng.random() < 0.7
            b = {(x + (i if horiz else 0), y + (0 if horiz else i))
                 for (x, y) in b for i in range(k)}
        if any(not in_bounds(x, y, BORDER + 3) for x, y in b):
            continue
        if b & avoid or b & taken:
            continue
        out.append(b)
        taken |= dilate(b, min_gap)
    return out


def build():
    objs, anims, details, rubble = load_stamps()
    print('stamps: objects=%d anim=%d details=%d rubble=%d'
          % (len(objs), len(anims), len(details), len(rubble)))

    frame = frame_region()
    inner_pad = dilate(frame, 2)

    # --- plateau / ridge blobs -------------------------------------------
    blobs = scatter_blobs(rng, 40, 2.6, 6.4, 8, inner_pad, elongate=0.45)
    blobs = [tidy(b) for b in blobs]
    blobs = [b for b in blobs if len(b) >= 9]

    # --- water pools ------------------------------------------------------
    solid_so_far = frame | set().union(*blobs) if blobs else frame
    pools = scatter_blobs(rng, 18, 3.0, 7.5, 7, dilate(solid_so_far, 5), elongate=0.25)
    pools = [tidy(p, passes=2) for p in pools]
    pools = [p for p in pools if len(p) >= 12]
    water = set().union(*pools) if pools else set()

    # --- cliffs & reachability -------------------------------------------
    for _ in range(8):
        ridge = frame | set().union(*blobs) if blobs else set(frame)
        cliffs, face = cliff_tiles(frame, cobble=True)
        for i, b in enumerate(blobs):
            c, f = cliff_tiles(b, cobble=(i % 10) < 7)
            cliffs.update(c)
            face |= f
        solid = ridge | face | water
        walk = {(x, y) for y in range(MAP_H) for x in range(MAP_W)} - solid
        comps = sorted(components(walk, 4), key=len, reverse=True)
        if len(comps) <= 1:
            break
        main = comps[0]
        drop = set()
        for c in comps[1:]:
            near = dilate(c, 2)
            for i, b in enumerate(blobs):
                if b & near:
                    drop.add(i)
        if not drop:
            break
        blobs = [b for i, b in enumerate(blobs) if i not in drop]
    walk = comps[0] if comps else set()
    print('blobs=%d pools=%d  walkable %d/%d (%.0f%%)'
          % (len(blobs), len(pools), len(walk), MAP_W * MAP_H,
             100 * len(walk) / (MAP_W * MAP_H)))

    # --- decorative rock mounds (no collision) ---------------------------
    mounds = set()
    for _ in range(46):
        cx = rng.randint(BORDER + 3, MAP_W - BORDER - 4)
        cy = rng.randint(BORDER + 3, MAP_H - BORDER - 4)
        mounds |= blob(rng, cx, cy, rng.uniform(2.2, 5.5), wobble=0.55)
    mounds = tidy(mounds) - dilate(ridge, 1) - dilate(water, 1)
    mounds = {p for p in mounds if in_bounds(p[0], p[1])}
    mounds = _drop_small(mounds, 6)

    # --- darker ground patches -------------------------------------------
    dark = set()
    for _ in range(80):
        cx = rng.randint(BORDER, MAP_W - BORDER - 1)
        cy = rng.randint(BORDER, MAP_H - BORDER - 1)
        dark |= blob(rng, cx, cy, rng.uniform(2.5, 7.0), wobble=0.55)
    dark = tidy(dark) - water
    dark = _drop_small(dark, 6)

    return dict(ridge=ridge, cliffs=cliffs, face=face, water=water, pools=pools,
                dark=dark, mounds=mounds, walk=walk, blobs=blobs,
                objs=objs, anims=anims, details=details, rubble=rubble)


def _drop_small(region, minsize):
    out = set()
    for c in components(region, 8):
        if len(c) >= minsize:
            out |= c
    return out


# ------------------------------------------------------------------ layers
def paint(m):
    water, dark, mounds = m['water'], m['dark'], m['mounds']
    layers = {k: {} for k in
              ('water', 'waterdetail', 'ground', 'grounddark', 'mound', 'rubble',
               'ridge', 'details', 'objlow', 'collision')}

    for c in dilate(water, 1):
        if in_bounds(*c):
            layers['water'][c] = WATER_FILL

    for y in range(MAP_H):
        for x in range(MAP_W):
            if (x, y) in water:
                continue
            t = shore_tile(water, x, y)
            if t:
                layers['ground'][(x, y)] = t

    for c in sorted(dark):
        if c in water:
            continue
        t = nine_slice(dark, c[0], c[1], DARK)
        if t:
            layers['grounddark'][c] = t

    for c in sorted(mounds):
        t = nine_slice(mounds, c[0], c[1], MOUND)
        if t:
            layers['mound'][c] = t

    layers['ridge'].update(m['cliffs'])

    for c in m['ridge'] | m['face'] | water:
        if in_bounds(*c):
            layers['collision'][c] = COLLIDER

    return layers
