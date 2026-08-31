extends Node2D
## Plays the boss fight headless and checks phase 3 holds its shape:
##   - the fight reaches phase 1 -> 2 -> 3
##   - in phase 3 attacks strictly alternate melee / ranged
##   - the sword form walks, the knight form never moves
##   - it dies instead of stalling
##
## Not part of the game - run it after touching BossMain:
##
##   godot --headless --path . res://Tools/MapGen/boss_phase_check.tscn \
##         --fixed-fps 1000 --quit-after 1000000
##
## Every melee turn comes out as a slam: spin and cleave sit behind wall-clock cooldowns
## (Time.get_ticks_msec) and this runs ~25x faster than real time, so they never come
## round here. That is the harness, not the boss - the alternation is what is under test.

const MELEE := [BossMain.Act.SLAM, BossMain.Act.SPIN, BossMain.Act.CLEAVE]
const RANGED := [BossMain.Act.CAST, BossMain.Act.SPREAD, BossMain.Act.STORM]

var boss: BossMain
var player: Node2D
var turns: Array = []           # ["melee:SLAM", "ranged:CAST", ...] seen in phase 3
var phases: Array = []
var knight_speed := 0.0
var sword_speed := 0.0
var morphs := 0
var anchor_slips: Array = []


func _ready() -> void:
	GameManager.god_mode = true       # the player is scenery here, not a participant
	var level: Node = load("res://Scenes/Levels/BossPlace.tscn").instantiate()
	add_child(level)
	await get_tree().physics_frame

	boss = level.find_child("Boss", true, false) as BossMain
	player = level.find_child("Player", true, false) as Node2D
	player.set_physics_process(false)
	player.set_process(false)
	boss.phase_started.connect(func(p, n): phases.append("%d:%s" % [p, n]))

	# Stand the player in front of the boss and let it be reached - the boss's cooldowns
	# are wall-clock (Time.get_ticks_msec), and this runs ~25x faster than real time, so
	# anything that waits on one would never come round. Slam has no cooldown, so an
	# arrival always resolves the melee turn.
	player.global_position = boss.global_position + Vector2(300, 0)

	var last_act := -1
	var last_form := boss._wearing_knight
	var frames := 0
	var stage := 0                # 0 = beat it to phase 3, 1 = watch, 2 = finish it
	var watch_left := 3000
	var trace: Array = []

	while frames < 30000:
		frames += 1
		await get_tree().physics_frame
		if not is_instance_valid(boss):
			break
		if trace.size() < 24 and frames % 200 == 0:
			trace.append("f%d p%d %s hp=%d v=%.0f%s"
				% [frames, boss.phase, _act_name(boss.act), boss.health,
					boss.velocity.length(), " KNIGHT" if boss._wearing_knight else ""])

		# record what the boss is doing
		if boss.act != last_act:
			last_act = boss.act
			if boss.phase == BossMain.PHASE3:
				if MELEE.has(boss.act):
					turns.append("melee:%s" % _act_name(boss.act))
				elif RANGED.has(boss.act):
					turns.append("ranged:%s" % _act_name(boss.act))
		if boss._wearing_knight != last_form:
			last_form = boss._wearing_knight
			if boss.phase == BossMain.PHASE3:
				morphs += 1
				# put the player back out of reach when the sword comes on, so every
				# melee turn has to include an approach
				if not last_form:
					player.global_position = _bait_spot()
		var speed: float = boss.velocity.length()
		if boss.phase == BossMain.PHASE3:
			if boss._wearing_knight:
				knight_speed = maxf(knight_speed, speed)
			else:
				sword_speed = maxf(sword_speed, speed)
			_check_anchor()

		match stage:
			0:
				if boss.phase == BossMain.PHASE3:
					stage = 1
				elif frames % 6 == 0:
					boss._take_damage(6)
			1:
				watch_left -= 1
				if watch_left <= 0:
					stage = 2
			2:
				if frames % 6 == 0:
					boss._take_damage(6)
				if boss.is_dead:
					break

	print("\ntrace:")
	for t in trace:
		print("   %s" % t)
	_report()
	get_tree().quit()


