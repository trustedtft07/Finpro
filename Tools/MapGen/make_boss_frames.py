"""Emit the boss SpriteFrames resources.

Frame rectangles come from the measurements in the analysis pass:
  Phase 1 (Sword.png)  - a clean 128x64 grid; the character always sits with its
                         shadow centred at (31, 50), so a 64x64 crop per cell works.
  Phase 2 (Crystal Knight.png) - hand-packed; frames are located by the orange core
                         of the knight, which sits at a fixed spot in its body, and a
                         64x64 cell is placed at core + (-32, -17).
"""
import os

#Frame rectangles are literal, so this script needs no asset paths of its own.
OUT = 'out'
os.makedirs(OUT, exist_ok=True)

P1 = ('uid://cxy3x7ts2nsjb', 'res://Art/Boss/Phase1/Sword.png')
P2 = ('uid://csa3oak3i0rbx', 'res://Art/Boss/Phase2/Crystal Knight.png')
FX = (None, 'res://Art/Boss/BossEffects.png')


def grid(row, count, w=64, h=64, pitch=128):
    return [(c * pitch, row * 64, w, h) for c in range(count)]


#Rows 0-3 are all idle/walk variants - the sword only bobs and the body never moves,
#so none of them is an attack. Measured on the sheet: the body centroid shifts at most
#1.3px across those rows, and the weapon pixel count stays flat. The sheet's real
#attacks are row 4 (ground slam: a filled ellipse on frame 4 and a dome on frame 8,
#both centred on the character - an all-directions move) and row 5 (a forward lunge:
#a lance streak, then two sweep crescents - a one-direction move).
#
#Row 5 is root-motioned: the character walks ~66 art px across its own 128-wide cell.
#Packing it verbatim made the boss slide across the arena, which is why the dash was
#cut. It comes back here as "cleave" with the travel taken out of the pack instead of
#out of the script: every frame is cropped at its own travel offset, so the character
#lands on the usual (31, 50) anchor in all of them and only the slash moves.
#
#The travels are the offset of the frame's ground shadow (the one translucent
#colour on the sheet, 35/0/56 at alpha 57) from the shadow in the idle pose, measured
#off its LEFT edge - the sweep crescents are drawn over the right half of the shadow,
#so that edge is the only one visible in every frame.
#
#Column 2 is left out on purpose. It draws the lunge's motion trail, a dark bar 39
#art px BEHIND the character - which is right for someone who just travelled through
#it, and wrong for a boss standing still. The rest re-times into windup -> lance ->
#sweep -> recover, with the durations holding the two frames that connect.
CLEAVE_ROW = 5
#(source column, travel to cancel, frame duration)
CLEAVE = [(0, 0, 3.5), (1, 0, 2.0),
          (5, 64, 1.5), (6, 64, 1.0), (3, 68, 1.5)]

PHASE1 = [
    ('idle',   grid(0, 7),  8.0,  True),
    ('walk',   grid(1, 4),  8.0,  True),
    ('slam',   grid(4, 14), 10.0, False),
    ('cleave', [(c * 128 + t, CLEAVE_ROW * 64, 128, 64, d) for c, t, d in CLEAVE],
               10.0, False),
    ('hurt',   grid(6, 2),  10.0, False),
    ('death',  grid(7, 9),  10.0, False),
]

CELL = 64
IDLE2 = [(14, 7), (78, 7), (142, 7), (206, 7)]
ATK_L = [(14, 407), (79, 407), (159, 407), (221, 412), (285, 412)]
ATK_R = [(14, 487), (78, 487), (157, 487), (224, 487), (304, 487)]
CAST = [(14, 567), (94, 567), (206, 566)]

PHASE2 = [
    ('idle',     [(x, y, CELL, CELL) for x, y in IDLE2], 6.0, True),
    ('attack_l', [(x, y, CELL, CELL) for x, y in ATK_L], 11.0, False),
    ('attack_r', [(x, y, CELL, CELL) for x, y in ATK_R], 11.0, False),
    ('cast',     [(x, y, CELL, CELL) for x, y in CAST], 4.0, False),
    ('spawn',    [(x, y, CELL, CELL) for x, y in reversed(CAST)], 4.0, False),
    ('death',    [(x, y, CELL, CELL) for x, y in CAST], 3.0, False),
]

FXA = [
    ('lightning', [(0, 0, 48, 64), (48, 0, 48, 64), (96, 0, 48, 64)], 11.0, False),
    ('spark',     [(i * 48, 64, 48, 64) for i in range(5)], 16.0, False),
    ('star',      [(0, 128, 48, 64), (48, 128, 48, 64)], 14.0, True),
    ('impact',    [(96, 128, 48, 64), (96, 64, 48, 64), (144, 64, 48, 64),
                   (192, 64, 48, 64)], 16.0, False),
    ('orb',       [(144, 128, 48, 64)], 6.0, True),
]


def write(path, tex, anims):
    uid, res = tex
    lines = ['[gd_resource type="SpriteFrames" format=3]', '']
    if uid:
        lines.append('[ext_resource type="Texture2D" uid="%s" path="%s" id="1_tex"]' % (uid, res))
    else:
        lines.append('[ext_resource type="Texture2D" path="%s" id="1_tex"]' % res)
    lines.append('')
    idx = 0
    body = []
    for name, rects, speed, loop in anims:
        frames = []
        for rect in rects:
            x, y, w, h = rect[:4]
            #a 5th element holds a per-frame duration, in frame units
            duration = rect[4] if len(rect) > 4 else 1.0
            rid = 'A%d' % idx
            idx += 1
            lines += ['[sub_resource type="AtlasTexture" id="%s"]' % rid,
                      'atlas = ExtResource("1_tex")',
                      'region = Rect2(%d, %d, %d, %d)' % (x, y, w, h), '']
            frames.append('{\n"duration": %.1f,\n"texture": SubResource("%s")\n}'
                          % (duration, rid))
        body.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %.1f\n}'
                    % (', '.join(frames), 'true' if loop else 'false', name, speed))
    lines += ['[resource]', 'animations = [%s]' % ', '.join(body), '']
    open(os.path.join(OUT, path), 'w', encoding='utf-8').write('\n'.join(lines))
    print('wrote', path, len(anims), 'animations')


write('BossPhase1Frames.tres', P1, PHASE1)
write('BossPhase2Frames.tres', P2, PHASE2)
write('BossFxFrames.tres', FX, FXA)
