"""Author the prop physics polygons of both forest tilesets from the art itself.

The props are multi-cell tiles on a 1px atlas grid (see "Props: tiles and collision"
in README.md), so a polygon written into the .tres is *not* in art space:

    art region, unflipped   left = -W/2 - texture_origin.x   top = -H/2 - texture_origin.y
    art region, FLIP_H      left = -W/2 + texture_origin.x   (the engine negates
                                                              texture_origin.x)
    collision                the engine mirrors the stored polygon about x = 0 when
                             the cell is placed with FLIP_H, so alternative 1 has to
                             store the *pre-mirrored* polygon

Both rules were measured against Godot 4.6 rather than assumed - see the probe notes
in README.md. This script takes the base band of each solid prop's own silhouette,
erodes away the wispy bits (root tendrils, thin bones), and writes one convex hull
per remaining lump.

    python prop_collision.py --out <dir>      # writes the two .tres files into <dir>
"""
import argparse
import base64
import os
import re
import struct

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))

# band = px of the art's silhouette, measured up from its lowest opaque row, that the
#        prop actually rests on. None means the whole sprite is its own footprint.
# erode = radius of the binary erosion that removes tendrils before hulling.
# keep  = how many separate lumps may become separate polygons.
SOLID = {
    'Art/Forest/GreenForestTileSet.tres': {
        (75, 0):    dict(band=None, erode=1),          # fallen log, lying down
        (75, 32):   dict(band=None, erode=1),          # fallen log, lying down
        (11, 143):  dict(band=18, erode=1),            # big tree, root flare
        (88, 143):  dict(band=18, erode=1),            # big tree
        (163, 163): dict(band=16, erode=1),            # small tree
        (211, 163): dict(band=16, erode=1),            # small tree
    },
    'Art/UndeadForest/UndeadForestTileSet.tres': {
        (416, 16):  dict(band=30, erode=2, keep=2),    # ruin: pillars over rubble
        (112, 48):  dict(band=26, erode=2, keep=2),    # ruin: stone arch
        (608, 48):  dict(band=26, erode=2, keep=2),    # rocks + broken pillar
        (288, 64):  dict(band=22, erode=1, keep=2),    # small rocks + pillar stub
        (16, 112):  dict(band=16, erode=1),            # dead tree, root flare
        (16, 192):  dict(band=28, erode=2, keep=2),    # boulders
        (128, 208): dict(band=22, erode=1),            # white stones, small
        (480, 208): dict(band=28, erode=2, keep=2),    # white stones, cluster
        (64, 320):  dict(band=None, erode=5),          # skeleton king: skull + torso
        (288, 320): dict(band=26, erode=2),            # big skull
        (16, 336):  dict(band=26, erode=2),            # skull over bones
        (992, 384): dict(band=24, erode=2),            # horned skull
        (416, 432): dict(band=28, erode=2, keep=2),    # skull pile
        (16, 496):  dict(band=20, erode=2),            # dead white tree
    },
}

# Bushes block nothing - they get a polygon on physics layer 1 ("Foliage", bit 8), which
# no body masks, purely so the player can sense that it is standing in one and wade.
FOLIAGE_BIT = 128
BUSHES = {
    'Art/Forest/GreenForestTileSet.tres': {
        (13, 4):     dict(band=None, erode=1),     # leafy shrub
        (15, 35):    dict(band=None, erode=1),     # leafy shrub, dark
    },
    'Art/UndeadForest/UndeadForestTileSet.tres': {
        (544, 144):  dict(band=None, erode=1),     # dead twig bush
        (80, 272):   dict(band=None, erode=1),     # dead twig bush, small
        (1008, 448): dict(band=None, erode=1),     # orange thorn bush
        (272, 464):  dict(band=None, erode=1),     # orange thorn bush, small
    },
}

