extends Node2D
## Playtests what prop_collision.py wrote: drives the real Player straight at every
## prop in a level and reports anything it walks through.
##   solid props must stop it; the ones deliberately left walkable must not.
## Not part of the game - run it after re-authoring prop collision:
##
##   godot --headless --path . res://Tools/MapGen/prop_collision_check.tscn \
##         --fixed-fps 1000 --quit-after 1000000 -- res://Scenes/Levels/GreenForest.tscn
##
## --fixed-fps is what makes it finish in seconds instead of minutes: without it the
## main loop waits on real time and every 45-frame run costs most of a second.

const SPEED := 260.0        # well above the real walk speed, so nothing "just" holds
const RUN := 45             # physics frames per attempt (~195px at SPEED)
const START := 64.0         # how far out the run starts
const DIRS: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]

var player: CharacterBody2D
var body_offset := Vector2.ZERO


func _ready() -> void:
	var level_path: String = OS.get_cmdline_user_args()[0]
	var level: Node = load(level_path).instantiate()
	add_child(level)
	await get_tree().physics_frame

	player = level.find_child("Player", true, false)
	# take movement off the FSM but leave the body in the physics space
	player.set_physics_process(false)
	player.set_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	var shape := player.find_child("BodyCollisionShape", true, false) as CollisionShape2D
	body_offset = shape.position
	print("player body: %s r=%.2f at %s" % [shape.shape.get_class(), shape.shape.radius, str(body_offset)])

	# every prop obstacle in the level, as a world-space polygon
	var obstacles := {}          # kind -> [ {poly, centre} ]
	var walkable := {}           # prop kinds that carry no collision at all
	var bushes := []             # world-space centres of every bush cell
	for n in _all(level):
		if n is TileMapLayer and (n.name == "Props" or n.name == "Bushes" or n.name == "Decor"):
			_gather_tiles(n, obstacles)
			_gather_walkable(n, walkable)
			if n.name == "Bushes":
				_gather_bushes(n, bushes)
		elif n is StaticBody2D and n.name == "PropsCollision":
			for c in n.get_children():
				if c is CollisionPolygon2D:
					var pts: PackedVector2Array = []
					for p in c.polygon:
						pts.append(p + c.position)
					var kind: String = "node:" + str(c.name).split("_")[0]
					obstacles.get_or_add(kind, []).append(pts)

	print("\n--- SOLID: every placement must be solid, and the player must not enter it ---")
	var bad := 0
	var kinds: Array = obstacles.keys()
	kinds.sort()
	for kind in kinds:
		var list: Array = obstacles[kind]
		# (a) can the player's own body stand on the prop's footprint? It must not.
		var porous := 0
		for poly in list:
			if not _occupied(_centroid(poly)):
				porous += 1
		# (b) walk it down: the body centre must never end up inside the polygon
		var walked := 0
		var entered := 0
		for poly in list:
			if walked >= 2:
				break
			var r := await _walk_into(poly)
			if r == -1:
				continue
			walked += 1
			entered += r
		var ok: bool = porous == 0 and entered == 0 and walked > 0
		if not ok:
			bad += 1
		print("  %s %-14s %3d placed  %d not solid  |  walked into %d, entered %d"
			% ["ok  " if ok else "FAIL", kind, list.size(), porous, walked, entered])

	print("\n--- WALKABLE: props deliberately left passable ---")
	var wkinds: Array = walkable.keys()
	wkinds.sort()
	for kind in wkinds:
		var pts: Array = walkable[kind]
		var blocked := 0
		var tried := 0
		for p in pts:
			if tried >= 3:
				break
			var r := await _run_free(p)
			if r == -1:
				continue
			tried += 1
			if r == 0:
				blocked += 1
		var mark := "ok  " if blocked == 0 else "FAIL"
		if blocked > 0:
			bad += 1
		print("  %s %-14s %3d placed  crossed %d clear lanes  blocked %d"
			% [mark, kind, pts.size(), tried, blocked])

	if not bushes.is_empty():
		print("\n--- BUSHES: passable, but they must be sensed and must slow the player ---")
		var slow: float = player.bush_slow
		var outside: float = player.move_speed_scale()
		var sensed := 0
		var has_body := 0
		var wrong_scale := 0
		var solid := 0
		var tested := 0
		for at in bushes:
			if tested >= 40:
				break
			tested += 1
			if _blocking(at):
				solid += 1                    # the bush layer must never block on layer 1
			if not _free_on(at, 128):
				has_body += 1                 # a foliage body is actually there
			player.global_position = at - body_offset
			await get_tree().physics_frame
			await get_tree().physics_frame
			if player.is_in_bush():
				sensed += 1
				if absf(player.move_speed_scale() - (1.0 - slow)) > 0.001:
					wrong_scale += 1
		var ok: bool = solid == 0 and sensed == tested and wrong_scale == 0 and outside == 1.0
		if not ok:
			bad += 1
		print("  %s %d cells  %d block World (want 0)  %d/%d carry a foliage body  sensed %d/%d  wrong slow %d  scale outside %.2f inside %.2f"
			% ["ok  " if ok else "FAIL", bushes.size(), solid, has_body, tested, sensed,
				tested, wrong_scale, outside, 1.0 - slow])

	print("\n%s" % ("ALL PROP COLLISION CHECKS PASSED" if bad == 0 else "%d KIND(S) FAILED" % bad))
	get_tree().quit()


