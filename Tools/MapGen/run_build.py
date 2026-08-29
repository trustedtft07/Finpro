import build_map as B, preview as P, populate as PP, pickle, random
from PIL import Image

def main(save_preview=True):
    m = B.build(); L = B.paint(m)
    rng = random.Random(7)
    walk = m['walk']
    cand = sorted(c for c in walk if 10 < c[0] < 26 and 60 < c[1] < 90)
    sx, sy = cand[len(cand)//2]
    spawn_clear = {(sx+dx, sy+dy) for dx in range(-7, 8) for dy in range(-6, 7)}
    sp, an = PP.populate(m, L, rng, spawn_clear)
    print('spawn', sx, sy, 'sprites', len(sp), 'anim', len(an))
    pickle.dump((m, L, sp, an, (sx, sy)), open('map.pkl', 'wb'))
    if save_preview:
        spr = [dict(src=('objects' if s['sheet']=='objects' else s['sheet']), col=s['col'],
                    row=s['row'], w=s['w'], h=s['h'], x=s['x'], ty=s['y'],
                    y=s['y']+s['h'], fh=s['fh']) for s in sp+an]
        P.render(L, spr, out='prev_full.png')
        im = Image.open('prev_full.png')
        im.resize((1500, 938), Image.LANCZOS).save('prev_full_s.png')
        im.crop((600, 300, 1900, 1120)).save('prev_crop1.png')
        im.crop((2100, 1200, 3400, 2020)).save('prev_crop2.png')
    return m, L, sp, an, (sx, sy)

if __name__ == '__main__':
    main()
