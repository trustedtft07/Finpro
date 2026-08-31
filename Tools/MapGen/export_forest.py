"""Write the Green Forest TileSet resource and scene.

NOTE: the shipped scene's props are TileMapLayer tiles, not the Sprite2D nodes this
writes - see "Props: tiles and collision" in README.md. Re-exporting replaces them
with sprites again; the conversion has to be re-applied after.
"""
import base64
import random
import struct

import ftiles as F
import forest_gen as G
from undead_gen import MAP_W, MAP_H

OUT = 'out'
TS_PATH = OUT + '/GreenForestTileSet.tres'
SCENE_PATH = OUT + '/GreenForest.tscn'

TILES_UID = 'uid://bl5m6mtwv4avt'
TILES_RES = 'res://Art/Forest/Tiles/Tileset.png'
DECOR_UID = 'uid://cbyikfg87elqy'
DECOR_RES = 'res://Art/Forest/Decorations/Decorations.png'
SCENE_UID = 'uid://dtdywhmx3qhs2'

SRC_TILES, SRC_DECOR = 0, 1
FULL_SQUARE = 'PackedVector2Array(-8, -8, 8, -8, 8, 8, -8, 8)'

# Collision outlines for the rock rim, taken verbatim from the hand-authored
# ForestTileSet.tres so the walls feel exactly as they were tuned to.
ROCK_POLY = {
    (3, 3): '8, 3.7770348, 8, 8, 2.877739, 8, 3.4173164, 4.3166103',
    (4, 3): '8, 1.978447, 8, 8, -8, 8, -8, 1.7985878',
    (5, 3): '-3.7770338, 4.136751, -2.3381634, 8, -8, 8, -8, 3.057598',
    (6, 3): '8, -8, 8, 8, -8, 8, -8, 4.136751, -0.71943474, 0.5395775, 1.6187286, -8',
    (7, 3): '-8, -8, -0.71943474, -5.755479, 2.6978817, 1.2590122, 8, 4.6763268, 8, 8, -8, 8',
    (3, 4): '8, -8, 8, 8, -2.1583042, 8, -2.6978817, -8',
    (5, 4): '2.1583042, -8, 1.7985878, 8, -8, 8, -8, -8',
    (6, 4): '8, -8, 8, 8, -8, 8, -8, -8',
    (7, 4): '-8, -8, 8, -8, 8, 8, -8, 8',
    (3, 5): '8, -8, 8, 8, -0.17985916, 0.5395775, -2.6978817, -8',
    (4, 5): '8, -8, 8, 8, -8, 8, -8, -8',
    (5, 5): '2.1583042, -8, 0.5395756, -0.17985725, -8, 5.3957634, -8, -8',
}
# the dirt-topped rim is the same art three rows further down
for (c, r), poly in list(ROCK_POLY.items()):
    ROCK_POLY[(c, r + 3)] = poly

WATER_SOLID = set(F.WATER.values()) | set(F.WATER_FILL) | set(F.LILY) | set(F.WATER_ISLAND.values())
WATER_SOLID.discard(F.WATER_ISLAND['C'])


def encode_layer(cells):
    buf = bytearray(struct.pack('<H', 0))
    for (x, y) in sorted(cells):
        t = cells[(x, y)]
        if t[0] == 'decor':
            src, c, r = SRC_DECOR, t[1], t[2]
        else:
            src, c, r = SRC_TILES, t[0], t[1]
        buf += struct.pack('<hhHhhH', x, y, src, c, r, 0)
    return base64.b64encode(bytes(buf)).decode()