func _gather_tiles(layer: TileMapLayer, out: Dictionary) -> void:
	var ts := layer.tile_set
	for cell in layer.get_used_cells():
		var src := ts.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
		if src == null:
			continue
		var atlas := layer.get_cell_atlas_coords(cell)
		var raw := layer.get_cell_alternative_tile(cell)
		var alt := raw & 0x0FFF
		var flip := bool(raw & TileSetAtlasSource.TRANSFORM_FLIP_H)
		var td := src.get_tile_data(atlas, alt)
		var origin := layer.map_to_local(cell)
		for i in td.get_collision_polygons_count(0):
			var pts: PackedVector2Array = []
			for p in td.get_collision_polygon_points(0, i):
				pts.append(Vector2(-p.x if flip else p.x, p.y) + origin)
			out.get_or_add("%d:%d" % [atlas.x, atlas.y], []).append(pts)


func _gather_walkable(layer: TileMapLayer, out: Dictionary) -> void:
	var ts := layer.tile_set
	for cell in layer.get_used_cells():
		var src := ts.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
		if src == null:
			continue
		var atlas := layer.get_cell_atlas_coords(cell)
		var alt := layer.get_cell_alternative_tile(cell) & 0x0FFF
		if src.get_tile_data(atlas, alt).get_collision_polygons_count(0) > 0:
			continue
		out.get_or_add("%d:%d" % [atlas.x, atlas.y], []).append(layer.map_to_local(cell))


## A point inside each bush's foliage polygon (physics layer 1), in world space.
func _gather_bushes(layer: TileMapLayer, out: Array) -> void:
	var ts := layer.tile_set
	for cell in layer.get_used_cells():
		var src := ts.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
		if src == null:
			continue
		var raw := layer.get_cell_alternative_tile(cell)
		var flip := bool(raw & TileSetAtlasSource.TRANSFORM_FLIP_H)
		var td := src.get_tile_data(layer.get_cell_atlas_coords(cell), raw & 0x0FFF)
		if td.get_collision_polygons_count(1) == 0:
			continue
		var pts: PackedVector2Array = []
		for p in td.get_collision_polygon_points(1, 0):
			pts.append(Vector2(-p.x if flip else p.x, p.y))
		out.append(_centroid(pts) + layer.map_to_local(cell))


func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / poly.size()


func _free(at: Vector2) -> bool:
	return _free_on(at, 1)


func _free_on(at: Vector2, mask: int) -> bool:
	var q := PhysicsPointQueryParameters2D.new()
	q.collision_mask = mask
	q.position = at
	return get_world_2d().direct_space_state.intersect_point(q, 1).is_empty()


## Does anything on the World layer block a *bush* cell itself? Neighbouring scenery is
## allowed to overlap one, so only a body the bush layer owns counts.
func _blocking(at: Vector2) -> bool:
	var q := PhysicsPointQueryParameters2D.new()
	q.collision_mask = 1
	q.position = at
	for hit in get_world_2d().direct_space_state.intersect_point(q, 8):
		var owner_node = hit.get("collider")
		if owner_node is TileMapLayer and owner_node.name == "Bushes":
			return true
	return false


## Would the player's own body overlap this spot? A solid prop must say yes.
func _occupied(at: Vector2) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = 8.06226
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, at)
	q.collision_mask = 1
	return not get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


## The player is 16px across, so a lane sampled only down its centre line still snags on
## scenery sitting beside it - sample the body's width too.
func _lane_clear(a: Vector2, b: Vector2) -> bool:
	var side := (b - a).normalized().orthogonal() * 8.0
	for i in 13:
		var p := a.lerp(b, i / 12.0)
		if not (_free(p) and _free(p + side) and _free(p - side)):
			return false
	return true


## Walk the player straight at the polygon. -> 1 if the body centre ever got inside it,
## 0 if it never did, -1 if no approach lane was clear enough to be a fair test.
func _walk_into(poly: PackedVector2Array) -> int:
	var target := _centroid(poly)
	var reach := 0.0
	for p in poly:
		reach = maxf(reach, (p - target).length())
	var out := reach + START
	for dir in DIRS:
		var start := target - dir * out
		# the run-up has to be clear of *other* scenery, up to where this prop begins
		var clear := true
		var t := 0.0
		while t < out:
			var at := start + dir * t
			if Geometry2D.is_point_in_polygon(at, poly):
				break
			if not _free(at):
				clear = false
				break
			t += 3.0
		if not clear:
			continue
		player.global_position = start - body_offset
		player.velocity = Vector2.ZERO
		var need := out + reach + 16.0        # far side of the polygon
		var frames := int(ceil(need / (SPEED / 60.0))) + 15
		for i in frames:
			player.velocity = dir * SPEED
			player.move_and_slide()
			await get_tree().physics_frame
			if Geometry2D.is_point_in_polygon(player.global_position + body_offset, poly):
				return 1
		return 0
	return -1


## Walk the player across a cell that should carry no collision. -> 1 free / 0 blocked / -1 skip
func _run_free(at: Vector2) -> int:
	for dir in DIRS:
		var start := at - dir * START
		if not _lane_clear(start, at + dir * START):
			continue
		player.global_position = start - body_offset
		player.velocity = Vector2.ZERO
		for i in RUN:
			player.velocity = dir * SPEED
			player.move_and_slide()
			await get_tree().physics_frame
		var travelled := (player.global_position + body_offset - start).dot(dir)
		return 1 if travelled > START + 8.0 else 0
	return -1


func _all(n: Node, acc: Array = []) -> Array:
	acc.append(n)
	for c in n.get_children():
		_all(c, acc)
	return acc
