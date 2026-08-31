"""Build the Green Forest map: terrain, plateaus with ramps, ponds, decoration."""
import math
import random
from collections import defaultdict

import ftiles as F
import forest_gen as G
from undead_gen import (MAP_W, MAP_H, DIRS8, in_bounds, blob, dilate,
                        components)

SEED = 20260830
BORDER = 2          # rock wall thickness around the map
PAD = BORDER + 1


def ring(a, b):
    return {(x, y) for y in range(MAP_H) for x in range(MAP_W)
            if x < b or y < b or x >= MAP_W - b or y >= MAP_H - b}


def walk_path(rng, x, y, length, thickness):
    ang = rng.uniform(0, math.tau)
    out = set()
    for _ in range(length):
        ang += rng.gauss(0, 0.32)
        x += math.cos(ang) * 1.3
        y += math.sin(ang) * 1.3
        if not in_bounds(int(x), int(y), PAD + 3):
            ang += math.pi
            x += 3 * math.cos(ang)
            y += 3 * math.sin(ang)
        cx, cy = int(round(x)), int(round(y))
        t = thickness + (1 if rng.random() < 0.3 else 0)
        for dy in range(-t, t + 1):
            for dx in range(-t, t + 1):
                if dx * dx + dy * dy <= t * t + 1:
                    out.add((cx + dx, cy + dy))
    return out


def scatter(rng, count, rmin, rmax, gap, avoid, elongate=0.0, pad=PAD + 2):
    out, taken, tries = [], set(), 0
    while len(out) < count and tries < count * 150:
        tries += 1
        r = rng.uniform(rmin, rmax)
        cx = rng.randint(int(r) + pad, MAP_W - int(r) - pad - 1)
        cy = rng.randint(int(r) + pad, MAP_H - int(r) - pad - 1)
        b = blob(rng, cx, cy, r, wobble=0.45)
        if rng.random() < elongate:
            k = rng.randint(3, 12)
            horiz = rng.random() < 0.65
            b = {(x + (i if horiz else 0), y + (0 if horiz else i))
                 for (x, y) in b for i in range(k)}
        if any(not in_bounds(x, y, pad) for x, y in b):
            continue
        if b & avoid or b & taken:
            continue
        out.append(b)
        taken |= dilate(b, gap)
    return out


def bottom_runs(region):
    """Cells on the region's bottom edge, grouped into horizontal runs."""
    bottom = sorted(c for c in region if (c[0], c[1] + 1) not in region)
    runs, cur = [], []
    for c in sorted(bottom, key=lambda p: (p[1], p[0])):
        if cur and c[1] == cur[-1][1] and c[0] == cur[-1][0] + 1:
            cur.append(c)
        else:
            if cur:
                runs.append(cur)
            cur = [c]
    if cur:
        runs.append(cur)
    return runs


