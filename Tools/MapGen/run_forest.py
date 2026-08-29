import math, pickle, random
from collections import defaultdict
import build_forest as B, export_forest as E, fpreview as P, forest_gen as G
from undead_gen import MAP_W, MAP_H, dilate
from PIL import Image


def pick(rng, walk, spawn, count, sep, from_spawn):
    out = []
    cells = sorted(walk)
    for _ in range(count * 500):
        if len(out) >= count:
            break
        c = rng.choice(cells)
        if math.dist(c, spawn) < from_spawn:
            continue
        if any(math.dist(c, o) < sep for o in out):
            continue
        if not all((c[0] + dx, c[1] + dy) in walk for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
            continue
        out.append(c)
    return out


def main(preview=True):
    m = B.build()
    L = B.paint(m)
    rng = random.Random(11)
    solid = (set(L['rocks']) - m['ramps']) | m['water']
    walk = (m['grass'] | m['dirt']) - solid - m['wall']
    cand = sorted(c for c in walk if 12 < c[0] < 30 and 60 < c[1] < 90)
    sx, sy = cand[len(cand) // 2]
    spawn_clear = {(sx + dx, sy + dy) for dx in range(-7, 8) for dy in range(-6, 7)}
    sprites = B.place_decor(m, L, rng, spawn_clear)
    walk2 = walk - set(L['collision'])
    enemies = pick(rng, walk2, (sx, sy), 16, 14, 34)
    coins = pick(rng, walk2, (sx, sy), 14, 10, 20)

    used = set()
    for key in ('dirtdetail', 'grass', 'dark', 'water', 'rocks', 'collision'):
        for t in L[key].values():
            used.add((t[0], t[1]))
    used.add(G.COLLIDER)
    decor_kinds = {(t[1], t[2], t[3], t[4]) for t in L['decor'].values()}
    print('tileset: %d tiles, %d decor kinds' % (len(used), len(decor_kinds)))
    E.write_tileset(used, decor_kinds)
    E.write_scene(L, sprites, (sx, sy), enemies, coins)
    pickle.dump((m, L, sprites, (sx, sy)), open('fmap.pkl', 'wb'))
    print('spawn', sx, sy, 'enemies', len(enemies), 'coins', len(coins))
    if preview:
        im = P.render(L, sprites, 'fprev.png')
        im.resize((1500, 938), Image.LANCZOS).save('fprev_s.png')
        im.crop((500, 400, 1800, 1220)).save('fprev_c1.png')
        im.crop((2100, 1300, 3400, 2120)).save('fprev_c2.png')
    return m, L, sprites, (sx, sy)


if __name__ == '__main__':
    main()
