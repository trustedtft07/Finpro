extends EnemyMain
class_name BossMain

#Two-phase boss.
#  Phase 1 - the Sword: walks the player down, slams the ground at close range and
#            dash-thrusts to close a gap.
#  Phase 2 - the Crystal Knight: roots itself in place and fights at range with a
#            charged beam, fans of small shards, and a lightning storm that paints a
#            circle on the ground before every bolt lands.
#Both phases share one health pool, the way a soulslike boss bar does.
#
#Every hit is fired from the animation frame that draws it, never from a timer, so
#the damage window can't drift out of sync with what the player sees. The frame
#numbers and hit radii below were measured off the sprite sheets - see
#Tools/MapGen/README.md.

signal phase_started(phase : int, boss_name : String)
signal boss_defeated

enum Act {
	SLEEP,                                   # waiting for the player to walk in
	CHASE, SLAM, DASH, RECOVER,              # phase 1
	TRANSITION,
	IDLE2, CAST, SPREAD, STORM,              # phase 2
	DYING,
}

const PHASE1 := 1
const PHASE2 := 2

#--- frames that actually connect, read off Sword.png -------------------------
#row 4 "slam": frame 4 draws the ground shockwave, frame 8 the rising dome
const SLAM_HIT_FRAME := 4
const SLAM_DOME_FRAME := 8
#row 5 "dash": frame 1 is the lunge streak, frame 2 is the character arriving with
#the sword out. Travel below is its ground shadow per frame, in art pixels.
const DASH_HIT_FRAME := 2
const DASH_TRAVEL : Array[float] = [0.0, 0.0, 66.0, 68.0, 67.0, 66.0, 65.0]
#the dash frames use the full 128x64 cell; anchor (31,50) sits at this offset in it
const DASH_CELL_OFFSET := Vector2(33, -18)
#row 3 of Crystal Knight's swing is where the crescent is drawn
const SWING_FIRE_FRAME := 3

@export_group("Identity")
@export var phase1_name : String = "The Crimson Sword"
@export var phase2_name : String = "Crystal Knight, Reborn"

@export_group("Activation")
@export var activation_range : float = 420.0
#Beyond this the fight resets - stops the boss trailing the player out of the arena
@export var leash_range : float = 1500.0

@export_group("Phase 1")
@export var chase_speed : float = 150.0
#The shockwave sprite is 52 art px across; at 3x that is a 78px radius on the ground
@export var slam_range : float = 92.0
@export var slam_radius : float = 80.0
@export var slam_damage : int = 44
#The dome is narrower than the shockwave, and only clips whoever stayed in it
@export var dome_radius : float = 62.0
@export var dome_damage : int = 26
@export var slam_recover : float = 0.6
#The dash covers a fixed 66 art px (198px at 3x), so it is only worth using from
#roughly that far out
@export var dash_min_range : float = 165.0
@export var dash_max_range : float = 290.0
@export var dash_radius : float = 58.0
@export var dash_damage : int = 38
@export var dash_recover : float = 0.5
@export var dash_cooldown : float = 3.2

@export_group("Phase 2")
@export var beam_damage : int = 42
@export var beam_lifetime : float = 0.95
@export var shard_damage : int = 16
@export var shard_volleys : int = 3
@export var storm_damage : int = 40
@export var storm_bolts : int = 7
@export var idle2_gap : float = 1.15

@export_group("Wiring")
@export var phase1_frames : SpriteFrames
@export var phase2_frames : SpriteFrames
@export var phase1_offset : Vector2 = Vector2(1, -19)
@export var phase2_offset : Vector2 = Vector2(0, -29)
@export var phase1_scale : float = 3.0
@export var phase2_scale : float = 2.0
#Body capsule per phase (radius, total height, centre y), sized to the drawn figure -
#the same shape is what the player's sword has to reach, so it has to match the art
@export var collider : CollisionShape2D
@export var phase1_body : Vector3 = Vector3(20, 56, -30)
@export var phase2_body : Vector3 = Vector3(34, 96, -52)
@export var beam_scene : PackedScene
@export var shard_scene : PackedScene
@export var lightning_scene : PackedScene
@export var hud : BossHUD
@export var arena_radius : float = 520.0