def write_tileset(used_tiles, decor_kinds):
    L = ['[gd_resource type="TileSet" format=3]', '',
         '[ext_resource type="Texture2D" uid="%s" path="%s" id="0_tiles"]' % (TILES_UID, TILES_RES),
         '[ext_resource type="Texture2D" uid="%s" path="%s" id="1_decor"]' % (DECOR_UID, DECOR_RES),
         '',
         '[sub_resource type="TileSetAtlasSource" id="Atlas_tiles"]',
         'texture = ExtResource("0_tiles")',
         'texture_region_size = Vector2i(16, 16)']
    for (c, r) in sorted(used_tiles):
        L.append('%d:%d/0 = 0' % (c, r))
        poly = None
        if (c, r) in ROCK_POLY:
            poly = ROCK_POLY[(c, r)]
        elif (c, r) in WATER_SOLID or (c, r) == G.COLLIDER:
            poly = FULL_SQUARE[len('PackedVector2Array('):-1]
        if poly:
            L.append('%d:%d/0/physics_layer_0/polygon_0/points = PackedVector2Array(%s)'
                     % (c, r, poly))
    L += ['', '[sub_resource type="TileSetAtlasSource" id="Atlas_decor"]',
          'texture = ExtResource("1_decor")',
          'texture_region_size = Vector2i(16, 16)']
    for (c, r, tw, th) in sorted(decor_kinds):
        if (tw, th) != (1, 1):
            L.append('%d:%d/size_in_atlas = Vector2i(%d, %d)' % (c, r, tw, th))
        L.append('%d:%d/0 = 0' % (c, r))
    L += ['', '[resource]', 'physics_layer_0/collision_layer = 1',
          'sources/0 = SubResource("Atlas_tiles")',
          'sources/1 = SubResource("Atlas_decor")', '']
    open(TS_PATH, 'w', encoding='utf-8').write('\n'.join(L))
    print('wrote', TS_PATH)


LAYER_NODES = [
    ('DirtDetail', 'dirtdetail', -14),
    ('Grass', 'grass', -13),
    ('GrassDark', 'dark', -12),
    ('Water', 'water', -11),
    ('Rocks', 'rocks', -10),
    ('Decor', 'decor', -9),
    ('Collision', 'collision', -8),
]

EXT = [
    ('TileSet', None, 'res://Art/Forest/GreenForestTileSet.tres', '1_ts'),
    ('Texture2D', DECOR_UID, DECOR_RES, '2_decor'),
    ('PackedScene', 'uid://bvg5dny32iw0x', 'res://Scenes/Player/Player.tscn', '3_player'),
    ('PackedScene', 'uid://b4l1gom0wsk8p', 'res://Scenes/Interactables/area_exit.tscn', '4_exit'),
    ('PackedScene', 'uid://dei3j88yw6omf', 'res://Scenes/Levels/MainFloor.tscn', '5_main'),
    ('PackedScene', 'uid://c8qy3n0m4tqxk', 'res://Scenes/Interactables/Bonfire.tscn', '6_bonfire'),
    ('PackedScene', 'uid://bvt7e871e6jeg', "res://Scenes/NPC's/Enemy/Enemy.tscn", '7_enemy'),
    ('PackedScene', 'uid://bblpsy4fvi76f', 'res://Scenes/Interactables/Coin.tscn', '8_coin'),
    ('Script', None, 'res://Scripts/LevelCameraBounds.gd', '9_cam'),
]


