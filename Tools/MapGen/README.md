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

Prop collision is authored separately by `prop_collision.py`, off the art rather than the
layout, and applies to both levels - see "Where a prop's collision actually goes" below.

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

## Props: tiles and collision

The two forest scenes carry their props as one **`Props` TileMapLayer** each, not as
Sprite2D nodes - collision comes from the tileset's physics layer, and GreenForest drops
from 1176 nodes to 46, UndeadForest from 527 to 98. Four details make that exact:

- **A 1px atlas grid.** Neither sheet is laid out on the 16px grid (Decorations.png packs
  its trees tightly, straddling cell boundaries), so the prop atlas source uses
  `texture_region_size = Vector2i(1, 1)` and `size_in_atlas` in pixels. Any region is then
  addressable without repacking the art.
- **Even-sized regions.** Godot rounds a Sprite2D's half-size to whole pixels but leaves a
  tile's on the half; an odd-sized region rasterises visibly squashed. Odd regions are
  grown one pixel into their own transparent margin first.
- **`texture_origin` places the art, `y_sort_origin` sorts it.** A multi-cell tile is drawn
  centred on its map cell, so `texture_origin = cell centre - where the sprite drew it`.
  Sorting is lifted by `SORT_LIFT` (16px): the player's origin sits at the centre of its
  32x32 sprite, 16px above its feet, while props are anchored at their base - without the
  lift the player is drawn behind a prop it has already walked past.
- **A flipped alternative per kind.** A flipped tile mirrors about the *map cell's* centre,
  which negates `texture_origin.x` - so alternative 1 of every kind carries flip-corrected
  geometry, and flipped props are placed with `alternative = FLIP_H | 1`.

UndeadForest's 46 animated props stay as `AnimatedSprite2D` under `PropsAnimated`: tileset
tile animation runs off a single clock, which would drop their randomised per-prop phase
and make every instance of a kind pulse in lockstep.

The conversion was verified by rendering the committed Sprite2D scenes against the tile
scenes - both levels come out **pixel-identical**.

### Where a prop's collision actually goes

`prop_collision.py` authors every prop polygon from the art itself, because writing them
by hand gets the frame wrong in two ways that are invisible until you play the level.
Both rules below were **measured against Godot 4.6**, not assumed - a probe placed each
tile, rendered it, and read the shapes back out of the physics server.

- **A polygon is in cell-local space, and the art is not centred on the cell.** The drawn
  region's top-left sits at `cell centre - size/2 - texture_origin`, so a 98px-tall tree
  with `texture_origin = (0, 0)` has its *roots 48px below the cell*. Polygons authored
  around the cell (`-16, 0 .. 16, 16` - what every prop shipped with) therefore floated in
  mid-canopy: the player walked through every trunk and was stopped by empty air above it.
- **`FLIP_H` mirrors the stored polygon about x = 0, and negates `texture_origin.x`.** So
  the flipped art's region starts at `-size/2 + texture_origin.x`, and alternative 1 has to
  store the polygon it wants *pre-mirrored*. Storing an already-mirrored polygon there - the
  obvious thing to do, and what the tilesets shipped with - mirrors it twice, putting the
  collision of every asymmetric flipped prop on the wrong side.