def build():
    rng = random.Random(SEED)
    raw = G.decoration_stamps()
    small_raw, props = G.classify(raw, 25)
    small = [s for s in G.tile_align(small_raw) if s not in G.check_boxes(G.tile_align(small_raw))]
    print('decor: small=%d props=%d' % (len(small), len(props)))

    wall = ring(0, BORDER)
    keepout = dilate(wall, 2)

    # --- plateaus ---------------------------------------------------------
    plateaus = []
    for b in scatter(rng, 30, 3.2, 7.0, 7, keepout, elongate=0.4):
        b = G.local_tidy(b)
        if len(b) < 16:
            continue
        plateaus.append(b)
    plateau_all = set().union(*plateaus) if plateaus else set()

    # --- ponds ------------------------------------------------------------
    ponds = []
    for b in scatter(rng, 15, 3.0, 6.5, 6, dilate(plateau_all | keepout, 5), elongate=0.2):
        b = G.local_tidy(b)
        if len(b) < 14:
            continue
        ponds.append(b)
    water = set().union(*ponds) if ponds else set()

    # --- dirt paths & clearings ------------------------------------------
    dirt = set()
    for _ in range(11):
        dirt |= walk_path(rng, rng.randint(20, MAP_W - 20), rng.randint(20, MAP_H - 20),
                          rng.randint(40, 110), rng.choice((1, 2, 2, 3)))
    for _ in range(9):
        cx = rng.randint(16, MAP_W - 17)
        cy = rng.randint(16, MAP_H - 17)
        dirt |= blob(rng, cx, cy, rng.uniform(4, 9), wobble=0.5)
    dirt = G.tidy(dirt) - dilate(water, 3)

    # plateau surfaces: a mesa reads as raised when its top differs from around it
    surfaces = {}
    for i, p in enumerate(plateaus):
        on_dirt = len(p & dirt) > len(p) * 0.4
        surfaces[i] = 'grass' if on_dirt else 'dirt'
    for i, p in enumerate(plateaus):
        inner = {c for c in p if all((c[0] + dx, c[1] + dy) in p for dx, dy in DIRS8)}
        if surfaces[i] == 'dirt':
            dirt |= inner
        else:
            dirt -= inner

    grass = ({(x, y) for y in range(MAP_H) for x in range(MAP_W)} - dirt) - water
    # slivers of grass one cell wide have no matching tile - shave them back to dirt
    for _ in range(8):
        bad = {c for c in grass if F.nine(grass, c[0], c[1], F.GRASS) is None}
        if not bad:
            break
        grass -= bad
        dirt |= bad

    # --- dark grass patches ------------------------------------------------
    # Dark grass has no inner-corner pieces, so each patch is generated on its own
    # and kept convex; touching patches would create corners it cannot tile.
    dark_patches = []
    taken = set()
    for _ in range(900):
        if len(dark_patches) >= 70:
            break
        cx = rng.randint(PAD + 4, MAP_W - PAD - 5)
        cy = rng.randint(PAD + 4, MAP_H - PAD - 5)
        b = G.local_tidy(blob(rng, cx, cy, rng.uniform(2.6, 6.5), wobble=0.5))
        if len(b) < 10:
            continue
        if not b <= grass or b & taken:
            continue
        dark_patches.append(b)
        taken |= dilate(b, 2)
    dark = set().union(*dark_patches) if dark_patches else set()

    return dict(rng=rng, wall=wall, plateaus=plateaus, surfaces=surfaces, ponds=ponds,
                water=water, dirt=dirt, grass=grass, dark=dark, dark_patches=dark_patches,
                small=small, props=props)


def _drop_small(region, minsize):
    out = set()
    for c in components(region, 8):
        if len(c) >= minsize:
            out |= c
    return out


# ------------------------------------------------------------------- painting
LAYER_KEYS = ['dirtdetail', 'grass', 'dark', 'water', 'rocks', 'decor', 'collision']