func _act_name(a: int) -> String:
	return BossMain.Act.keys()[a]


## The sprite's cell offset has to travel with the body it belongs to. The cleave is the
## one animation packed in wide cells and rides its own offset; leaving that offset on
## against a narrow frame draws the boss 96px behind itself, and phase 3 swapping bodies
## mid-fight is a fresh way to strand it.
func _check_anchor() -> void:
	if anchor_slips.size() >= 4:
		return
	var want: Vector2 = boss.phase2_offset if boss._wearing_knight else boss.phase1_offset
	if boss.act == BossMain.Act.CLEAVE:
		want = BossMain.CLEAVE_CELL_OFFSET
	if boss.sprite.offset.distance_to(want) > 0.5:
		anchor_slips.append("%s %s: offset %s, wanted %s"
			% ["knight" if boss._wearing_knight else "sword", _act_name(boss.act),
				str(boss.sprite.offset), str(want)])


## 300px from the boss, toward the middle of the arena and on ground it can actually
## walk - dropping the bait at a fixed +x offset parks it behind the ruins often enough
## that the boss spends the test shoving at a rock.
func _bait_spot() -> Vector2:
	var inward: Vector2 = boss._origin - boss.global_position
	if inward.length() < 1.0:
		inward = Vector2.RIGHT
	for step in 8:
		var at: Vector2 = boss.global_position + inward.normalized().rotated(step * 0.5) * 300.0
		if _clear(at):
			return at
	return boss._origin


func _clear(at: Vector2) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var c := CircleShape2D.new()
	c.radius = 40.0
	q.shape = c
	q.transform = Transform2D(0.0, at)
	q.collision_mask = 1
	return get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


func _report() -> void:
	var bad := 0
	print("\nphases seen:")
	for p in phases:
		print("   %s" % p)
	if phases.size() != 3:
		bad += 1
		print("  FAIL expected 3 phase announcements, got %d" % phases.size())
	else:
		print("  ok   all three phases announced")

	print("\nphase 3 turn order (%d turns, %d body changes):" % [turns.size(), morphs])
	print("   %s" % ", ".join(turns.slice(0, 14)))
	var breaks := 0
	for i in range(1, turns.size()):
		if turns[i].split(":")[0] == turns[i - 1].split(":")[0]:
			breaks += 1
			if breaks <= 3:
				print("  FAIL %s follows %s" % [turns[i], turns[i - 1]])
	if turns.size() < 6:
		bad += 1
		print("  FAIL only %d attacks in phase 3 - it is stalling" % turns.size())
	elif breaks > 0:
		bad += 1
		print("  FAIL %d place(s) where the same kind repeats" % breaks)
	else:
		print("  ok   melee and ranged strictly alternate over %d turns" % turns.size())

	print("\nmovement per body in phase 3:")
	print("   sword  peak speed %.1f px/s" % sword_speed)
	print("   knight peak speed %.1f px/s" % knight_speed)
	if sword_speed < 50.0:
		bad += 1
		print("  FAIL the sword form never walked")
	elif knight_speed > 1.0:
		bad += 1
		print("  FAIL the knight form moved")
	else:
		print("  ok   the sword walks, the knight stays rooted")

	print("\nsprite anchor while phase 3 swaps bodies:")
	if anchor_slips.is_empty():
		print("  ok   the cell offset always matched the body on screen")
	else:
		bad += 1
		for s in anchor_slips:
			print("  FAIL %s" % s)

	if not is_instance_valid(boss) or boss.is_dead:
		print("\n  ok   the fight ended - the boss died")
	else:
		bad += 1
		print("\n  FAIL the boss never died (phase %d, act %s at %s, v=%.0f)"
			% [boss.phase, _act_name(boss.act), str(boss.global_position),
				boss.velocity.length()])

	print("\n%s" % ("BOSS PHASE 3 CHECKS PASSED" if bad == 0 else "%d CHECK(S) FAILED" % bad))
