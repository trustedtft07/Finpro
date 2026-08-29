"""Re-pack the loose VFX pieces of Crystal Knight.png into uniform animation cells.

The source sheet is hand-packed: effects sit at arbitrary offsets and share space with
a black annotation bracket. Godot's AnimatedSprite2D needs equal-sized frames with a
consistent anchor, so each piece is lifted out by connected components and re-pasted
into a clean grid. Pixels are untouched - only their placement changes.
"""
import os
import numpy as np
from PIL import Image

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'Art', 'Boss')
SRC = Image.open(os.path.join(BASE, 'Phase2', 'Crystal Knight.png')).convert('RGBA')
A = np.asarray(SRC)
ALPHA = A[:, :, 3] > 8

CW, CH = 48, 64          # effects cell
BEAM_W, BEAM_H = 48, 80  # beam cell


def col_groups(y0, y1, x0, x1, gap=5):
    band = ALPHA[y0:y1, x0:x1]
    cols = band.any(axis=0)
    runs, s = [], None
    for i, v in enumerate(cols):
        if v and s is None:
            s = i
        elif not v and s is not None:
            runs.append((x0 + s, x0 + i - 1))
            s = None
    if s is not None:
        runs.append((x0 + s, x1 - 1))
    out = []
    for r in runs:
        if out and r[0] - out[-1][1] - 1 < gap:
            out[-1] = (out[-1][0], r[1])
        else:
            out.append(r)
    return out


def piece(x0, x1, y0, y1):
    """Tight crop of one piece plus its bbox inside the given window."""
    sub = ALPHA[y0:y1, x0:x1 + 1]
    ys, xs = np.nonzero(sub)
    bx0, bx1 = x0 + xs.min(), x0 + xs.max()
    by0, by1 = y0 + ys.min(), y0 + ys.max()
    return SRC.crop((bx0, by0, bx1 + 1, by1 + 1)), (bx0, by0, bx1 - bx0 + 1, by1 - by0 + 1)


def paste(sheet, img, col, row, anchor='center', cw=CW, ch=CH, pad=2):
    w, h = img.size
    x = col * cw + (cw - w) // 2
    if anchor == 'center':
        y = row * ch + (ch - h) // 2
    elif anchor == 'bottom':
        y = row * ch + ch - h - pad
    else:  # top
        y = row * ch + pad
    sheet.alpha_composite(img, (x, y))


def build_effects():
    cols = 5
    rows = 3
    sheet = Image.new('RGBA', (cols * CW, rows * CH), (0, 0, 0, 0))

    # row 0 - lightning strike (3 frames), anchored on the ground impact point
    for i, (x0, x1) in enumerate(col_groups(318, 386, 16, 200)):
        img, bb = piece(x0, x1, 318, 386)
        paste(sheet, img, i, 0, 'bottom')
        print('lightning %d: src %s -> cell(%d,0) size %s' % (i, bb, i, img.size))

    # row 1 - impact sparks (5 frames)
    for i, (x0, x1) in enumerate(col_groups(76, 118, 20, 340)):
        img, bb = piece(x0, x1, 76, 118)
        paste(sheet, img, i, 1, 'center')
        print('spark %d: src %s -> cell(%d,1) size %s' % (i, bb, i, img.size))

    # row 2 - small projectile spin (2), then its burst on impact (2)
    star = [(162, 174, 640, 658), (179, 189, 640, 658)]
    for i, (x0, x1, y0, y1) in enumerate(star):
        img, bb = piece(x0, x1, y0, y1)
        paste(sheet, img, i, 2, 'center')
        print('star %d: src %s' % (i, bb))
    burst, bb = piece(176, 207, 658, 688)
    paste(sheet, burst, 2, 2, 'center')
    print('burst: src %s' % (bb,))
    orb, bb = piece(146, 160, 660, 682)
    paste(sheet, orb, 3, 2, 'center')
    print('orb: src %s' % (bb,))
    return sheet


def build_beam():
    """Two crystal-blast frames, flipped so the narrow tip is the muzzle end."""
    sheet = Image.new('RGBA', (2 * BEAM_W, BEAM_H), (0, 0, 0, 0))
    for i, (x0, x1) in enumerate([(299, 339), (352, 364)]):
        img, bb = piece(x0, x1, 556, 640)
        img = img.transpose(Image.FLIP_TOP_BOTTOM)
        w, h = img.size
        sheet.alpha_composite(img, (i * BEAM_W + (BEAM_W - w) // 2, BEAM_H - h))
        print('beam %d: src %s size %s' % (i, bb, img.size))
    return sheet


if __name__ == '__main__':
    build_effects().save('BossEffects.png')
    build_beam().save('BossBeam.png')
    print('written')
