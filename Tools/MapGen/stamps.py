"""Extract multi-tile 'stamps' (whole objects / terrain formations) from the reference map.

A stamp is a list of (dx, dy, gid) with dx,dy normalised to start at 0,0.
Objects are split per sprite-instance: cells belonging to one placed sprite share the same
(tileset, atlas_col - map_x, atlas_row - map_y) offset, so grouping by that offset and then
taking connected components recovers exactly what the artist stamped down.
"""
import tmxlib as T
from collections import defaultdict


def _components(cells, connectivity=8):
    """cells: iterable of (x,y). -> list of sets"""
    cells = set(cells)
    dirs4 = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    dirs8 = dirs4 + [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    dirs = dirs8 if connectivity == 8 else dirs4
    seen = set()
    out = []
    for c in cells:
        if c in seen:
            continue
        stack = [c]
        seen.add(c)
        comp = set()
        while stack:
            p = stack.pop()
            comp.add(p)
            for d in dirs:
                q = (p[0] + d[0], p[1] + d[1])
                if q in cells and q not in seen:
                    seen.add(q)
                    stack.append(q)
        out.append(comp)
    return out


def normalise(cellmap):
    """cellmap {(x,y): gid} -> (w, h, [(dx,dy,gid)])"""
    xs = [x for x, y in cellmap]
    ys = [y for x, y in cellmap]
    x0, y0 = min(xs), min(ys)
    body = sorted(((x - x0, y - y0, g) for (x, y), g in cellmap.items()), key=lambda t: (t[1], t[0]))
    return max(xs) - x0 + 1, max(ys) - y0 + 1, body


def object_stamps(layer_cells):
    """Split one object layer into individual sprite instances."""
    groups = defaultdict(dict)
    for (x, y), gid in layer_cells.items():
        ts, c, r, fh, fv, fd = T.decode(gid)
        # mirrored sprites run right-to-left in atlas space
        key = (ts['name'], fh, fv, (c + x) if fh else (c - x), r - y)
        groups[key][(x, y)] = gid
    out = []
    for key, cm in groups.items():
        for comp in _components(cm.keys(), 8):
            out.append(normalise({p: cm[p] for p in comp}))
    return out


def region_stamps(layer_cells, connectivity=8):
    """Whole connected formations (used for terrain: plateaus, brick patches)."""
    out = []
    for comp in _components(layer_cells.keys(), connectivity):
        out.append(normalise({p: layer_cells[p] for p in comp}))
    return out


def dedupe(stamps):
    seen = {}
    for w, h, body in stamps:
        k = (w, h, tuple(body))
        if k not in seen:
            seen[k] = [w, h, body, 0]
        seen[k][3] += 1
    return [(v[0], v[1], v[2], v[3]) for v in seen.values()]