# GreenForest's ground rocks are 32x32 tiles in the 16px *decor* atlas, not the 1px prop
# atlas, so they are plain `size_in_atlas` tiles with no texture_origin: a rock's whole
# silhouette is its footprint.
DECOR_SOLID = {
    'Art/Forest/GreenForestTileSet.tres': {
        (10, 6): dict(band=None, erode=1), (12, 6): dict(band=None, erode=1),
        (14, 6): dict(band=None, erode=1),         # single stones
        (10, 8): dict(band=None, erode=1), (12, 8): dict(band=None, erode=1),
        (14, 8): dict(band=None, erode=1),         # boulder piles
    },
}

# Props that stayed as nodes: UndeadForest's 46 animated ones (tile animation runs off one
# clock and would put every instance of a kind in lockstep) and all of BossPlace's, which
# was never converted to tiles. Their collision cannot live in the tileset, so it is
# emitted as one StaticBody2D per scene. The animated kinds are keyed by source region
# because the two scenes number their SpriteFrames differently.
ANIMATED_KINDS = {
    ('Objects_animated3.png', 16, 16):  dict(band=24, erode=2),   # big gnarled dead tree
    ('Objects_animated3.png', 16, 144): dict(band=20, erode=2),   # gnarled dead tree
    ('Objects_animated3.png', 16, 240): dict(band=22, erode=2),   # dead stump
    ('Objects_animated3.png', 16, 416): dict(band=30, erode=2),   # skull shrine
    ('Objects_animated.png', 16, 304):  dict(band=30, erode=2),   # stone gate
    ('Objects_animated.png', 16, 528):  dict(band=26, erode=2),   # skull gravestone
}
OBJECTS_SHEET = 'Objects.png'
UNDEAD_TRES = 'Art/UndeadForest/UndeadForestTileSet.tres'

# scene -> (parent node holding the props, does its foliage get the bush z-lift?)
SPRITE_PROPS = {
    'res://Scenes/Levels/UndeadForest.tscn': 'PropsAnimated',
    'res://Scenes/Levels/BossPlace.tscn': 'Props',
}
# Bushes draw over the player so walking into one hides them. In the arena that is all
# they do - a slow field in a boss fight reads as the dodge being cheated.
BUSH_Z = 1

ALPHA = 24        # opaque threshold; below this is anti-alias fringe
MIN_AREA = 36     # a lump smaller than this is scenery, not an obstacle
MIN_SPAN = 6      # ...and so is one thinner than this in either axis
SIMPLIFY = 1.0    # hull simplification tolerance, px


# --------------------------------------------------------------------------- mask ops
def erode(mask, r):
    """Binary erosion by a (2r+1)^2 square, via a summed-area table."""
    if r <= 0:
        return mask.copy()
    h, w = mask.shape
    pad = np.zeros((h + 2 * r, w + 2 * r), np.int32)
    pad[r:r + h, r:r + w] = mask
    ii = pad.cumsum(0).cumsum(1)
    ii = np.pad(ii, ((1, 0), (1, 0)))
    k = 2 * r + 1
    tot = (ii[k:k + h, k:k + w] - ii[0:h, k:k + w]
           - ii[k:k + h, 0:w] + ii[0:h, 0:w])
    return tot == k * k