var phase : int = PHASE1
var act : int = Act.SLEEP
var _timer : float = 0.0
var _player : PlayerMain
var _origin : Vector2
var _aim : Vector2 = Vector2.RIGHT
var _last_move : int = -1
var _fired : bool = false
var _fired2 : bool = false
var _volleys_left : int = 0
var _dash_from : Vector2
var _dash_dir : Vector2 = Vector2.RIGHT
var _dash_ready_at : float = 0.0

func _ready():
	super()
	_origin = global_position
	_wear_phase1()
	if hud:
		hud.hide_bar()

func _physics_process(delta):
	super(delta)
	_player = get_tree().get_first_node_in_group("Player") as PlayerMain

	if act == Act.DYING:
		return
	#Facing is frozen through a dash: flipping mid-lunge would mirror its travel
	if act != Act.DASH:
		_face_player()

	if act == Act.SLEEP:
		_check_activation()
		return

	if is_knockbacked:
		#CharacterBase is driving the body this frame; just let the clock run
		_timer -= delta
		return

	_timer -= delta
	match act:
		Act.CHASE: _do_chase()
		Act.SLAM: _do_slam()
		Act.DASH: _do_dash()
		Act.RECOVER: _do_recover()
		Act.TRANSITION: _do_transition()
		Act.IDLE2: _do_idle2()
		Act.CAST: _do_cast()
		Act.SPREAD: _do_spread()
		Act.STORM: _do_storm()

#region helpers
#CharacterBase turns by velocity, which a rooted phase 2 boss never has
func Turn():
	pass

func _alive_player() -> bool:
	return is_instance_valid(_player) and not _player.is_dead

func _to_player() -> Vector2:
	if not _alive_player():
		return Vector2.RIGHT
	return _player.global_position - global_position

func _face_player():
	if not _alive_player():
		return
	var dir = -1.0 if flipped_horizontal else 1.0
	var size = absf(sprite.scale.x)
	sprite.scale.x = size * (dir if _to_player().x >= 0.0 else -dir)

func _enter(new_act : int, duration : float):
	act = new_act
	_timer = duration
	_fired = false
	_fired2 = false

func _wear_phase1():
	sprite.sprite_frames = phase1_frames
	sprite.offset = phase1_offset
	sprite.scale = Vector2(phase1_scale, phase1_scale)
	_apply_body(phase1_body)
	sprite.play("idle")

#Fresh shape per call: a shape resource edited in place would be shared by every
#instance of this scene
func _apply_body(body : Vector3):
	if collider == null:
		return
	var capsule := CapsuleShape2D.new()
	capsule.radius = body.x
	capsule.height = body.y
	collider.shape = capsule
	collider.position = Vector2(0.0, body.z)

func _check_activation():
	if not _alive_player() or _to_player().length() > activation_range:
		return
	if hud:
		hud.show_bar(phase1_name, max_health, health)
	phase_started.emit(PHASE1, phase1_name)
	sprite.play("walk")
	_enter(Act.CHASE, 0.0)

#Damage the player if it stands inside `radius`. Honours the parry window.
func _hit_player(radius : float, damage : int):
	if not _alive_player():
		return
	var offset = _to_player()
	if offset.length() > radius:
		return
	if _player.try_parry(self):
		return
	_player._take_damage(damage)
	var push = offset.normalized()
	if push == Vector2.ZERO:
		push = Vector2.RIGHT
	_player.apply_knockback(push, 260.0)
	AudioManager.play_sound(AudioManager.ENEMY_HIT, 0, -8)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
#endregion

#region phase 1
func _do_chase():
	if not _alive_player():
		velocity = Vector2.ZERO
		return
	var offset = _to_player()
	var distance = offset.length()
	if distance > leash_range:
		_reset_fight()
		return

	if distance <= slam_range:
		velocity = Vector2.ZERO
		_start_slam()
		return
	if distance >= dash_min_range and distance <= dash_max_range and _now() >= _dash_ready_at:
		velocity = Vector2.ZERO
		_start_dash()
		return

	if sprite.animation != "walk":
		sprite.play("walk")
	velocity = offset.normalized() * chase_speed
	move_and_slide()

func _start_slam():
	_last_move = Act.SLAM
	sprite.play("slam")
	_enter(Act.SLAM, 0.0)

