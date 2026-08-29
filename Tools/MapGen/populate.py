"""Scatter rubble, water detail, ground details, props and animated props."""
import random
from collections import defaultdict

import tmxlib as T
import stamps as S
from undead_gen import MAP_W, MAP_H, in_bounds, dilate, COLLIDER


def water_detail_stamps():
    L = T.load_layers()
    out = []
    for l in [x for x in L if x['name'] == 'water_detailization']:
        for w, h, body in S.object_stamps(l['cells']):
            cells = []
            for dx, dy, g in body:
                ts, c, r, fh, fv, fd = T.decode(g)
                if ts['name'] != 'Water_detilazation':
                    break
                cells.append(('water_detail', c, r, fh, dx, dy))
            else:
                out.append(dict(w=w, h=h, body=cells))
    seen, uniq = set(), []
    for s in out:
        k = repr(sorted(s['body']))
        if k not in seen:
            seen.add(k)
            uniq.append(s)
    return uniq


def _fits(occ, x, y, w, h, allowed):
    for dy in range(h):
        for dx in range(w):
            c = (x + dx, y + dy)
            if c in occ or c not in allowed:
                return False
    return True


def _mark(occ, x, y, w, h, pad=0):
    for dy in range(-pad, h + pad):
        for dx in range(-pad, w + pad):
            occ.add((x + dx, y + dy))


def populate(m, layers, rng, spawn_clear):
    water = m['water']
    walk = m['walk']
    ridge = m['ridge']
    face = m['face']

    solid = ridge | face | water
    # ground an object may stand on
    free = {c for c in walk if c not in dilate(spawn_clear, 0)}
    occ = set(dilate(solid, 1)) | set(spawn_clear)

    sprites = []
    anim_sprites = []

    # --- water surface detail (animated) ---------------------------------
    wds = water_detail_stamps()
    if wds:
        for pool in m['pools']:
            n = max(1, len(pool) // 14)
            for _ in range(n * 3):
                if n <= 0:
                    break
                s = rng.choice(wds)
                px = rng.randint(min(p[0] for p in pool), max(p[0] for p in pool))
                py = rng.randint(min(p[1] for p in pool), max(p[1] for p in pool))
                if not _fits(set(), px, py, s['w'], s['h'], pool):
                    continue
                for src, c, r, fh, dx, dy in s['body']:
                    layers['waterdetail'][(px + dx, py + dy)] = (src, c, r, fh)
                n -= 1

    # --- rubble paths -----------------------------------------------------
    placed = 0
    for _ in range(2000):
        if not m['rubble'] or placed >= 55:
            break
        s = rng.choice(m['rubble'])
        x = rng.randint(6, MAP_W - s['w'] - 6)
        y = rng.randint(6, MAP_H - s['h'] - 6)
        if not _fits(set(), x, y, s['w'], s['h'], free):
            continue
        fh = rng.random() < 0.5
        for src, c, r, f0, dx, dy in s['body']:
            tx = x + (s['w'] - 1 - dx if fh else dx)
            layers['rubble'][(tx, y + dy)] = (src, c, r, fh != f0)
        placed += 1

    # --- tall props (y-sorted sprites) ------------------------------------
    tall = [o for o in m['objs'] if o['h'] >= 3]
    short = [o for o in m['objs'] if o['h'] < 3]
    big = [o for o in m['objs'] if o['w'] >= 4 and o['h'] >= 4]

    def place_props(pool_, count, pad, mirror=True, into=None):
        placed = 0
        for _ in range(count * 40):
            if placed >= count:
                break
            s = rng.choice(pool_)
            x = rng.randint(5, MAP_W - s['w'] - 5)
            y = rng.randint(5, MAP_H - s['h'] - 5)
            base = {(x + dx, y + s['h'] - 1 - k) for dx in range(s['w']) for k in (0, 1)}
            if not base <= free:
                continue
            cells = {(x + dx, y + dy) for dy in range(s['h']) for dx in range(s['w'])}
            if cells & occ or cells & water:
                continue
            fh = mirror and rng.random() < 0.5
            (into if into is not None else sprites).append(
                dict(kind='obj', x=x, y=y, w=s['w'], h=s['h'],
                     col=s['col'], row=s['row'], fh=fh, sheet=s.get('sheet', 'objects')))
            _mark(occ, x, y, s['w'], s['h'], pad)
            placed += 1
        return placed

    n_tall = place_props(tall, 430, 0)
    n_anim = place_props(m['anims'], 46, 1, mirror=False, into=anim_sprites)

    # --- low props straight onto a tile layer ------------------------------
    n_low = 0
    for _ in range(9000):
        if n_low >= 620:
            break
        s = rng.choice(short)
        x = rng.randint(5, MAP_W - s['w'] - 5)
        y = rng.randint(5, MAP_H - s['h'] - 5)
        cells = {(x + dx, y + dy) for dy in range(s['h']) for dx in range(s['w'])}
        if not cells <= free or cells & occ:
            continue
        fh = rng.random() < 0.5
        for src, c, r, f0, dx, dy in s['body']:
            tx = x + (s['w'] - 1 - dx if fh else dx)
            layers['objlow'][(tx, y + dy)] = (src, c, r, fh != f0)
        _mark(occ, x, y, s['w'], s['h'], 0)
        n_low += 1

    # --- ground details ----------------------------------------------------
    det_occ = set()
    n_det = 0
    for _ in range(20000):
        if n_det >= 1900:
            break
        s = rng.choice(m['details'])
        x = rng.randint(5, MAP_W - s['w'] - 5)
        y = rng.randint(5, MAP_H - s['h'] - 5)
        cells = {(x + dx, y + dy) for dy in range(s['h']) for dx in range(s['w'])}
        if not cells <= walk or cells & det_occ:
            continue
        fh = rng.random() < 0.5
        for src, c, r, f0, dx, dy in s['body']:
            tx = x + (s['w'] - 1 - dx if fh else dx)
            layers['details'][(tx, y + dy)] = (src, c, r, fh != f0)
        det_occ |= cells
        n_det += 1

    print('props tall=%d anim=%d low=%d details=%d' % (n_tall, n_anim, n_low, n_det))
    return sprites, anim_sprites
