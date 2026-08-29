"""Write the UndeadForest Godot scene."""
import random

from undead_gen import MAP_W, MAP_H, GR, WC, WD, OB, DT
from export_godot import TEX, ANIM_TEX, SCENE_PATH, encode_layer, FRAME_MS, ANIM_FRAME_STRIDE

LAYER_NODES = [
    ('Water', 'water', -12),
    ('WaterDetail', 'waterdetail', -11),
    ('Ground', 'ground', -10),
    ('GroundDark', 'grounddark', -9),
    ('Mounds', 'mound', -8),
    ('Rubble', 'rubble', -7),
    ('Ridge', 'ridge', -6),
    ('Details', 'details', -5),
    ('ObjectsLow', 'objlow', -4),
    ('Collision', 'collision', -3),
]

EXT = [
    ('TileSet', None, 'res://Art/UndeadForest/UndeadForestTileSet.tres', '1_ts'),
    ('Texture2D', TEX[OB][0], TEX[OB][1], '2_obj'),
    ('PackedScene', 'uid://bvg5dny32iw0x', 'res://Scenes/Player/Player.tscn', '3_player'),
    ('PackedScene', 'uid://b4l1gom0wsk8p', 'res://Scenes/Interactables/area_exit.tscn', '4_exit'),
    ('PackedScene', 'uid://dei3j88yw6omf', 'res://Scenes/Levels/MainFloor.tscn', '5_main'),
    ('PackedScene', 'uid://c8qy3n0m4tqxk', 'res://Scenes/Interactables/Bonfire.tscn', '6_bonfire'),
    ('PackedScene', 'uid://bvt7e871e6jeg', "res://Scenes/NPC's/Enemy/Enemy.tscn", '7_enemy'),
    ('PackedScene', 'uid://bblpsy4fvi76f', 'res://Scenes/Interactables/Coin.tscn', '8_coin'),
    ('Script', None, 'res://Scripts/UndeadForestLevel.gd', '10_level'),
]


