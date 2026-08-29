"""Build BossPlace: a walled Undead Forest arena for the two-phase boss.

Reuses the Undead Forest generator's cliff tiling and stamp library, but at arena
scale and with the middle deliberately left bare so the boss telegraphs stay readable.
The tileset is shared with UndeadForest.tscn, so this also re-emits that resource with
the union of the tiles both maps use.
"""
import base64
import math
import random
import struct

import undead_gen as U

# Arena a little larger than the camera's 1920x1080 view, so it pans slightly
U.MAP_W, U.MAP_H = 136, 84

import build_map as B            # noqa: E402  (must import after the size override)
import export_godot as EG        # noqa: E402
import gdscene as GS             # noqa: E402
from undead_gen import (GR, WC, WD, OB, DT, DARK, MOUND, COLLIDER, DIRS8,
                        in_bounds, blob, dilate, components, cliff_tiles,
                        nine_slice, smooth, fill_holes, open2x2)

SEED = 20260831
WALL = 4
MAP_W, MAP_H = U.MAP_W, U.MAP_H
CENTRE = (MAP_W // 2, MAP_H // 2 - 2)
ARENA_CLEAR = 27.0               # tiles kept free of scenery around the centre

import os
PROJ = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
OUT = 'out'


def tidy(region, passes=3, thr=5):
    r = fill_holes(open2x2(smooth(region, passes, thr)))
    return {p for p in r if in_bounds(*p)}


def frame_region():
    return {(x, y) for y in range(MAP_H) for x in range(MAP_W)
            if x < WALL or y < WALL or x >= MAP_W - WALL or y >= MAP_H - WALL}


def dist_c(c):
    return math.hypot(c[0] - CENTRE[0], c[1] - CENTRE[1])


def build():
    rng = random.Random(SEED)
    objs, anims, details, rubble = B.load_stamps()

    wall = frame_region()
    keepout = dilate(wall, 2)

    # A few rock outcrops tucked into the corners - cover to break line of sight,
    # without crowding the space the fight needs
    blobs = []
    taken = set()
    for _ in range(400):
        if len(blobs) >= 8:
            break
        cx = rng.randint(WALL + 5, MAP_W - WALL - 6)
        cy = rng.randint(WALL + 5, MAP_H - WALL - 10)
        if math.hypot(cx - CENTRE[0], cy - CENTRE[1]) < ARENA_CLEAR + 4:
            continue
        b = tidy(blob(rng, cx, cy, rng.uniform(2.6, 4.4), wobble=0.5))
        if not b or b & keepout or b & taken or any(not in_bounds(x, y, WALL + 2) for x, y in b):
            continue
        if any(dist_c(c) < ARENA_CLEAR for c in b):
            continue
        blobs.append(b)
        taken |= dilate(b, 7)

    cliffs, face = cliff_tiles(wall, cobble=True)
    for i, b in enumerate(blobs):
        c, f = cliff_tiles(b, cobble=(i % 3 != 0))
        cliffs.update(c)
        face |= f

    ridge = wall | set().union(*blobs) if blobs else set(wall)
    solid = ridge | face
    walk = {(x, y) for y in range(MAP_H) for x in range(MAP_W)} - solid
    comps = sorted(components(walk, 4), key=len, reverse=True)
    main = comps[0]
    for c in comps[1:]:
        ridge |= c
        walk -= c

    # Ground texture
    dark = set()
    for _ in range(26):
        cx = rng.randint(WALL, MAP_W - WALL - 1)
        cy = rng.randint(WALL, MAP_H - WALL - 1)
        dark |= blob(rng, cx, cy, rng.uniform(2.5, 6.0), wobble=0.55)
    dark = tidy(dark)

    mounds = set()
    for _ in range(16):
        cx = rng.randint(WALL, MAP_W - WALL - 1)
        cy = rng.randint(WALL, MAP_H - WALL - 1)
        mounds |= blob(rng, cx, cy, rng.uniform(2.2, 4.2), wobble=0.55)
    mounds = tidy(mounds) - dilate(ridge, 1)

    return dict(rng=rng, wall=wall, blobs=blobs, ridge=ridge, cliffs=cliffs, face=face,
                dark=dark, mounds=mounds, walk=main,
                objs=objs, anims=anims, details=details, rubble=rubble)


def paint(m):
    rng = m['rng']
    layers = {k: {} for k in ('grounddark', 'mound', 'ridge', 'details', 'objlow',
                              'collision')}
    for c in sorted(m['dark']):
        t = nine_slice(m['dark'], c[0], c[1], DARK)
        if t:
            layers['grounddark'][c] = t
    for c in sorted(m['mounds']):
        t = nine_slice(m['mounds'], c[0], c[1], MOUND)
        if t:
            layers['mound'][c] = t
    layers['ridge'].update(m['cliffs'])
    for c in m['ridge'] | m['face']:
        if in_bounds(*c):
            layers['collision'][c] = COLLIDER
    return layers


def decorate(m, layers, rng, spawn_clear):
    solid = m['ridge'] | m['face']
    free = {c for c in m['walk'] if dist_c(c) > ARENA_CLEAR} - spawn_clear
    free -= dilate(solid, 1)
    occ = set(dilate(solid, 1)) | set(spawn_clear)
    sprites = []

    tall = [o for o in m['objs'] if o['h'] >= 3]
    short = [o for o in m['objs'] if o['h'] < 3]

    def place(pool, target, pad, tries, into=None, mirror=True):
        n = 0
        for _ in range(tries):
            if n >= target:
                break
            s = rng.choice(pool)
            x = rng.randint(WALL, MAP_W - s['w'] - WALL)
            y = rng.randint(WALL, MAP_H - s['h'] - WALL)
            base = {(x + dx, y + s['h'] - 1 - k) for dx in range(s['w']) for k in (0, 1)}
            if not base <= free:
                continue
            cells = {(x + dx, y + dy) for dy in range(s['h']) for dx in range(s['w'])}
            if cells & occ:
                continue
            (into if into is not None else sprites).append(
                dict(kind='obj', x=x, y=y, w=s['w'], h=s['h'], col=s['col'], row=s['row'],
                     fh=mirror and rng.random() < 0.5, sheet=s.get('sheet', 'objects')))
            for dy in range(-pad, s['h'] + pad):
                for dx in range(-pad, s['w'] + pad):
                    occ.add((x + dx, y + dy))
            n += 1
        return n

    anim_sprites = []
    n_tall = place(tall, 70, 1, 9000)
    n_anim = place(m['anims'], 10, 1, 4000, into=anim_sprites, mirror=False)

    n_low = 0
    for _ in range(6000):
        if n_low >= 120:
            break
        s = rng.choice(short)
        x = rng.randint(WALL, MAP_W - s['w'] - WALL)
        y = rng.randint(WALL, MAP_H - s['h'] - WALL)
        cells = {(x + dx, y + dy) for dy in range(s['h']) for dx in range(s['w'])}
        if not cells <= free or cells & occ:
            continue
        fh = rng.random() < 0.5
        for src, c, r, f0, dx, dy in s['body']:
            tx = x + (s['w'] - 1 - dx if fh else dx)
            layers['objlow'][(tx, y + dy)] = (src, c, r, fh != f0)
        occ |= cells
        n_low += 1

    det = set()
    n_det = 0
    for _ in range(12000):
        if n_det >= 620:
            break
        s = rng.choice(m['details'])
        x = rng.randint(WALL, MAP_W - s['w'] - WALL)
        y = rng.randint(WALL, MAP_H - s['h'] - WALL)
        cells = {(x + dx, y + dy) for dy in range(s['h']) for dx in range(s['w'])}
        if not cells <= m['walk'] or cells & det:
            continue
        fh = rng.random() < 0.5
        for src, c, r, f0, dx, dy in s['body']:
            tx = x + (s['w'] - 1 - dx if fh else dx)
            layers['details'][(tx, y + dy)] = (src, c, r, fh != f0)
        det |= cells
        n_det += 1

    print('arena decor: tall=%d anim=%d low=%d details=%d' % (n_tall, n_anim, n_low, n_det))
    return sprites, anim_sprites


# ------------------------------------------------------------------ tileset
def existing_undead_tiles():
    """Tiles the already-shipped UndeadForest scene relies on."""
    nodes, _ = GS.parse_scene(os.path.join(PROJ, 'Scenes', 'Levels', 'UndeadForest.tscn'))
    by_id = {v: k for k, v in EG.SRC_ID.items()}
    used = {}
    for n in nodes:
        if n['type'] != 'TileMapLayer':
            continue
        cells = GS.decode_tile_map_data(n['body'])
        for (src, c, r, alt) in cells.values():
            used.setdefault(by_id[src], set()).add((c, r))
    return used
