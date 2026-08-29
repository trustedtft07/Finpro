"""Decode Godot .tscn TileMapLayer data and AtlasTexture sprites."""
import base64
import re
import struct


def parse_scene(path):
    text = open(path, encoding='utf-8').read()
    blocks = re.split(r'\n(?=\[)', text)
    nodes = []
    subres = {}
    cur = None
    for b in blocks:
        head = b.split('\n', 1)[0]
        m = re.match(r'\[node name="([^"]+)" type="([^"]*)"?', head)
        if m:
            cur = dict(name=m.group(1), type=m.group(2), body=b)
            nodes.append(cur)
            continue
        m = re.match(r'\[node name="([^"]+)" parent="([^"]*)"', head)
        if m:
            cur = dict(name=m.group(1), type='instance', body=b)
            nodes.append(cur)
            continue
        m = re.match(r'\[sub_resource type="([^"]+)" id="([^"]+)"\]', head)
        if m:
            subres[m.group(2)] = dict(type=m.group(1), body=b)
    return nodes, subres


def decode_tile_map_data(body):
    m = re.search(r'tile_map_data = PackedByteArray\("([^"]*)"\)', body)
    if not m:
        return None
    d = base64.b64decode(m.group(1))
    cells = {}
    off = 2
    n = (len(d) - off) // 12
    for i in range(n):
        x, y, src, ax, ay, alt = struct.unpack_from('<hhHhhH', d, off + i * 12)
        cells[(x, y)] = (src, ax, ay, alt)
    return cells


def prop(body, name):
    m = re.search(r'^%s = (.+)$' % re.escape(name), body, re.M)
    return m.group(1) if m else None