def write_scene(layers, sprites, anims, spawn, enemies, coins):
    rng = random.Random(99)
    out = ['[gd_scene format=4]', '']
    used_sheets = sorted({s['sheet'] for s in anims})
    for typ, uid, path, ident in EXT:
        if uid:
            out.append('[ext_resource type="%s" uid="%s" path="%s" id="%s"]'
                       % (typ, uid, path, ident))
        else:
            out.append('[ext_resource type="%s" path="%s" id="%s"]' % (typ, path, ident))
    for sh in used_sheets:
        uid, path = ANIM_TEX[sh]
        out.append('[ext_resource type="Texture2D" uid="%s" path="%s" id="9_%s"]'
                   % (uid, path, sh))
    out.append('')

    out += ['[sub_resource type="Environment" id="Env"]',
            'background_mode = 3',
            'glow_enabled = true',
            'glow_normalized = true',
            'glow_intensity = 1.1',
            'glow_bloom = 0.45',
            'adjustment_enabled = true',
            'adjustment_saturation = 0.92',
            '']

    kinds = {}
    for s in sprites:
        k = (s['col'], s['row'], s['w'], s['h'])
        if k in kinds:
            continue
        kinds[k] = 'At%d' % len(kinds)
        out += ['[sub_resource type="AtlasTexture" id="%s"]' % kinds[k],
                'atlas = ExtResource("2_obj")',
                'region = Rect2(%d, %d, %d, %d)' % (s['col'] * 16, s['row'] * 16,
                                                    s['w'] * 16, s['h'] * 16),
                '']

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
                    % ((s['col'] + ANIM_FRAME_STRIDE * f) * 16, s['row'] * 16,
                       s['w'] * 16, s['h'] * 16),
                    '']
            frames.append('{\n"duration": 1.0,\n"texture": SubResource("%s")\n}' % fid)
        out += ['[sub_resource type="SpriteFrames" id="%s"]' % anim_kinds[k],
                'animations = [{',
                '"frames": [%s],' % ', '.join(frames),
                '"loop": true,',
                '"name": &"default",',
                '"speed": %.4f' % (1000.0 / FRAME_MS),
                '}]',
                '']

    W, H = MAP_W * 16, MAP_H * 16
    out += ['[node name="UndeadForest_Root" type="Node2D"]',
            'y_sort_enabled = true',
            'texture_filter = 1',
            'script = ExtResource("10_level")',
            'map_size = Vector2i(%d, %d)' % (W, H),
            '',
            '[node name="WorldEnvironment" type="WorldEnvironment" parent="."]',
            'environment = SubResource("Env")',
            '',
            '[node name="CanvasModulate" type="CanvasModulate" parent="."]',
            'color = Color(0.76, 0.79, 0.85, 1)',
            '',
            '[node name="Backdrop" type="Polygon2D" parent="."]',
            'z_index = -20',
            'color = Color(0.43529, 0.45098, 0.41569, 1)',
            'polygon = PackedVector2Array(0, 0, %d, 0, %d, %d, 0, %d)' % (W, W, H, H),
            '']

    for node, key, z in LAYER_NODES:
        cells = layers.get(key, {})
        if not cells:
            continue
        out += ['[node name="%s" type="TileMapLayer" parent="."]' % node,
                'z_index = %d' % z,
                'tile_map_data = PackedByteArray("%s")' % encode_layer(cells),
                'tile_set = ExtResource("1_ts")',
                '']

    out += ['[node name="Props" type="Node2D" parent="."]', 'y_sort_enabled = true', '']
    for i, s in enumerate(sprites):
        k = (s['col'], s['row'], s['w'], s['h'])
        px = s['x'] * 16 + s['w'] * 8
        py = (s['y'] + s['h']) * 16
        out += ['[node name="P%d" type="Sprite2D" parent="Props"]' % i,
                'position = Vector2(%d, %d)' % (px, py),
                'texture = SubResource("%s")' % kinds[k],
                'offset = Vector2(0, %d)' % (-s['h'] * 8)]
        if s['fh']:
            out.append('flip_h = true')
        out.append('')
    for i, s in enumerate(anims):
        k = (s['sheet'], s['col'], s['row'], s['w'], s['h'])
        px = s['x'] * 16 + s['w'] * 8
        py = (s['y'] + s['h']) * 16
        out += ['[node name="A%d" type="AnimatedSprite2D" parent="Props"]' % i,
                'position = Vector2(%d, %d)' % (px, py),
                'sprite_frames = SubResource("%s")' % anim_kinds[k],
                'autoplay = "default"',
                'frame = %d' % rng.randrange(6),
                'speed_scale = %.2f' % rng.uniform(0.8, 1.15),
                'offset = Vector2(0, %d)' % (-s['h'] * 8),
                '']

    sx, sy = spawn
    px, py = sx * 16 + 8, sy * 16 + 8
    out += ['[node name="Bonfire" parent="." instance=ExtResource("6_bonfire")]',
            'position = Vector2(%d, %d)' % (px, py - 48),
            '',
            '[node name="ReturnExit" parent="." instance=ExtResource("4_exit")]',
            'position = Vector2(%d, %d)' % (px - 72, py),
            'next_scene = ExtResource("5_main")',
            '',
            '[node name="Enemies" type="Node" parent="."]', '']
    for i, (ex, ey) in enumerate(enemies):
        out += ['[node name="Enemy%d" parent="Enemies" instance=ExtResource("7_enemy")]' % i,
                'position = Vector2(%d, %d)' % (ex * 16 + 8, ey * 16 + 8), '']
    out += ['[node name="Pickups" type="Node" parent="."]', '']
    for i, (cx, cy) in enumerate(coins):
        out += ['[node name="Coin%d" parent="Pickups" instance=ExtResource("8_coin")]' % i,
                'position = Vector2(%d, %d)' % (cx * 16 + 8, cy * 16 + 8),
                'amplitude = 12.0', '']
    # Player.tscn sets top_level, which pulls it out of the root's Y-sort and makes it
    # draw over every prop. This level wants it sorted with the scenery.
    out += ['[node name="Player" parent="." instance=ExtResource("3_player")]',
            'top_level = false',
            'position = Vector2(%d, %d)' % (px, py), '']

    text = '\n'.join(out)
    open(SCENE_PATH, 'w', encoding='utf-8').write(text)
    print('wrote', SCENE_PATH, '%.1f KB' % (len(text) / 1024))