The footprint of each solid prop is the band of its own silhouette that rests on the ground
(`SOLID` in `prop_collision.py`, in px measured up from the art's lowest opaque row). That
band is eroded to drop tendrils - root hairs, thin bones, the skeleton king's arms, which
would otherwise balloon the hull - and what survives becomes one convex polygon per lump.
Trees and logs (GreenForest) and trees, rocks, ruins and big skulls (UndeadForest) are
solid; grass, mushrooms, ferns, loose bones and rubble stay walkable.

GreenForest's ground rocks are the exception to the "props are the 1px atlas" rule: they are
32x32 tiles in the 16px **decor** atlas with no `texture_origin` at all, so their local frame
is just `art (u, v) -> (u - 16, v - 16)`. They are listed separately in `DECOR_SOLID`, and a
rock's whole silhouette is its footprint rather than a base band.

GreenForest also carried a separate `Collision` TileMapLayer: one invisible 16x16 cell per
tall tree, from back when props were Sprite2D nodes anchored at their base. The tile
conversion moved the anchor into the canopy and left those cells behind, so all 430 of them
were invisible walls standing in open grass. They are gone - `build_forest.py` no longer
emits them and the trees carry trunk-shaped polygons instead. UndeadForest's `Collision`
layer is terrain (cliff faces and water) and is untouched.

Props that stayed as **nodes** cannot hold a tileset polygon: UndeadForest's 46 animated
ones, and the whole of BossPlace, which was never converted to tiles. Those get one
`PropsCollision` StaticBody2D per scene with a `CollisionPolygon2D` per instance, rather
than a body each. Both `Sprite2D` and `AnimatedSprite2D` props here are centred with
`offset = (0, -h/2)`, so the art's bottom edge lands exactly on the node origin:
art `(u, v)` -> local `(u - w/2, v - h)`, mirrored about x when the node is flipped. The
animated kinds are keyed by *source region* rather than SpriteFrames id, because the two
scenes number theirs differently for the same art.

```
python prop_collision.py --out out      # re-author both tilesets + all three scenes
```

It is idempotent - it strips what it wrote last time before writing again - and rewrites
`Art/*/…TileSet.tres` plus GreenForest, UndeadForest and BossPlace. The scene steps chain
through `out/`, so several passes may touch the same scene.

### Bushes: drawn over the player, and they slow it down

Walking into a bush should read as pushing through branches, which takes two things the
tilesets could not express on their own.

- **Drawn over the player.** Bushes used to be y-sorted in with the trees in `Props`, so the
  player passed in front of them as often as behind. They are split out into their own
  **`Bushes` TileMapLayer at `z_index = 1`**, which draws over the player unconditionally -
  walk into one and you are hidden. Trees stay in `Props` at z 0 and keep y-sorting normally.
  BossPlace has no bush layer to split, so its 16 bush *sprites* get `z_index = 1` directly.
- **Sensed without blocking.** Bushes carry a second polygon on **physics layer 8
  ("Foliage", bit 128)**, which nothing masks - it blocks no one and exists only to be read.
  `PlayerMain.is_in_bush()` asks for it with a shape query and `move_speed_scale()` returns
  `1 - bush_slow` (0.6) while inside, which `PlayerWalkState` applies to its target speed.

Two things worth knowing before changing that:

- **An `Area2D` does not work here.** A sensor Area2D on the player, correctly masked and
  positioned, reports *zero* overlapping bodies against TileMapLayer's own static foliage
  bodies, while a `intersect_shape` at the identical transform and mask returns the hit. The
  query is also answered on the frame it is asked rather than one frame late.
- **The roll is deliberately exempt.** Only `PlayerWalkState` scales its speed. A dodge that
  scenery can slow is a dodge the player cannot commit to on sight.

The bush slow is forest-only by design: BossPlace's bushes are lifted for the visual but
carry no foliage polygon, because a slow field inside a boss arena reads as the dodge being
cheated rather than as scenery.

`Scenes/Interactables/Bonfire.tscn` sits next to this: it used to draw at `z_index = 5`, on
top of the player standing on it. It is z 0 now, and the three y-sorted outdoor levels drop
their own instance to -1 so the player is strictly above it - still clear of every ground
layer, which sits at -3 and below. The "Press 'E'" label carries its own `z_index` so it
stays readable over the scenery.

Check the result by actually playing it: `prop_collision_check.gd` drives the real Player
at every prop in a level and fails on anything the player's body can enter, on any walkable
prop that turns out to block a clear lane, and on any bush that either blocks the player or
fails to slow it.

```
godot --headless --path . res://Tools/MapGen/prop_collision_check.tscn \
	  --fixed-fps 1000 --quit-after 1000000 -- res://Scenes/Levels/GreenForest.tscn
```

`--fixed-fps` matters: without it the loop waits on real time and the run takes minutes
instead of a couple of seconds. For a picture rather than a verdict, run any level with
`--debug-collisions` and set the layers' `collision_visibility_mode` to force-show.

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
