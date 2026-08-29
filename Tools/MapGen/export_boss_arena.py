"""Write BossPlace.tscn and re-emit the shared Undead Forest tileset."""
import random

import build_boss_arena as A
import export_godot as EG
from undead_gen import GR, OB

MAP_W, MAP_H = A.MAP_W, A.MAP_H
OUT = 'out'

LAYER_NODES = [
    ('GroundDark', 'grounddark', -9),
    ('Mounds', 'mound', -8),
    ('Ridge', 'ridge', -6),
    ('Details', 'details', -5),
    ('ObjectsLow', 'objlow', -4),
    ('Collision', 'collision', -3),
]

EXT = [
    ('TileSet', None, 'res://Art/UndeadForest/UndeadForestTileSet.tres', '1_ts'),
    ('Texture2D', EG.TEX[OB][0], EG.TEX[OB][1], '2_obj'),
    ('PackedScene', 'uid://bvg5dny32iw0x', 'res://Scenes/Player/Player.tscn', '3_player'),
    ('PackedScene', 'uid://b4l1gom0wsk8p', 'res://Scenes/Interactables/area_exit.tscn', '4_exit'),
    #Back to the hub, not to UndeadForest: that scene holds the gate INTO this one,
    #and two scenes referencing each other is a cyclic resource Godot cannot load.
    ('PackedScene', 'uid://dei3j88yw6omf', 'res://Scenes/Levels/MainFloor.tscn', '5_back'),
    ('PackedScene', 'uid://c8qy3n0m4tqxk', 'res://Scenes/Interactables/Bonfire.tscn', '6_bonfire'),
    ('PackedScene', None, 'res://Scenes/Boss/Boss.tscn', '7_boss'),
    ('Script', None, 'res://Scripts/LevelCameraBounds.gd', '8_cam'),
]


def frame_entry(fid):
    return '{\n"duration": 1.0,\n"texture": SubResource("%s")\n}' % fid


