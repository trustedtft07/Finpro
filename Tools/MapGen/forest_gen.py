"""Green Forest map generation: terrain regions, autotiling, decoration stamps."""
import math
import os
import random
from collections import defaultdict

import numpy as np
from PIL import Image

import ftiles as F
from undead_gen import (MAP_W, MAP_H, DIRS8, in_bounds, blob, smooth, fill_holes,
                        open2x2, components, dilate)

TILES_SRC = 0          # Tileset.png
DECOR_SRC = 1          # Decorations.png

DIRT_RGB = (164, 97, 43)
COLLIDER = (0, 13)     # empty cell in Tileset.png, used only as a collision shape

BORDER = 5


def tidy(region, passes=3, thr=5):
    r = fill_holes(open2x2(smooth(region, passes, thr)))
    return {p for p in r if in_bounds(*p)}


def nine(region, x, y, table):
    return F.nine(region, x, y, table)


def convexify(region, rounds=12):
    """Fill concave corners. Tables without inner-corner pieces (water, dark grass)
    can only tile a region whose outline never turns inward."""
    region = set(region)
    for _ in range(rounds):
        add = set()
        for (x, y) in region:
            for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
                if (x + dx, y + dy) in region:
                    continue
                if (x + dx, y) in region and (x, y + dy) in region:
                    add.add((x + dx, y + dy))
        add = {c for c in add if in_bounds(*c)}
        if not add:
            break
        region |= add
    return region


def concave_cells(region):
    bad = set()
    for (x, y) in region:
        for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
            if (x + dx, y + dy) not in region and (x + dx, y) in region and (x, y + dy) in region:
                bad.add((x, y))
    return bad


# ---------------------------------------------------------------- decorations
def decoration_stamps():
    """Connected components of Decorations.png, with tile-aligned atlas boxes."""
    im = Image.open(F.DECOR).convert('RGBA')
    a = np.asarray(im)[:, :, 3] > 8
    H, W = a.shape
    seen = np.zeros_like(a, bool)
    out = []
    for y in range(H):
        for x in range(W):
            if not a[y, x] or seen[y, x]:
                continue
            stack = [(x, y)]
            seen[y, x] = True
            cells = []
            while stack:
                cx, cy = stack.pop()
                cells.append((cx, cy))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < W and 0 <= ny < H and a[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            stack.append((nx, ny))
            if len(cells) < 12:
                continue
            xs = [c[0] for c in cells]
            ys = [c[1] for c in cells]
            out.append(dict(px=min(xs), py=min(ys),
                            pw=max(xs) - min(xs) + 1, ph=max(ys) - min(ys) + 1,
                            area=len(cells)))
    return out


def tile_align(out):
    """Tile-aligned atlas boxes. Objects packed close together share a box, so merge
    any that overlap - the merged box is still one clean decoration."""
    boxes = []
    for s in out:
        boxes.append([s['px'] // 16, s['py'] // 16,
                      (s['px'] + s['pw'] - 1) // 16, (s['py'] + s['ph'] - 1) // 16, [s]])
    merged = True
    while merged:
        merged = False
        for i in range(len(boxes)):
            for j in range(i + 1, len(boxes)):
                a1, b1, c1, d1, m1 = boxes[i]
                a2, b2, c2, d2, m2 = boxes[j]
                if a1 <= c2 and a2 <= c1 and b1 <= d2 and b2 <= d1:
                    boxes[i] = [min(a1, a2), min(b1, b2), max(c1, c2), max(d1, d2), m1 + m2]
                    boxes.pop(j)
                    merged = True
                    break
            if merged:
                break
    res = []
    for c0, r0, c1, r1, members in boxes:
        px = min(m['px'] for m in members)
        py = min(m['py'] for m in members)
        pw = max(m['px'] + m['pw'] for m in members) - px
        ph = max(m['py'] + m['ph'] for m in members) - py
        res.append(dict(px=px, py=py, pw=pw, ph=ph, col=c0, row=r0,
                        tw=c1 - c0 + 1, th=r1 - r0 + 1,
                        area=sum(m['area'] for m in members)))
    return res


def classify(stamps, prop_min_h=25):
    """Split into tilemap-able small decor and y-sorted props."""
    small, props = [], []
    for s in stamps:
        (props if s['ph'] >= prop_min_h else small).append(s)
    return small, props


def check_boxes(stamps):
    """A tile-aligned box must not clip a neighbouring object."""
    im = Image.open(F.DECOR).convert('RGBA')
    a = np.asarray(im)[:, :, 3] > 8
    bad = []
    for s in stamps:
        x0, y0 = s['col'] * 16, s['row'] * 16
        x1, y1 = x0 + s['tw'] * 16, y0 + s['th'] * 16
        box = a[y0:y1, x0:x1]
        own = np.zeros_like(box)
        own[s['py'] - y0:s['py'] - y0 + s['ph'], s['px'] - x0:s['px'] - x0 + s['pw']] = \
            a[s['py']:s['py'] + s['ph'], s['px']:s['px'] + s['pw']]
        if (box & ~own).any():
            bad.append(s)
    return bad


def local_tidy(region, passes=3, thr=5):
    """Same as tidy() but only walks the region's own bounding box - the global
    version scans the whole map, which is far too slow for many small blobs."""
    region = set(region)
    if not region:
        return region
    for _ in range(passes):
        x0 = min(c[0] for c in region) - 2
        x1 = max(c[0] for c in region) + 3
        y0 = min(c[1] for c in region) - 2
        y1 = max(c[1] for c in region) + 3
        new = set()
        for y in range(y0, y1):
            for x in range(x0, x1):
                n = sum(1 for dx, dy in [(0, 0)] + DIRS8 if (x + dx, y + dy) in region)
                if n >= thr:
                    new.add((x, y))
        region = new
        if not region:
            return region
    # opening with a 2x2 element -> minimum width of two
    eroded = {c for c in region
              if (c[0] + 1, c[1]) in region and (c[0], c[1] + 1) in region
              and (c[0] + 1, c[1] + 1) in region}
    out = set()
    for (x, y) in eroded:
        out.update([(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)])
    return {c for c in out if in_bounds(*c)}
