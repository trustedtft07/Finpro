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

| Row | Move | Source columns | Impact frames | Measured |
| --- | --- | --- | --- | --- |
| 4 | ground slam | 0-4, 7, 8, 11-13 | **4** (shockwave), **6** (dome) | shockwave spans 52 art px -> 78px radius at 3x; dome 41 px |
| 4 | spin (re-cut) | 2-3 windup, 5, 6, 9, 10 sweep | timer-driven, see below | the ring frames, the only omnidirectional art on the sheet |
| 5 | forward cleave | 0, 1, 5, 6, 3 | **1** (lance), **2** (sweep) | the lance streak runs 90 art px past the character and is ~15 art px thick; the sweep crescent reaches 29 |

**Impact frames are indices into the pack, not columns on the sheet.** The two only
happened to agree while `slam` was the whole row. They stopped agreeing the moment the
ring frames moved out of it: dropping columns 5 and 6 pulls the dome forward from index
8 to index **6**. Re-cutting a row in `make_boss_frames.py` means re-checking the
matching constants at the top of `BossMain.gd`.

`BossMain` fires every hit from `sprite.frame`, never from a timer - with one deliberate
exception noted below - so the damage window cannot drift away from the drawing. The two
rows are deliberately different shapes, and phase 1 picks a move by range: row 4 draws a
filled ellipse and then a dome, both centred on the character, so it hits as a **circle
in every direction**; row 5 draws a streak along one axis, so it hits as a **band down
that one line**, with the crescent that follows as a short wedge around the boss.

### The spin, and why it is cut out of row 4

Phase 1 wants three answers, one per range band, and the sheet only holds two attacks.
The spin is therefore a **re-cut of row 4**, not new art: columns 2-3 are the sword drawn
back and carry the windup pose on their own, and columns 5, 6, 9 and 10 are the ring
frames - the only cells anywhere on the sheet that draw force leaving the character in
every direction at once. The sword sits at a different angle in each, so looping them
while `BossMain._face_sweep()` turns the boss to follow its own sweep reads as one
continuous swing rather than four poses on repeat.

Those four ring frames are **moved out of `slam`, not copied**. Leaving them in both
packs meant the boss drew the same expanding rings for two different moves, and a boss's
tells are the one thing that must never read the same - a player cannot commit to a dodge
they have to wait out to identify. What is left in `slam` is its own shape: windup, the
ground burst, the dome, recovery. Columns 4 and 8 are held 1.8 frame-units each so the
two bursts still carry the move now that the rings are not there to dissipate them; the
slam comes out at 1.20s instead of 1.40s, which reads as tighter rather than clipped.

It is the one phase 1 move driven by a timer instead of by `sprite.frame`, because its
hitbox is a wedge rotating continuously rather than a single frame that connects; the
`spin` animation loops underneath for however long `spin_sweep_time` is set to. Two
consequences worth keeping in mind:

- **The loop has to be taken off screen explicitly.** `slam` and `cleave` end themselves,
  a looping `spin` does not. Every exit runs `_play_narrow("idle")` and every act change
  goes through `_enter()`, which is the single place `BossSpinAura.finish()` is called -
  recovery, a parry, the phase flip, death and a leash reset all land there.
- **The drawing and the hitbox share their numbers.** `BossSpinAura` is handed the same
  radius, arc and angle `_hit_player_wedge()` is testing that frame, the way `AttackAura`
  works on the player's side, so retuning `spin_radius` in the inspector moves the
  crescent with it and the move stays dodgeable on sight rather than by memory. The sweep
  also opens on the *far* side of the player and travels round to them, which buys half a
  revolution of visible warning on top of the windup.

Row 5 is root-motioned - the character walks ~66 art px across its own 128px cell. It
used to be packed verbatim, with the script cancelling the travel in `sprite.offset`
and moving the body by the same amount; on screen that read as the sprite sliding off
its own body, so the move was pulled. It is back as `cleave` with the travel taken out
of the **pack** instead: every frame is cropped at its own travel offset, so the
character lands on the usual (31, 50) anchor in all of them and only the slash moves.
The boss itself no longer travels at all. Those cells are the full 128 wide, so
`BossMain.CLEAVE_CELL_OFFSET` swaps in for the duration of the animation - the two
offsets put the character in the same spot, which is why the swap is invisible.

Three things about that pack are easy to get wrong, and all three were, first time round:

- **Measure the travel off the ground shadow, not the silhouette.** The shadow is the
  sheet's only translucent colour (35/0/56 at alpha 57) and sits in a fixed spot under
  the character, so it is the anchor. Correlating the body silhouette instead is
  thrown off by the slash pixels drawn over it, which put two frames 1-2 art px out -
  3-6px of sideways twitch on screen at 3x. Take the shadow's **left** edge: the sweep
  crescents cover its right half.
- **Not every frame survives being pinned.** Column 2 is the lunge's motion trail, a
  dark bar drawn 39 art px behind the character. Behind someone who just travelled
  through it that reads as speed; behind a boss standing still it reads as a plank
  stuck through its back. It is left out of the pack.
- **The offset and the animation have to move together.** The cleave is the only phase 1
  animation in wide cells, so it rides `CLEAVE_CELL_OFFSET` while it plays. Putting that
  offset back on its own - without starting a narrow-cell animation in the same breath -
  leaves the last cleave frame on screen against the narrow offset, and 33 + (31 - 64) is
  -32 art px: the boss is drawn 96px behind itself until something else finally plays.
  Every exit out of the cleave goes through `BossMain._play_narrow()` for exactly this
  reason, and `_smoke` checks the drawn anchor every physics frame rather than checking
  the offset value, which is what let the bug through the first time.

The lance is only ever drawn along the sprite's own x, so its hitbox takes its
direction from the facing flip rather than from where the player is standing, and the
boss only commits to the swing when the player is inside `cleave_band` of its own line.
Stepping north or south out of that band is the dodge.

Crystal Knight's swing draws its crescent on frame **3** of 5; that is when the shard
fan leaves. The beam and the storm fire when the `cast` animation ends. The beam
leaves the **lit core in the knight's head**, cell (32, 12.5) - `BossMain.HEAD_CELL` -
and is aimed from that same point, so its hitbox is exactly the line it draws.
