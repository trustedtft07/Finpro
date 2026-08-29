"""Write the Godot TileSet resource and the UndeadForest scene."""
import base64
import struct
import random
from collections import defaultdict

import tmxlib as T
from undead_gen import MAP_W, MAP_H, GR, WC, WD, OB, DT

OUT = "out"
TS_PATH = OUT + "/UndeadForestTileSet.tres"
SCENE_PATH = OUT + "/UndeadForest.tscn"

TEX = {
    GR: ('uid://b8kv7l47emvv4', 'res://Art/UndeadForest/Tiled_files/Ground_rocks.png'),
    WC: ('uid://1rttfb0k5u3k', 'res://Art/UndeadForest/Tiled_files/water_coasts.png'),
    WD: ('uid://e8086dm7mvl3', 'res://Art/UndeadForest/Tiled_files/water_detilazation.png'),
    OB: ('uid://dlsknijysom2e', 'res://Art/UndeadForest/Tiled_files/Objects.png'),
    DT: ('uid://b5ptdqnw2twwb', 'res://Art/UndeadForest/Tiled_files/details.png'),
}
ANIM_TEX = {
    'anim1': ('uid://dqb16ybpv2n60', 'res://Art/UndeadForest/Tiled_files/Objects_animated.png'),
    'anim2': ('uid://ca0m1pss3rgxt', 'res://Art/UndeadForest/Tiled_files/Objects_animated2.png'),
    'anim3': ('uid://bd0elyxea57dm', 'res://Art/UndeadForest/Tiled_files/Objects_animated3.png'),
}
SRC_ID = {GR: 0, WC: 1, WD: 2, OB: 3, DT: 4}
TS_NAME = {GR: 'Ground_rocks', WC: 'water_coasts', WD: 'Water_detilazation',
           OB: 'Objects', DT: 'details'}

FLIP_H = 1 << 12
FRAME_MS = 150.0
ANIM_FRAME_STRIDE = 7        # Objects_animated: frames sit 7 columns apart


# ------------------------------------------------------------ tile_map_data
def encode_layer(cells):
    """cells: {(x,y): (src, col, row, fh?)} -> base64 PackedByteArray body."""
    buf = bytearray(struct.pack('<H', 0))
    for (x, y) in sorted(cells):
        t = cells[(x, y)]
        src, c, r = SRC_ID[t[0]], t[1], t[2]
        alt = FLIP_H if (len(t) > 3 and t[3]) else 0
        buf += struct.pack('<hhHhhH', x, y, src, c, r, alt)
    return base64.b64encode(bytes(buf)).decode()


# ------------------------------------------------------------------ tileset
def _anims_for(srckey):
    ts = {t['name']: t for t in T.TILESETS}[TS_NAME[srckey]]
    cols = ts['columns']
    out = {}
    for tid, frames in ts['anims'].items():
        c, r = tid % cols, tid // cols
        rows = [f[0] // cols for f in frames]
        cs = {f[0] % cols for f in frames}
        if len(cs) != 1 or len(rows) < 2:
            continue
        stride = rows[1] - rows[0]
        if any(rows[i + 1] - rows[i] != stride for i in range(len(rows) - 1)):
            continue
        out[(c, r)] = (len(frames), stride)
    return out


def write_tileset(used):
    """used: {srckey: set of (col,row)}  plus the collider tile."""
    lines = ['[gd_resource type="TileSet" format=3]', '']
    for k in sorted(used, key=lambda s: SRC_ID[s]):
        uid, path = TEX[k]
        lines.append('[ext_resource type="Texture2D" uid="%s" path="%s" id="%d_tex"]'
                     % (uid, path, SRC_ID[k]))
    lines.append('')

    for k in sorted(used, key=lambda s: SRC_ID[s]):
        anims = _anims_for(k) if k in (WC, WD) else {}
        lines.append('[sub_resource type="TileSetAtlasSource" id="Atlas_%d"]' % SRC_ID[k])
        lines.append('texture = ExtResource("%d_tex")' % SRC_ID[k])
        lines.append('texture_region_size = Vector2i(16, 16)')
        for (c, r) in sorted(used[k]):
            if (c, r) in anims:
                n, stride = anims[(c, r)]
                lines.append('%d:%d/animation_columns = 1' % (c, r))
                lines.append('%d:%d/animation_separation = Vector2i(0, %d)' % (c, r, stride - 1))
                lines.append('%d:%d/animation_speed = %.4f' % (c, r, 1000.0 / FRAME_MS))
                lines.append('%d:%d/animation_frames_count = %d' % (c, r, n))
                for i in range(n):
                    lines.append('%d:%d/animation_frame_%d/duration = 1.0' % (c, r, i))
            lines.append('%d:%d/0 = 0' % (c, r))
            if k == GR and (c, r) == COLLIDER_CR:
                lines.append('%d:%d/0/physics_layer_0/polygon_0/points = '
                             'PackedVector2Array(-8, -8, 8, -8, 8, 8, -8, 8)' % (c, r))
        lines.append('')

    lines.append('[resource]')
    lines.append('physics_layer_0/collision_layer = 1')
    for k in sorted(used, key=lambda s: SRC_ID[s]):
        lines.append('sources/%d = SubResource("Atlas_%d")' % (SRC_ID[k], SRC_ID[k]))
    lines.append('')
    open(TS_PATH, 'w', encoding='utf-8').write('\n'.join(lines))
    print('wrote', TS_PATH)


COLLIDER_CR = (0, 59)