def components(mask):
    """8-connected components, largest first, as lists of (x, y)."""
    h, w = mask.shape
    seen = np.zeros_like(mask, bool)
    out = []
    for sy in range(h):
        for sx in range(w):
            if not mask[sy, sx] or seen[sy, sx]:
                continue
            stack = [(sx, sy)]
            seen[sy, sx] = True
            pix = []
            while stack:
                x, y = stack.pop()
                pix.append((x, y))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < w and 0 <= ny < h and mask[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            stack.append((nx, ny))
            out.append(pix)
    out.sort(key=len, reverse=True)
    return out


# ------------------------------------------------------------------------- geometry
def hull(points):
    """Monotone chain; returns the hull counter-clockwise in a y-down frame."""
    pts = sorted(set(points))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower = []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    upper = []
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def simplify_ring(ring, tol):
    """Drop hull vertices that sit within tol of the chord they bridge."""
    changed = True
    ring = list(ring)
    while changed and len(ring) > 3:
        changed = False
        for i in range(len(ring)):
            a, b, c = ring[i - 1], ring[i], ring[(i + 1) % len(ring)]
            ax, ay = a
            cx, cy = c
            L = ((cx - ax) ** 2 + (cy - ay) ** 2) ** 0.5
            if L == 0:
                continue
            d = abs((cx - ax) * (ay - b[1]) - (ax - b[0]) * (cy - ay)) / L
            if d <= tol:
                ring.pop(i)
                changed = True
                break
    return ring


def clockwise(ring):
    """Godot's own tile polygons wind clockwise in the y-down tile frame."""
    area = 0.0
    for i in range(len(ring)):
        x0, y0 = ring[i]
        x1, y1 = ring[(i + 1) % len(ring)]
        area += x0 * y1 - x1 * y0
    return ring if area > 0 else ring[::-1]


# ------------------------------------------------------------------------ tres parse
# Files are processed with '\n' throughout and written back with whatever they came in
# with - BossPlace.tscn is checked out CRLF, and rewriting it LF makes a two-line edit
# read as a whole-file change in every diff that is not git's own (`* text=auto`).
_NEWLINE = {}


def read_text(path):
    with open(path, encoding='utf-8', newline='') as f:
        raw = f.read()
    _NEWLINE[os.path.basename(path)] = '\r\n' if '\r\n' in raw else '\n'
    return raw.replace('\r\n', '\n')


def write_text(dst, text):
    nl = _NEWLINE.get(os.path.basename(dst), '\n')
    with open(dst, 'w', encoding='utf-8', newline='') as f:
        f.write(text.replace('\n', nl))


def read_tres(path):
    return read_text(path).split('\n')


def atlas_block(lines, atlas_id):
    """-> (start, end) line indices of the given [sub_resource ...] block."""
    start = None
    for i, ln in enumerate(lines):
        if ln.startswith('[sub_resource') and 'id="%s"' % atlas_id in ln:
            start = i
        elif start is not None and (ln.startswith('[sub_resource') or ln.startswith('[resource]')):
            return start, i
    return start, len(lines)


def parse_props(lines, lo, hi):
    """-> {(col,row): {'size': (w,h), 'alts': {alt: {'texture_origin': (x,y)}}}}"""
    props = {}
    for ln in lines[lo:hi]:
        m = re.match(r'^(\d+):(\d+)/(.*?) = (.*)$', ln.strip())
        if not m:
            continue
        c, r, key, val = int(m.group(1)), int(m.group(2)), m.group(3), m.group(4)
        p = props.setdefault((c, r), {'size': (1, 1), 'alts': {}})
        if key == 'size_in_atlas':
            mm = re.match(r'Vector2i\((\d+), (\d+)\)', val)
            p['size'] = (int(mm.group(1)), int(mm.group(2)))
            continue
        am = re.match(r'^(\d+)(?:/(.*))?$', key)
        if not am:
            continue
        a = p['alts'].setdefault(int(am.group(1)), {'texture_origin': (0, 0)})
        if am.group(2) == 'texture_origin':
            mm = re.match(r'Vector2i\((-?\d+), (-?\d+)\)', val)
            a['texture_origin'] = (int(mm.group(1)), int(mm.group(2)))
    return props


def region_size(lines, lo, hi):
    for ln in lines[lo:hi]:
        m = re.match(r'^texture_region_size = Vector2i\((\d+), (\d+)\)$', ln.strip())
        if m:
            return int(m.group(1)), int(m.group(2))
    return 16, 16                        # Godot's default when the line is absent


def texture_of(lines, lo, hi):
    tex_id = None
    for ln in lines[lo:hi]:
        m = re.match(r'^texture = ExtResource\("([^"]+)"\)$', ln.strip())
        if m:
            tex_id = m.group(1)
            break
    for ln in lines:
        m = re.match(r'\[ext_resource type="Texture2D" uid="[^"]*" path="([^"]+)" id="%s"\]'
                     % re.escape(tex_id), ln)
        if m:
            return m.group(1)
    raise SystemExit('texture %s not found' % tex_id)


# ----------------------------------------------------------------------------- build
def footprint(art, cfg):
    """-> list of hulls, each a ring of (u, v) corner coords in the art region."""
    mask = np.array(art)[:, :, 3] > ALPHA
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return []
    v1 = int(ys.max())
    band = cfg.get('band')
    v0 = 0 if band is None else max(0, v1 - band + 1)

    sub = mask.copy()
    sub[:v0] = False
    sub[v1 + 1:] = False

    r = cfg.get('erode', 1)
    thin = erode(sub, r)
    while r > 0 and not thin.any():
        r -= 1
        thin = erode(sub, r)
    if not thin.any():
        thin = sub

    rings = []
    for pix in components(thin)[:cfg.get('keep', 1)]:
        if len(pix) < MIN_AREA:
            continue
        px = [p[0] for p in pix]
        py = [p[1] for p in pix]
        if max(px) - min(px) + 1 < MIN_SPAN or max(py) - min(py) + 1 < MIN_SPAN:
            continue
        # give back the pixels the erosion ate, then hull the pixel corners
        corners = []
        for x, y in pix:
            corners += [(x - r, y - r), (x + 1 + r, y - r),
                        (x + 1 + r, y + 1 + r), (x - r, y + 1 + r)]
        ring = simplify_ring(hull(corners), SIMPLIFY)
        # never let the erosion pad-back push the hull outside the sprite
        w, h = art.size
        ring = [(min(max(x, 0), w), min(max(y, 0), h)) for x, y in ring]
        rings.append(clockwise(simplify_ring(ring, 0.0)))
    return rings


def to_local(ring, size, torigin, flipped):
    """Art-region corner coords -> the polygon to store on that alternative."""
    w, h = size
    tox, toy = torigin
    top = -h / 2.0 - toy
    if not flipped:
        left = -w / 2.0 - tox
        out = [(left + u, top + v) for u, v in ring]
    else:
        # the flipped tile draws source column u at region column (w - u), and the
        # engine then mirrors whatever polygon is stored - so store the mirror.
        left = -w / 2.0 + tox
        out = [(-(left + w - u), top + v) for u, v in ring]
        out.reverse()
    return out


def fmt(ring):
    def n(v):
        return str(int(v)) if float(v).is_integer() else ('%g' % v)
    return 'PackedVector2Array(%s)' % ', '.join('%s, %s' % (n(x), n(y)) for x, y in ring)


def _rings_for(tex, props, cfgs, region, label, report):
    """Footprint rings per tile, in art-region corner coords."""
    out = {}
    for key, cfg in cfgs.items():
        if key not in props:
            raise SystemExit('no tile %d:%d in %s' % (key[0], key[1], label))
        c, r = key
        w, h = props[key]['size'][0] * region[0], props[key]['size'][1] * region[1]
        x, y = c * region[0], r * region[1]
        rings = footprint(tex.crop((x, y, x + w, y + h)), cfg)
        if not rings:
            raise SystemExit('%s: %d:%d produced no footprint' % (label, c, r))
        out[key] = rings
        report.append('  %-10s %3dx%-3d  %d poly  %s'
                      % ('%d:%d' % key, w, h, len(rings),
                         ' '.join('%dpt' % len(p) for p in rings)))
    return out


def _emit(atlas, lines, lo, hi, tres_rel, report):
    """-> (lines to drop, {(tile, alt): [lines to add after that tile's block]})"""
    props = parse_props(lines, lo, hi)
    tex_path = texture_of(lines, lo, hi)
    tex = Image.open(os.path.join(ROOT, tex_path.replace('res://', '').replace('/', os.sep))).convert('RGBA')
    region = region_size(lines, lo, hi)

    # physics layer 0 blocks the player; layer 1 only marks foliage for the bush slow
    jobs = []
    if atlas == 'Atlas_props':
        jobs.append((0, SOLID.get(tres_rel, {})))
        jobs.append((1, BUSHES.get(tres_rel, {})))
    else:
        jobs.append((0, DECOR_SOLID.get(tres_rel, {})))

    owned = set()
    add = {}
    for layer, cfgs in jobs:
        if not cfgs:
            continue
        report.append('  physics_layer_%d:' % layer)
        rings_of = _rings_for(tex, props, cfgs, region, tres_rel, report)
        owned |= set(cfgs)
        for key, rings in rings_of.items():
            for alt in props[key]['alts']:
                pre = '%d:%d/%d/physics_layer_%d' % (key[0], key[1], alt, layer)
                buf = add.setdefault((key, alt), [])
                if len(rings) > 1:
                    buf.append('%s/polygons_count = %d' % (pre, len(rings)))
                size = (props[key]['size'][0] * region[0], props[key]['size'][1] * region[1])
                for n, ring in enumerate(rings):
                    local = to_local(ring, size,
                                     props[key]['alts'][alt]['texture_origin'], alt != 0)
                    buf.append('%s/polygon_%d/points = %s' % (pre, n, fmt(local)))
    return owned, add


def rewrite(tres_rel, out_dir, report):
    path = os.path.join(ROOT, tres_rel)
    lines = read_tres(path)

    owned, add = {}, {}
    spans = []
    for atlas in ('Atlas_props', 'Atlas_decor'):
        lo, hi = atlas_block(lines, atlas)
        if lo is None:
            continue
        o, a = _emit(atlas, lines, lo, hi, tres_rel, report)
        if not o:
            continue
        spans.append((lo, hi, o))
        add.update(a)

    def group_of(i):
        """The (tile, alt) a line belongs to, or None."""
        for lo, hi, o in spans:
            if not (lo <= i < hi):
                continue
            m = re.match(r'^(\d+):(\d+)/(\d+)(?:/(.*?))? = ', lines[i].strip())
            if m:
                key = (int(m.group(1)), int(m.group(2)))
                if key in o:
                    return key, int(m.group(3)), (m.group(4) or '')
        return None

    # Drop what a previous run wrote *first*: the anchor pass below looks at the next
    # line to find the end of a tile's block, and must not defer to one that is going away.
    kept = []
    for i in range(len(lines)):
        g = group_of(i)
        if g and g[2].startswith('physics_layer_'):
            continue
        kept.append((lines[i], g))

    out = []
    for j, (ln, g) in enumerate(kept):
        out.append(ln)
        # emit at the end of each tile/alt block, after texture_origin / y_sort_origin
        if g:
            nxt = kept[j + 1][1] if j + 1 < len(kept) else None
            if (nxt is None or nxt[:2] != g[:2]) and (g[0], g[1]) in add:
                out += add.pop((g[0], g[1]))

    if add:
        raise SystemExit('%s: no anchor line for %s' % (tres_rel, sorted(add)))

    if BUSHES.get(tres_rel):
        out = declare_layer(out, 1, FOLIAGE_BIT)

    dst = os.path.join(out_dir, os.path.basename(tres_rel))
    write_text(dst, '\n'.join(out))
    return dst


def declare_layer(lines, index, bit):
    """Make sure [resource] declares physics_layer_<index> on the given bit."""
    key = 'physics_layer_%d/collision_layer' % index
    for i, ln in enumerate(lines):
        if ln.startswith(key + ' ='):
            lines[i] = '%s = %d' % (key, bit)
            return lines
    at = lines.index('[resource]')
    prev = 'physics_layer_%d/collision_layer' % (index - 1)
    for j in range(at, len(lines)):
        if lines[j].startswith(prev):
            lines.insert(j + 1, '%s = %d' % (key, bit))
            return lines
    raise SystemExit('no %s to insert after' % prev)


# ------------------------------------------------------- animated props (scene side)
BODY = 'PropsCollision'


def _scene_regions(text):
    """-> (atlas id -> (sheet basename, rect), SpriteFrames id -> (sheet basename, rect))"""
    ext = {m.group(2): os.path.basename(m.group(1)) for m in re.finditer(
        r'\[ext_resource type="Texture2D" uid="[^"]*" path="([^"]+)" id="([^"]+)"\]', text)}
    paths = {m.group(2): m.group(1) for m in re.finditer(
        r'\[ext_resource type="Texture2D" uid="[^"]*" path="([^"]+)" id="([^"]+)"\]', text)}
    atlases = {}
    for m in re.finditer(r'\[sub_resource type="AtlasTexture" id="([^"]+)"\]\s*\n'
                         r'atlas = ExtResource\("([^"]+)"\)\s*\n'
                         r'region = Rect2\(([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+)\)', text):
        eid = m.group(2)
        atlases[m.group(1)] = (ext[eid], paths[eid],
                               tuple(int(float(m.group(i))) for i in (3, 4, 5, 6)))
    frames = {}
    for m in re.finditer(r'\[sub_resource type="SpriteFrames" id="(\w+)"\]\s*\n'
                         r'animations = \[\{\s*\n"frames": \[(.*?)\],', text, re.S):
        first = re.search(r'SubResource\("([^"]+)"\)', m.group(2)).group(1)
        frames[m.group(1)] = atlases[first]
    return atlases, frames


def _kind_cfg(sheet, x, y):
    """-> (solid footprint cfg or None, is it a bush?)"""
    if sheet == OBJECTS_SHEET:
        return SOLID[UNDEAD_TRES].get((x, y)), (x, y) in BUSHES[UNDEAD_TRES]
    return ANIMATED_KINDS.get((sheet, x, y)), False


def patch_sprite_props(scene_rel, out_dir, report):
    """Collision for the props a scene keeps as nodes, plus the bush z-lift.

    Both node kinds are centred with `offset = (0, -h/2)`, so the art's bottom edge sits
    exactly on the node origin: art (u, v) -> local (u - w/2, v - h), mirrored about x
    when the node is flipped.
    """
    text = scene_text(scene_rel, out_dir)
    parent = SPRITE_PROPS[scene_rel]
    atlases, frames = _scene_regions(text)

    rings_of = {}

    def rings_for(sheet, tex_path, rect):
        key = (sheet, rect[0], rect[1])
        if key in rings_of:
            return rings_of[key]
        cfg, bush = _kind_cfg(sheet, rect[0], rect[1])
        if cfg is None:
            rings_of[key] = (None, bush)
            return rings_of[key]
        x, y, w, h = rect
        tex = Image.open(os.path.join(ROOT, tex_path.replace('res://', '').replace('/', os.sep)))
        rings = footprint(tex.convert('RGBA').crop((x, y, x + w, y + h)), cfg)
        if not rings:
            raise SystemExit('%s: %s %d,%d produced no footprint' % (scene_rel, sheet, x, y))
        rings_of[key] = ([[(u - w / 2.0, v - h) for u, v in r] for r in rings], bush)
        report.append('  %-22s %4d,%-4d %3dx%-3d  %d poly'
                      % (sheet, x, y, w, h, len(rings)))
        return rings_of[key]

    solids, bushes = [], []
    for m in re.finditer(r'\[node name="(\w+)" type="(Sprite2D|AnimatedSprite2D)" '
                         r'parent="%s"[^\]]*\]\n(.*?)(?=\n\[node |\Z)' % re.escape(parent),
                         text, re.S):
        name, kind, body = m.group(1), m.group(2), m.group(3)
        pos = re.search(r'position = Vector2\(([-\d.]+), ([-\d.]+)\)', body)
        if not pos:
            continue
        if kind == 'Sprite2D':
            tid = re.search(r'texture = SubResource\("(\w+)"\)', body)
            entry = atlases.get(tid.group(1)) if tid else None
        else:
            sid = re.search(r'sprite_frames = SubResource\("(\w+)"\)', body)
            entry = frames.get(sid.group(1)) if sid else None
        if entry is None:
            continue
        sheet, tex_path, rect = entry
        rings, bush = rings_for(sheet, tex_path, rect)
        if bush:
            bushes.append(name)
            continue
        if rings is None:
            continue
        off = re.search(r'offset = Vector2\(([-\d.]+), ([-\d.]+)\)', body)
        if off and abs(float(off.group(2)) + rect[3] / 2.0) > 0.01:
            raise SystemExit('%s: %s offset %s is not -h/2'
                             % (scene_rel, name, off.group(2)))
        flip = bool(re.search(r'^flip_h = true$', body, re.M))
        solids.append((name, float(pos.group(1)), float(pos.group(2)), rings, flip))

    # drop a previous run's body and every node parented to it, so re-running is a no-op
    head, sep, rest = text.partition('\n[node ')
    kept = [head]
    for block in (sep + rest).split('\n[node ')[1:]:
        nm = re.match(r'name="([^"]+)"', block)
        pt = re.search(r'parent="([^"]*)"', block)
        if (nm and nm.group(1) == BODY) or (pt and pt.group(1) == BODY):
            continue
        kept.append('\n[node ' + block)
    text = ''.join(kept)

    out = ['[node name="%s" type="StaticBody2D" parent="."]' % BODY,
           'collision_layer = 1',
           'collision_mask = 0',
           '']
    for name, px, py, rings, flip in solids:
        for n, ring in enumerate(rings):
            r = [(-x, y) for x, y in ring][::-1] if flip else ring
            out += ['[node name="%s_%d" type="CollisionPolygon2D" parent="%s"]'
                    % (name, n, BODY),
                    'position = Vector2(%g, %g)' % (px, py),
                    'polygon = %s' % fmt(r),
                    '']
    block = '\n'.join(out)

    anchor = re.search(r'\n\[node name="Bonfire" parent="\."', text)
    if not anchor:
        raise SystemExit('%s: no Bonfire node to anchor the body before' % scene_rel)
    text = text[:anchor.start() + 1] + block + text[anchor.start() + 1:]

    # bushes draw over the player, so walking into one hides them
    for name in bushes:
        text = _set_node_prop(text, parent, name, 'z_index', str(BUSH_Z))

    dst = os.path.join(out_dir, os.path.basename(scene_rel))
    write_text(dst, text)
    report.append('  %d solid instance(s), %d bush(es) lifted to z=%d'
                  % (len(solids), len(bushes), BUSH_Z))
    return dst


def _set_node_prop(text, parent, name, key, value):
    """Set (or replace) one property line on a node."""
    m = re.search(r'\[node name="%s" type="\w+" parent="%s"[^\]]*\]\n'
                  % (re.escape(name), re.escape(parent)), text)
    if not m:
        raise SystemExit('no node %s under %s' % (name, parent))
    end = text.find('\n[node ', m.end())
    end = len(text) if end == -1 else end
    body = text[m.end():end]
    line = '%s = %s' % (key, value)
    if re.search(r'^%s = ' % re.escape(key), body, re.M):
        body = re.sub(r'^%s = .*$' % re.escape(key), line, body, flags=re.M)
    else:
        body = line + '\n' + body
    return text[:m.end()] + body + text[end:]


def drop_layer(scene_rel, node, out_dir, report):
    """Remove a whole TileMapLayer node from a scene."""
    text = scene_text(scene_rel, out_dir)
    pat = r'\n\[node name="%s" type="TileMapLayer" parent="\."[^\]]*\]\n.*?(?=\n\[node )' % node
    new, n = re.subn(pat, '\n', text, flags=re.S)
    report.append('  dropped %d "%s" node(s)' % (n, node))
    dst = os.path.join(out_dir, os.path.basename(scene_rel))
    write_text(dst, new)
    return dst


# ------------------------------------------------------------------ bushes (tile side)
BUSH_LAYER = 'Bushes'


def _decode_cells(blob):
    d = base64.b64decode(blob)
    out = {}
    for i in range((len(d) - 2) // 12):
        x, y, src, ax, ay, alt = struct.unpack_from('<hhHhhH', d, 2 + i * 12)
        out[(x, y)] = (src, ax, ay, alt)
    return out


def _encode_cells(cells):
    buf = bytearray(struct.pack('<H', 0))
    for (x, y) in sorted(cells):
        src, ax, ay, alt = cells[(x, y)]
        buf += struct.pack('<hhHhhH', x, y, src, ax, ay, alt)
    return base64.b64encode(bytes(buf)).decode()


def _layer_block(text, name):
    m = re.search(r'\[node name="%s" type="TileMapLayer" parent="\."[^\]]*\]\n' % name, text)
    if not m:
        return None
    end = text.find('\n[node ', m.end())
    end = len(text) if end == -1 else end
    return m.start(), m.end(), end


def split_bushes(scene_rel, tres_rel, out_dir, report):
    """Move the bush tiles out of Props into their own layer drawn over the player."""
    text = scene_text(scene_rel, out_dir)
    kinds = {k for k in BUSHES[tres_rel]}

    props = _layer_block(text, 'Props')
    if props is None:
        raise SystemExit('%s: no Props TileMapLayer' % scene_rel)
    cells = _decode_cells(re.search(r'tile_map_data = PackedByteArray\("([^"]*)"\)',
                                    text[props[1]:props[2]]).group(1))
    old = _layer_block(text, BUSH_LAYER)
    if old:                                   # fold a previous run back in first
        cells.update(_decode_cells(re.search(
            r'tile_map_data = PackedByteArray\("([^"]*)"\)', text[old[1]:old[2]]).group(1)))
        head = text[:old[0]]
        if head.endswith('\n\n'):
            head = head[:-1]      # the blank line that separated it, or re-runs stack them
        text = head + text[old[2]:]
        props = _layer_block(text, 'Props')

    bush = {c: v for c, v in cells.items() if (v[1], v[2]) in kinds}
    rest = {c: v for c, v in cells.items() if (v[1], v[2]) not in kinds}
    if not bush:
        raise SystemExit('%s: no bush tiles found in Props' % scene_rel)

    body = text[props[1]:props[2]]
    body = re.sub(r'tile_map_data = PackedByteArray\("[^"]*"\)',
                  'tile_map_data = PackedByteArray("%s")' % _encode_cells(rest), body)
    ts = re.search(r'tile_set = ExtResource\("([^"]+)"\)', body).group(1)
    layer = ('\n[node name="%s" type="TileMapLayer" parent="."]\n'
             'y_sort_enabled = true\n'
             'z_index = %d\n'
             'tile_map_data = PackedByteArray("%s")\n'
             'tile_set = ExtResource("%s")\n'
             % (BUSH_LAYER, BUSH_Z, _encode_cells(bush), ts))
    text = text[:props[1]] + body + layer + text[props[2]:]

    report.append('  %d bush tiles -> "%s" (z=%d), %d left in Props'
                  % (len(bush), BUSH_LAYER, BUSH_Z, len(rest)))
    dst = os.path.join(out_dir, os.path.basename(scene_rel))
    write_text(dst, text)
    return dst


def scene_text(scene_rel, out_dir):
    """Read the scene from out_dir if an earlier step already staged it there."""
    path = os.path.join(ROOT, scene_rel.replace('res://', '').replace('/', os.sep))
    text = read_text(path)                # also records the file's real line endings
    staged = os.path.join(out_dir, os.path.basename(scene_rel))
    if os.path.exists(staged):
        with open(staged, encoding='utf-8', newline='') as f:
            return f.read().replace('\r\n', '\n')
    return text


GREEN = 'res://Scenes/Levels/GreenForest.tscn'
UNDEAD = 'res://Scenes/Levels/UndeadForest.tscn'
BOSS = 'res://Scenes/Levels/BossPlace.tscn'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default='out')
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)

    def step(label, fn, *args):
        report = [label]
        dst = fn(*args, a.out, report)
        print('\n'.join(report))
        print('  -> %s' % dst)

    for tres in SOLID:
        step(tres, rewrite, tres)
    # Scene steps chain through out/, so several may touch the same scene.
    step(GREEN, split_bushes, GREEN, 'Art/Forest/GreenForestTileSet.tres')
    # GreenForest carried one invisible 16x16 collider per tall tree, anchored to the
    # prop's *cell* - which the tile conversion left ~40px up in the canopy. The prop
    # tiles now carry a trunk-shaped polygon, so the layer is dead weight.
    step(GREEN, drop_layer, GREEN, 'Collision')
    step(UNDEAD, split_bushes, UNDEAD, UNDEAD_TRES)
    step(UNDEAD, patch_sprite_props, UNDEAD)
    step(BOSS, patch_sprite_props, BOSS)


if __name__ == '__main__':
    main()
