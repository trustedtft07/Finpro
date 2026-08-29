# Map generators

Offline Python tooling (not part of the game build) that produced the two large
outdoor levels from their raw asset packs. Nothing here runs at game time.

| Level | Scene | TileSet | Entry point |
| --- | --- | --- | --- |
| Undead Forest | `Scenes/Levels/UndeadForest.tscn` | `Art/UndeadForest/UndeadForestTileSet.tres` | `python export_all.py` |
| Green Forest | `Scenes/Levels/GreenForest.tscn` | `Art/Forest/GreenForestTileSet.tres` | `python export_forest.py` via `run_forest.py` |
| Boss arena | `Scenes/Levels/BossPlace.tscn` | shares the Undead Forest tileset | `python export_boss_arena.py` |

Both need Python 3 with Pillow and numpy, and both write into `out/`; copy the two
files from there over the ones in `Scenes/Levels/` and the art folder. Each map is
deterministic - same seed in, same map out.

## Undead Forest

Learns its tile vocabulary from the asset pack's own sample map
(`Art/UndeadForest/Tiled_files/Undead_land.tmx`). Props, ground details and rubble
are cut out of that map as "stamps", grouped by atlas offset so each stamp is
exactly one sprite the artist drew. The plateau/cliff tiling is read off the island
stamp at `Ground_rocks.png` (0-4, 0-6).

```
python export_all.py      # full export + prev_full.png
python run_build.py       # preview PNG only, for tuning layout numbers
```

| What | Where |
| --- | --- |
| Map size (tiles) | `undead_gen.py` - `MAP_W`, `MAP_H` |
| Layout seed | `build_map.py` - `SEED` |
| Plateau / pool count and size | `build_map.py` - `scatter_blobs` calls in `build()` |
| Prop and detail density | `populate.py` - the caps in `populate()` |
| Scene wiring | `export_scene.py` |

## Green Forest

`Art/Forest` ships no sample map, so the tile tables in `ftiles.py` were read off
the sheets directly and then cross-checked against the previous hand-made
GreenForest scene (`gdscene.py` decodes a `.tscn`'s `tile_map_data`, which is how
the grass inner-corner mapping and the water fallback were confirmed).

Things worth knowing before editing `ftiles.py`:

- Grass has a full inner-corner set, including the two diagonal-pair pieces.
- **Dark grass and water have no inner corners.** Concave outline corners fall back
  to the plain centre tile, which is what the original scene did too. Patch shapes
  are smoothed so this stays rare.
- `Tileset.png` (3-5, 3-5) is a rock *rim* whose centre is empty: a region tiled
  with it becomes a walled plateau whose interior is open ground.
- Row 9 is the gap-in-the-wall set (grass 0-3, dirt 4-7). Dropping those four tiles
  into a plateau's bottom edge makes the ramp you climb up through - they carry no
  collision, while the rim tiles around them do.

```
python run_forest.py      # build + export + fprev.png
```

| What | Where |
| --- | --- |
| Map size (tiles) | `undead_gen.py` - `MAP_W`, `MAP_H` (shared) |
| Layout seed | `build_forest.py` - `SEED` |
| Plateaus, ponds, dirt paths | `build_forest.py` - `build()` |
| Ramp placement | `build_forest.py` - `paint()`, the `bottom_runs` loop |
| Tree/decoration density | `build_forest.py` - `place_decor()` |
| Collision shapes | `export_forest.py` - `ROCK_POLY`, `WATER_SOLID` |

The rock collision outlines in `export_forest.py` are copied verbatim from the
hand-authored `Art/Forest/ForestTileSet.tres`, so the walls feel exactly as they
were tuned there.

## Boss arena and boss sprites

`export_boss_arena.py` builds `BossPlace.tscn` with the Undead Forest tiling at arena
scale, keeping a wide circle around the middle free so the boss telegraphs stay
readable. It also re-emits `UndeadForestTileSet.tres` from the union of the tiles
BossPlace and UndeadForest use, since both share it.

Note that `BossPlace` exits to **MainFloor**, not back to UndeadForest: UndeadForest
holds the gate into the arena, and two scenes referencing each other as
`PackedScene` is a cyclic resource Godot refuses to load.

Boss art comes from `Art/Boss/`, which ships two hand-packed sheets:

- `Phase1/Sword.png` is a clean 128x64 grid, 14 columns x 8 rows. The character's
  shadow is centred at (31, 50) in every cell, so a 64x64 crop per frame lines up
  with no per-frame fixing.
- `Phase2/Crystal Knight.png` is packed by hand at arbitrary offsets. Frames are
  located by the **orange core** of the knight, which sits at a fixed spot in its
  body; a 64x64 cell placed at core + (-32, -17) captures every pose without
  clipping a neighbour.

```
python make_boss_fx.py       # re-pack the loose VFX into Art/Boss/BossEffects.png + BossBeam.png
python make_boss_frames.py   # emit the three SpriteFrames resources into out/
```

`make_boss_fx.py` exists because the effect pieces (lightning, sparks, shards) sit at
irregular offsets and share space with a black annotation bracket the artist left in
the sheet. It lifts each piece out by connected components and re-pastes it into a
uniform grid - the pixels are untouched, only their placement changes.

### Which rows are actually attacks

Worth knowing before touching `BossMain.gd`: **rows 0-3 of `Sword.png` are all idle /
walk variants**, not attacks. Measured across those rows the body centroid moves at
most 1.3px and the weapon pixel count stays flat - the sword just bobs. Only two rows
are real attacks:

| Row | Move | Impact frames | Measured |
| --- | --- | --- | --- |
| 4 | ground slam | **4** (shockwave), **8** (dome) | shockwave spans 52 art px -> 78px radius at 3x; dome 41 px |
| 5 | dash thrust | **2** (arrival) | the ground shadow jumps from x+0 to x+66 art px between frames 1 and 2 |

`BossMain` fires every hit from `sprite.frame`, never from a timer, so the damage
window cannot drift away from the drawing. The dash is root-motioned: the character
walks across its own 128px frame, so the script cancels that in `sprite.offset` and
moves the body by the same amount, which keeps the collider on the drawing.

Crystal Knight's swing draws its crescent on frame **3** of 5; that is when the shard
fan leaves. The beam and the storm fire when the `cast` animation ends.