def write_scene(layers, sprites, anims, spawn, boss_cell):
    rng = random.Random(3)
    out = ['[gd_scene format=4]', '']
    sheets = sorted({s['sheet'] for s in anims})
    for typ, uid, path, ident in EXT:
        if uid:
            out.append('[ext_resource type="%s" uid="%s" path="%s" id="%s"]'
                       % (typ, uid, path, ident))
        else:
            out.append('[ext_resource type="%s" path="%s" id="%s"]' % (typ, path, ident))
    for sh in sheets:
        uid, path = EG.ANIM_TEX[sh]
        out.append('[ext_resource type="Texture2D" uid="%s" path="%s" id="9_%s"]'
                   % (uid, path, sh))
    out.append('')

    out += ['[sub_resource type="Environment" id="Env"]',
            'background_mode = 3', 'glow_enabled = true', 'glow_normalized = true',
            'glow_intensity = 1.25', 'glow_bloom = 0.5',
            'adjustment_enabled = true', 'adjustment_saturation = 0.9', '']

    kinds = {}
    for s in sprites:
        k = (s['col'], s['row'], s['w'], s['h'])
        if k in kinds:
            continue
        kinds[k] = 'At%d' % len(kinds)
        out += ['[sub_resource type="AtlasTexture" id="%s"]' % kinds[k],
                'atlas = ExtResource("2_obj")',
                'region = Rect2(%d, %d, %d, %d)'
                % (s['col'] * 16, s['row'] * 16, s['w'] * 16, s['h'] * 16), '']

    anim_kinds = {}
    for s in anims:
        k = (s['sheet'], s['col'], s['row'], s['w'], s['h'])
        if k in anim_kinds:
            continue
        idx = len(anim_kinds)
        anim_kinds[k] = 'SF%d' % idx
        frames = []
        for f in range(6):
            fid = 'AF%d_%d' % (idx, f)
            out += ['[sub_resource type="AtlasTexture" id="%s"]' % fid,
                    'atlas = ExtResource("9_%s")' % s['sheet'],
                    'region = Rect2(%d, %d, %d, %d)'
                    % ((s['col'] + EG.ANIM_FRAME_STRIDE * f) * 16, s['row'] * 16,
                       s['w'] * 16, s['h'] * 16), '']
            frames.append(frame_entry(fid))
        out += ['[sub_resource type="SpriteFrames" id="%s"]' % anim_kinds[k],
                'animations = [{', '"frames": [%s],' % ', '.join(frames),
                '"loop": true,', '"name": &"default",',
                '"speed": %.4f' % (1000.0 / EG.FRAME_MS), '}]', '']

    W, H = MAP_W * 16, MAP_H * 16
    out += ['[node name="BossPlace_Root" type="Node2D"]',
            'y_sort_enabled = true', 'texture_filter = 1',
            'script = ExtResource("8_cam")',
            'map_size = Vector2i(%d, %d)' % (W, H), '',
            '[node name="WorldEnvironment" type="WorldEnvironment" parent="."]',
            'environment = SubResource("Env")', '',
            '[node name="CanvasModulate" type="CanvasModulate" parent="."]',
            'color = Color(0.72, 0.75, 0.84, 1)', '',
            '[node name="Backdrop" type="Polygon2D" parent="."]',
            'z_index = -20', 'color = Color(0.43529, 0.45098, 0.41569, 1)',
            'polygon = PackedVector2Array(0, 0, %d, 0, %d, %d, 0, %d)' % (W, W, H, H), '']

    for node, key, z in LAYER_NODES:
        cells = layers.get(key, {})
        if not cells:
            continue
        out += ['[node name="%s" type="TileMapLayer" parent="."]' % node,
                'z_index = %d' % z,
                'tile_map_data = PackedByteArray("%s")' % EG.encode_layer(cells),
                'tile_set = ExtResource("1_ts")', '']

    out += ['[node name="Props" type="Node2D" parent="."]', 'y_sort_enabled = true', '']
    for i, s in enumerate(sprites):
        k = (s['col'], s['row'], s['w'], s['h'])
        out += ['[node name="P%d" type="Sprite2D" parent="Props"]' % i,
                'position = Vector2(%d, %d)' % (s['x'] * 16 + s['w'] * 8, (s['y'] + s['h']) * 16),
                'texture = SubResource("%s")' % kinds[k],
                'offset = Vector2(0, %d)' % (-s['h'] * 8)]
        if s['fh']:
            out.append('flip_h = true')
        out.append('')
    for i, s in enumerate(anims):
        k = (s['sheet'], s['col'], s['row'], s['w'], s['h'])
        out += ['[node name="A%d" type="AnimatedSprite2D" parent="Props"]' % i,
                'position = Vector2(%d, %d)' % (s['x'] * 16 + s['w'] * 8, (s['y'] + s['h']) * 16),
                'sprite_frames = SubResource("%s")' % anim_kinds[k],
                'autoplay = "default"', 'frame = %d' % rng.randrange(6),
                'speed_scale = %.2f' % rng.uniform(0.8, 1.15),
                'offset = Vector2(0, %d)' % (-s['h'] * 8), '']

    sx, sy = spawn
    px, py = sx * 16 + 8, sy * 16 + 8
    bx, by = boss_cell[0] * 16 + 8, boss_cell[1] * 16 + 8
    out += ['[node name="Boss" parent="." instance=ExtResource("7_boss")]',
            'position = Vector2(%d, %d)' % (bx, by), '',
            '[node name="Bonfire" parent="." instance=ExtResource("6_bonfire")]',
            'position = Vector2(%d, %d)' % (px - 64, py + 4), '',
            '[node name="ReturnExit" parent="." instance=ExtResource("4_exit")]',
            'position = Vector2(%d, %d)' % (px + 56, py + 4),
            'next_scene = ExtResource("5_back")', '',
            '[node name="Player" parent="." instance=ExtResource("3_player")]',
            'top_level = false',
            'position = Vector2(%d, %d)' % (px, py), '']

    text = '\n'.join(out)
    open(OUT + '/BossPlace.tscn', 'w', encoding='utf-8').write(text)
    print('wrote BossPlace.tscn  %.1f KB' % (len(text) / 1024))


def main():
    m = A.build()
    layers = A.paint(m)
    rng = random.Random(77)
    spawn = (MAP_W // 2, MAP_H - A.WALL - 6)
    spawn_clear = {(spawn[0] + dx, spawn[1] + dy)
                   for dx in range(-8, 9) for dy in range(-5, 5)}
    sprites, anims = A.decorate(m, layers, rng, spawn_clear)

    used = A.existing_undead_tiles()
    for cells in layers.values():
        for t in cells.values():
            used.setdefault(t[0], set()).add((t[1], t[2]))
    used.setdefault(GR, set()).add(EG.COLLIDER_CR)
    print('tileset union:', {k: len(v) for k, v in used.items()})
    EG.write_tileset(used)

    write_scene(layers, sprites, anims, spawn, A.CENTRE)
    print('arena %dx%d tiles (%dx%d px), walkable %d cells'
          % (MAP_W, MAP_H, MAP_W * 16, MAP_H * 16, len(m['walk'])))
    return m, layers, sprites, anims, spawn


if __name__ == '__main__':
    main()