def paint(m):
    rng = m['rng']
    layers = {k: {} for k in LAYER_KEYS}
    warn = 0

    # dirt speckle where dirt is actually visible
    visible_dirt = m['dirt'] - m['wall']
    for c in visible_dirt:
        if rng.random() < 0.11:
            layers['dirtdetail'][c] = rng.choice(F.DIRT_VARIANTS)

    for c in m['grass']:
        t = F.nine(m['grass'], c[0], c[1], F.GRASS)
        if t is None:
            warn += 1
            continue
        if t == F.GRASS['C'] and rng.random() < 0.022:
            t = rng.choice(F.GRASS_VARIANTS)
        layers['grass'][c] = t
    for patch in m['dark_patches']:
        for c in patch:
            t = F.nine(patch, c[0], c[1], F.GRASS_DARK)
            if t:
                layers['dark'][c] = t

    # ponds
    for pond in m['ponds']:
        for c in pond:
            t = F.nine(pond, c[0], c[1], F.WATER)
            if t is None:
                continue
            if t == F.WATER['C']:
                r = rng.random()
                if r < 0.05:
                    t = rng.choice(F.LILY)
                elif r < 0.14:
                    t = rng.choice(F.WATER_FILL)
            layers['water'][c] = t

    # rock walls: the border ring plus every plateau
    regions = [(m['wall'], 'dirt', False)]
    for i, p in enumerate(m['plateaus']):
        regions.append((p, m['surfaces'][i], True))
    ramp_cells = set()
    for region, surface, allow_ramp in regions:
        table = F.ROCK_GRASS if surface == 'grass' else F.ROCK_DIRT
        for c in region:
            t = F.nine(region, c[0], c[1], table)
            if t is None or t == table['C']:
                continue          # interior stays open ground
            layers['rocks'][c] = t
        if not allow_ramp:
            continue
        ramps = F.RAMP_GRASS if surface == 'grass' else F.RAMP_DIRT
        runs = [r for r in bottom_runs(region) if len(r) >= 6]
        runs.sort(key=len, reverse=True)
        for run in runs[:2 if len(runs) > 2 else 1]:
            start = run[len(run) // 2 - 2]
            cells = [(start[0] + i, start[1]) for i in range(4)]
            if any(c not in region for c in cells):
                continue
            if any((c[0], c[1] + 1) in region for c in cells):
                continue
            for i, c in enumerate(cells):
                layers['rocks'][c] = ramps[i]
                ramp_cells.add(c)

    m['ramps'] = ramp_cells
    if warn:
        print('WARNING: %d grass cells had no matching tile' % warn)
    return layers


def density_field(rng, cell=9, smooth_passes=2):
    """Coarse noise so trees clump into groves instead of spreading evenly."""
    gw, gh = MAP_W // cell + 2, MAP_H // cell + 2
    g = [[rng.random() for _ in range(gw)] for _ in range(gh)]
    for _ in range(smooth_passes):
        g = [[sum(g[min(max(j + dj, 0), gh - 1)][min(max(i + di, 0), gw - 1)]
                  for dj in (-1, 0, 1) for di in (-1, 0, 1)) / 9.0
              for i in range(gw)] for j in range(gh)]
    lo = min(min(r) for r in g)
    hi = max(max(r) for r in g)
    span = max(hi - lo, 1e-6)
    return lambda x, y: (g[y // cell][x // cell] - lo) / span


def place_decor(m, layers, rng, spawn_clear):
    """Small decorations onto the decor tile layer, props as y-sorted sprites."""
    solid = set(layers['rocks']) - m['ramps'] | m['water']
    free = (m['grass'] | m['dirt']) - solid - dilate(m['water'], 1) - m['wall']
    free = {c for c in free if in_bounds(c[0], c[1], PAD)} - spawn_clear
    occ = set(dilate(solid, 1)) | set(spawn_clear)

    sprites = []
    trees = [s for s in m['props'] if s['ph'] >= 60]
    shrubs = [s for s in m['props'] if s['ph'] < 60]

    grove = density_field(rng)

    def place(pool, target, pad, tries, clump=0.0):
        n = 0
        for _ in range(tries):
            if n >= target:
                break
            s = rng.choice(pool)
            tw = (s['pw'] + 15) // 16
            th = (s['ph'] + 15) // 16
            x = rng.randint(PAD, MAP_W - tw - PAD)
            y = rng.randint(PAD, MAP_H - th - PAD)
            cells = {(x + dx, y + dy) for dy in range(th) for dx in range(tw)}
            base = {(x + dx, y + th - 1) for dx in range(tw)}
            if not base <= free or cells & occ:
                continue
            if clump and rng.random() > (1.0 - clump) + clump * grove(x, y):
                continue
            sprites.append(dict(s=s, x=x, y=y, tw=tw, th=th, fh=rng.random() < 0.5))
            for c in cells:
                occ.add(c)
            for dy in range(-pad, th + pad):
                for dx in range(-pad, tw + pad):
                    occ.add((x + dx, y + dy))
            n += 1
        return n

    n_tree = place(trees, 430, 1, 40000, clump=0.8)
    n_shrub = place(shrubs, 700, 0, 30000, clump=0.35)

    n_small = 0
    for _ in range(60000):
        if n_small >= 2600:
            break
        s = rng.choice(m['small'])
        x = rng.randint(PAD, MAP_W - s['tw'] - PAD)
        y = rng.randint(PAD, MAP_H - s['th'] - PAD)
        cells = {(x + dx, y + dy) for dy in range(s['th']) for dx in range(s['tw'])}
        if not cells <= free or cells & occ:
            continue
        layers['decor'][(x, y)] = ('decor', s['col'], s['row'], s['tw'], s['th'])
        occ |= cells
        n_small += 1

    # Tree trunks used to block movement with one COLLIDER cell each, anchored to the
    # sprite's bottom tile. The shipped scene carries its props as tiles instead, whose
    # cell sits mid-canopy, so those colliders ended up ~40px above the trunks - an
    # invisible wall in open grass, with the trunk itself walkable. Trunk collision now
    # comes from the tileset (prop_collision.py), so nothing is emitted here.

    print('props: trees=%d shrubs=%d small=%d' % (n_tree, n_shrub, n_small))
    return sprites
