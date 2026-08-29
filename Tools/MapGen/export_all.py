"""End-to-end: build the map, then write the Godot TileSet + scene."""
import math
import random
from collections import defaultdict

import run_build
import export_godot as EG
import export_scene as ES
from undead_gen import MAP_W, MAP_H


def pick_spots(rng, walk, spawn, count, min_sep, min_from_spawn):
    out = []
    cells = sorted(walk)
    for _ in range(count * 400):
        if len(out) >= count:
            break
        c = rng.choice(cells)
        if math.dist(c, spawn) < min_from_spawn:
            continue
        if any(math.dist(c, o) < min_sep for o in out):
            continue
        # keep a little breathing room around it
        if not all((c[0] + dx, c[1] + dy) in walk
                   for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
            continue
        out.append(c)
    return out


def main():
    m, layers, sprites, anims, spawn = run_build.main(save_preview=True)

    used = defaultdict(set)
    for cells in layers.values():
        for t in cells.values():
            used[t[0]].add((t[1], t[2]))
    used[EG.GR].add(EG.COLLIDER_CR)

    print('tileset sources:', {k: len(v) for k, v in used.items()})
    EG.write_tileset(used)

    rng = random.Random(4242)
    enemies = pick_spots(rng, m['walk'], spawn, 16, 14, 34)
    coins = pick_spots(rng, m['walk'], spawn, 14, 10, 20)
    ES.write_scene(layers, sprites, anims, spawn, enemies, coins)
    print('enemies', len(enemies), 'coins', len(coins))


if __name__ == '__main__':
    main()