func _do_slam():
	var frame = sprite.frame
	if not _fired and frame >= SLAM_HIT_FRAME:
		_fired = true
		_hit_player(slam_radius, slam_damage)
		GameManager.hitstop(0.05, 0.25)
	if not _fired2 and frame >= SLAM_DOME_FRAME:
		_fired2 = true
		_hit_player(dome_radius, dome_damage)
	if not sprite.is_playing():
		_enter(Act.RECOVER, slam_recover)

func _start_dash():
	_last_move = Act.DASH
	_dash_from = global_position
	_dash_dir = _to_player().normalized()
	if _dash_dir == Vector2.ZERO:
		_dash_dir = Vector2.RIGHT
	#Lock the facing before the lunge so the art travels the way the boss moves
	var dir = -1.0 if flipped_horizontal else 1.0
	sprite.scale.x = absf(sprite.scale.x) * (dir if _dash_dir.x >= 0.0 else -dir)
	sprite.offset = DASH_CELL_OFFSET
	sprite.play("dash")
	_enter(Act.DASH, 0.0)
	_dash_ready_at = _now() + dash_cooldown

func _do_dash():
	var frame = mini(sprite.frame, DASH_TRAVEL.size() - 1)
	var art_travel = DASH_TRAVEL[frame]
	#Root motion: the character walks across its own frame, so cancel that in the
	#sprite offset and move the body instead. The hitbox then tracks the drawing.
	sprite.offset.x = DASH_CELL_OFFSET.x - art_travel
	var target = _dash_from + _dash_dir * (art_travel * phase1_scale)
	var step = target - global_position
	if step.length() > 0.5:
		move_and_collide(step)

	if not _fired and frame >= DASH_HIT_FRAME:
		_fired = true
		_hit_player(dash_radius, dash_damage)
		GameManager.hitstop(0.04, 0.3)

	if not sprite.is_playing():
		sprite.offset = phase1_offset
		_enter(Act.RECOVER, dash_recover)

func _do_recover():
	if _timer > 0.0:
		return
	sprite.play("walk")
	_enter(Act.CHASE, 0.0)

func _reset_fight():
	velocity = Vector2.ZERO
	global_position = _origin
	health = max_health
	healthbar.value = health
	phase = PHASE1
	_wear_phase1()
	if hud:
		hud.hide_bar()
	act = Act.SLEEP
#endregion

#region phase transition
func _start_transition():
	invincible = true
	velocity = Vector2.ZERO
	sprite.offset = phase1_offset
	sprite.play("death")
	if hud:
		hud.flash()
	_enter(Act.TRANSITION, 0.0)

func _do_transition():
	if sprite.is_playing():
		return
	phase = PHASE2
	invincible = false
	sprite.sprite_frames = phase2_frames
	sprite.offset = phase2_offset
	sprite.scale = Vector2(phase2_scale, phase2_scale)
	_apply_body(phase2_body)
	sprite.play("spawn")
	if hud:
		hud.set_name_text(phase2_name)
	phase_started.emit(PHASE2, phase2_name)
	_enter(Act.IDLE2, 0.9)
#endregion

#region phase 2
func _do_idle2():
	velocity = Vector2.ZERO
	if sprite.animation != "idle" and not sprite.is_playing():
		sprite.play("idle")
	if _timer > 0.0:
		return
	_pick_phase2_move()

func _pick_phase2_move():
	var moves : Array[int] = [Act.CAST, Act.SPREAD, Act.STORM]
	moves.erase(_last_move)
	var choice = moves[randi() % moves.size()]
	_last_move = choice
	match choice:
		Act.CAST:
			_aim = _to_player().normalized()
			sprite.play("cast")
			_enter(Act.CAST, 0.0)
		Act.SPREAD:
			_volleys_left = shard_volleys
			_play_swing()
			_enter(Act.SPREAD, 0.0)
		Act.STORM:
			sprite.play("cast")
			_enter(Act.STORM, 0.0)

func _play_swing():
	sprite.play("attack_r" if _to_player().x >= 0.0 else "attack_l")