def write_scene(layers, sprites, spawn, enemies, coins):
    rng = random.Random(5)
    out = ['[gd_scene format=4 uid="%s"]' % SCENE_UID, '']
    for typ, uid, path, ident in EXT:
        if uid:
            out.append('[ext_resource type="%s" uid="%s" path="%s" id="%s"]'
                       % (typ, uid, path, ident))
        else:
            out.append('[ext_resource type="%s" path="%s" id="%s"]' % (typ, path, ident))
    out += ['', '[sub_resource type="Environment" id="Env"]',
            'background_mode = 3',
            'glow_enabled = true',
            'glow_normalized = true',
            'glow_intensity = 0.85',
            'glow_bloom = 0.25',
            'adjustment_enabled = true',
            'adjustment_saturation = 1.04',
            '']

    kinds = {}
    for sp in sprites:
        s = sp['s']
        k = (s['px'], s['py'], s['pw'], s['ph'])
        if k in kinds:
            continue
        kinds[k] = 'At%d' % len(kinds)
        out += ['[sub_resource type="AtlasTexture" id="%s"]' % kinds[k],
                'atlas = ExtResource("2_decor")',
                'region = Rect2(%d, %d, %d, %d)' % k, '']

    W, H = MAP_W * 16, MAP_H * 16
    out += ['[node name="GreenForest_Root" type="Node2D"]',
            'y_sort_enabled = true',
            'texture_filter = 1',
            'script = ExtResource("9_cam")',
            'map_size = Vector2i(%d, %d)' % (W, H),
            '',
            '[node name="WorldEnvironment" type="WorldEnvironment" parent="."]',
            'environment = SubResource("Env")',
            '',
            '[node name="Backdrop" type="Polygon2D" parent="."]',
            'z_index = -20',
            'color = Color(%.5f, %.5f, %.5f, 1)' % tuple(v / 255.0 for v in G.DIRT_RGB),
            'polygon = PackedVector2Array(0, 0, %d, 0, %d, %d, 0, %d)' % (W, W, H, H),
            '']
    for node, key, z in LAYER_NODES:
        cells = layers.get(key, {})
        if not cells:
            continue
        out += ['[node name="%s" type="TileMapLayer" parent="."]' % node,
                'z_index = %d' % z,
                'tile_map_data = PackedByteArray("%s")' % encode_layer(cells),
                'tile_set = ExtResource("1_ts")', '']

    out += ['[node name="Props" type="Node2D" parent="."]', 'y_sort_enabled = true', '']
    for i, sp in enumerate(sprites):
        s = sp['s']
        k = (s['px'], s['py'], s['pw'], s['ph'])
        px = sp['x'] * 16 + sp['tw'] * 8
        py = (sp['y'] + sp['th']) * 16
        out += ['[node name="P%d" type="Sprite2D" parent="Props"]' % i,
                'position = Vector2(%d, %d)' % (px, py),
                'texture = SubResource("%s")' % kinds[k],
                'offset = Vector2(0, %d)' % (-s['ph'] // 2)]
        if sp['fh']:
            out.append('flip_h = true')
        out.append('')

    sx, sy = spawn
    px, py = sx * 16 + 8, sy * 16 + 8
    out += ['[node name="Bonfire" parent="." instance=ExtResource("6_bonfire")]',
            'position = Vector2(%d, %d)' % (px, py - 48), '',
            '[node name="ReturnExit" parent="." instance=ExtResource("4_exit")]',
            'position = Vector2(%d, %d)' % (px - 72, py),
            'next_scene = ExtResource("5_main")', '',
            '[node name="Enemies" type="Node" parent="."]', '']
    for i, (ex, ey) in enumerate(enemies):
        out += ['[node name="Enemy%d" parent="Enemies" instance=ExtResource("7_enemy")]' % i,
                'position = Vector2(%d, %d)' % (ex * 16 + 8, ey * 16 + 8), '']
    out += ['[node name="Pickups" type="Node" parent="."]', '']
    for i, (cx, cy) in enumerate(coins):
        out += ['[node name="Coin%d" parent="Pickups" instance=ExtResource("8_coin")]' % i,
                'position = Vector2(%d, %d)' % (cx * 16 + 8, cy * 16 + 8),
                'amplitude = 12.0', '']
    out += ['[node name="Player" parent="." instance=ExtResource("3_player")]',
            'top_level = false',
            'position = Vector2(%d, %d)' % (px, py), '']

    text = '\n'.join(out)
    open(SCENE_PATH, 'w', encoding='utf-8').write(text)
    print('wrote', SCENE_PATH, '%.1f KB' % (len(text) / 1024))