#The beam leaves on the last frame of the charge, and tracks until then
func _do_cast():
	if sprite.frame < sprite.sprite_frames.get_frame_count("cast") - 1 and _alive_player():
		_aim = _to_player().normalized()
	if sprite.is_playing():
		return
	if beam_scene:
		var beam = beam_scene.instantiate()
		beam.direction = _aim
		beam.damage = beam_damage
		beam.lifetime = beam_lifetime
		beam.global_position = global_position + Vector2(0, -14)
		get_tree().current_scene.add_child(beam)
	AudioManager.play_sound(AudioManager.PLAYER_ATTACK_SWING, 0.0, 2)
	_enter(Act.IDLE2, beam_lifetime + idle2_gap)

#Shards leave on the frame the crescent is drawn, one volley per swing
func _do_spread():
	if not _fired and sprite.frame >= SWING_FIRE_FRAME:
		_fired = true
		_fire_fan(7, 0.85)
		_volleys_left -= 1
	if sprite.is_playing():
		return
	if _volleys_left > 0:
		_play_swing()
		_enter(Act.SPREAD, 0.0)
		return
	_enter(Act.IDLE2, idle2_gap)

func _fire_fan(count : int, spread : float):
	if not shard_scene or count < 2:
		return
	var base = _to_player().normalized()
	if base == Vector2.ZERO:
		base = Vector2.DOWN
	for i in count:
		var t = (float(i) / float(count - 1)) - 0.5
		var shard = shard_scene.instantiate()
		shard.direction = base.rotated(t * spread)
		shard.damage = shard_damage
		shard.global_position = global_position + Vector2(0, -12) + shard.direction * 26.0
		get_tree().current_scene.add_child(shard)

func _do_storm():
	if sprite.is_playing():
		return
	if not _fired:
		_fired = true
		_call_storm()
		_enter(Act.IDLE2, 2.1 + idle2_gap)

func _call_storm():
	if not lightning_scene or not _alive_player():
		return
	var target = _player.global_position
	for i in storm_bolts:
		var spot : Vector2
		if i == 0:
			spot = target
		else:
			var angle = randf() * TAU
			spot = target + Vector2(cos(angle), sin(angle)) * randf_range(70.0, 240.0)
		var bolt = lightning_scene.instantiate()
		bolt.damage = storm_damage
		bolt.warn_time = 0.85 + i * 0.11
		bolt.global_position = _clamp_to_arena(spot)
		get_tree().current_scene.add_child(bolt)

func _clamp_to_arena(point : Vector2) -> Vector2:
	var offset = point - _origin
	if offset.length() > arena_radius:
		offset = offset.normalized() * arena_radius
	return _origin + offset
#endregion

#region damage / death
func _take_damage(amount):
	if act == Act.SLEEP or act == Act.TRANSITION or is_dead:
		return
	super._take_damage(amount)
	if hud:
		hud.on_damaged(health)
	#Half health flips the fight into its second phase instead of killing it
	if phase == PHASE1 and not is_dead and health <= max_health * 0.5:
		_start_transition()

#Bosses shrug most of the shove off, or a combo would push them out of the arena
func apply_knockback(direction : Vector2, force : float, duration : float = 0.15):
	if act == Act.TRANSITION or act == Act.DYING or act == Act.SLEEP or act == Act.DASH:
		return
	super.apply_knockback(direction, force * 0.12, duration * 0.6)

#A parry staggers the boss out of its swing. Moving to RECOVER also drops the rest of
#the attack's frame-driven hits, since those only fire from SLAM/DASH.
func interrupt_attack():
	if act != Act.SLAM and act != Act.DASH:
		return
	sprite.offset = phase1_offset
	sprite.play("hurt" if phase == PHASE1 else "idle")
	_enter(Act.RECOVER, slam_recover * 1.6)

func finished_attacking():
	pass

func _die():
	if is_dead:
		return
	is_dead = true
	act = Act.DYING
	velocity = Vector2.ZERO
	if phase == PHASE1:
		sprite.offset = phase1_offset
	sprite.play("death")
	if hud:
		hud.on_defeated()
	boss_defeated.emit()
	GameManager.hitstop(0.35, 0.08)
	var tween = create_tween()
	tween.tween_interval(1.1)
	tween.tween_property(self, "modulate:a", 0.0, 0.9)
	tween.tween_callback(queue_free)
#endregion
