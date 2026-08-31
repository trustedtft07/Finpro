extends EnemyMain
class_name BossMain

#Two-phase boss.
#  Phase 1 - the Sword: walks the player down and answers with one of three swings,
#            one per range band - a ground slam at its feet, a whirling spin that
#            sweeps the ring around it twice, and a forward cleave that lances a long
#            way down a single line.
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
	CHASE, SLAM, SPIN, CLEAVE, RECOVER,      # phase 1
	TRANSITION,
	IDLE2, CAST, SPREAD, STORM,              # phase 2
	DYING,
}

const PHASE1 := 1
const PHASE2 := 2

#--- frames that actually connect, read off Sword.png -------------------------
#row 4 "slam": source column 4 draws the ground shockwave, column 8 the rising dome.
#Both are drawn centred on the character, so both hit as circles.
#
#These are indices into the PACK, not columns on the sheet, and the two stopped matching
#when the ring frames moved out to "spin": dropping columns 5 and 6 pulls the dome
#forward from index 8 to index 6. Re-cutting the slam in make_boss_frames.py means
#re-checking this pair.
const SLAM_HIT_FRAME := 4
const SLAM_DOME_FRAME := 6
#"cleave" is row 5 re-packed in place (see Tools/MapGen/make_boss_frames.py): frame 1
#draws the lance streak, frame 3 the sweep crescent that follows it. Its cells are the
#full 128x64, so the sprite carries a different offset while this one plays.
const CLEAVE_LANCE_FRAME := 1
const CLEAVE_SWEEP_FRAME := 2
const CLEAVE_CELL_OFFSET := Vector2(33, -19)
#row 3 of Crystal Knight's swing is where the crescent is drawn
const SWING_FIRE_FRAME := 3
#The lit core in Crystal Knight's head, measured in its 64x64 cell. The phase 2
#beam leaves from there, so the point is read off the art rather than guessed. It sits
#on the sprite's centre line, so the facing flip never shifts it.
const HEAD_CELL := Vector2(32.0, 12.5)
const CELL_CENTRE := Vector2(32.0, 32.0)

@export_group("Identity")
@export var phase1_name : String = "The Crimson Sword"
@export var phase2_name : String = "Crystal Knight, Reborn"

@export_group("Activation")
@export var activation_range : float = 420.0
#Beyond this the fight resets - stops the boss trailing the player out of the arena
@export var leash_range : float = 1500.0

@export_group("Phase 1")
#A shade quicker than the player's 240. With no dash of its own this walk is the only
#way phase 1 closes a gap, so it has to win ground on someone backing off - the dodge
#roll is what the player buys distance with, not walking away.
@export var chase_speed : float = 265.0
#--- the slam: every direction at once ---------------------------------------
#The shockwave sprite is 52 art px across; at 3x that is a 78px radius on the ground
@export var slam_range : float = 92.0
@export var slam_radius : float = 78.0
@export var slam_damage : int = 44
#The dome is narrower than the shockwave, and only clips whoever stayed in it
@export var dome_radius : float = 62.0
@export var dome_damage : int = 26
@export var slam_recover : float = 0.6

#--- the spin: the ring around it, twice -------------------------------------
#Reaches further than the slam and covers every angle, so the band between the two is no
#longer a safe place to stand and wait. The answer is to be outside spin_radius when it
#starts, or to roll through the crescent - not to sidestep, which is the cleave's
#answer, and not to back off one step, which is the slam's.
@export var spin_radius : float = 165.0
#Half-width of the damaging wedge, in degrees
@export var spin_arc : float = 34.0
@export var spin_damage : int = 26
#Long enough to react to on sight. The aura draws a closing ring for all of it.
@export var spin_windup : float = 0.5
@export var spin_sweep_time : float = 1.0
@export var spin_revolutions : float = 2.0
#The payoff for baiting it out: the longest opening phase 1 gives up
@export var spin_recover : float = 0.75
@export var spin_cooldown : float = 4.5
#Only worth starting when the sweep can actually reach
@export var spin_trigger_range : float = 165.0

#--- the cleave: one direction, a long way ------------------------------------
#The lance streak runs 90 art px past the character and is drawn about 15 art px
#thick. Undoing the ground perspective the slam is drawn in (a circle of radius 26
#comes out 11 tall) turns that thickness into a band roughly 36 art px wide. At 3x:
#270 long, 54 either side of the line.
@export var cleave_reach : float = 270.0
@export var cleave_half_width : float = 54.0
@export var cleave_damage : int = 40
#The crescent that follows only reaches 29 art px past the character, but it wraps
#most of the way around it - a chip hit for anyone who dodged inside the lance
@export var sweep_radius : float = 90.0
@export var sweep_arc : float = 110.0
@export var sweep_damage : int = 20
#Committed from here out. The far end stops short of the lance itself so the boss
#never opens with a swing that lands short.
@export var cleave_min_range : float = 120.0
@export var cleave_max_range : float = 250.0
#The streak is only ever drawn along the sprite's own x, so the boss waits until the
#player is roughly level with it before committing - otherwise the lance would point
#past them. This is also the dodge: step north or south out of the band.
@export var cleave_band : float = 90.0
@export var cleave_recover : float = 0.45
@export var cleave_cooldown : float = 2.6

#--- getting parried ----------------------------------------------------------
#The punish window. Long on purpose: it has to buy two player swings (~0.45s each)
#and still leave time to walk back out of slam range before the boss picks up again.
@export var parry_stagger : float = 1.8

@export_group("Phase 2")
@export var beam_damage : int = 42
@export var beam_lifetime : float = 0.95
#How far past the head the beam starts, so it clears the face instead of drawing
#over it
@export var beam_muzzle : float = 18.0
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
@export var spin_aura : BossSpinAura
@export var arena_radius : float = 520.0

var phase : int = PHASE1
var act : int = Act.SLEEP
var _timer : float = 0.0
var _player : PlayerMain
var _origin : Vector2
var _aim : Vector2 = Vector2.RIGHT
var _last_move : int = -1               # phase 2 only, so it never repeats a move
var _fired : bool = false
var _fired2 : bool = false
var _volleys_left : int = 0
var _cleave_dir : Vector2 = Vector2.RIGHT
var _cleave_ready_at : float = 0.0
var _spin_from : float = 0.0
var _spin_ready_at : float = 0.0

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
	#Facing is locked through a cleave: the lance is drawn along the sprite's x and
	#the hitbox reads its direction off that, so a mid-swing flip would mirror the hit
	#away from the streak. A spin drives its own facing off the sweep instead.
	if act != Act.CLEAVE and act != Act.SPIN:
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
		Act.SPIN: _do_spin()
		Act.CLEAVE: _do_cleave()
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
	#Only phase 1 has a front to turn. Crystal Knight is drawn symmetrical and says
	#which way it is swinging with attack_l / attack_r instead - mirroring it as well
	#would cancel that out and bring the crescent down on the side away from the
	#player. Its beam and shards leave from the centre line, so nothing else notices.
	if phase != PHASE1:
		return
	var dir = -1.0 if flipped_horizontal else 1.0
	var size = absf(sprite.scale.x)
	sprite.scale.x = size * (dir if _to_player().x >= 0.0 else -dir)

func _enter(new_act : int, duration : float):
	#Every way out of a spin comes through here - recovery, a parry, the phase flip,
	#death - so this is the one place the whirl has to be taken off screen
	if new_act != Act.SPIN and spin_aura:
		spin_aura.finish()
	act = new_act
	_timer = duration
	_fired = false
	_fired2 = false

func _wear_phase1():
	sprite.sprite_frames = phase1_frames
	sprite.scale = Vector2(phase1_scale, phase1_scale)
	_apply_body(phase1_body)
	_play_narrow("idle")

#Every phase 1 animation is packed in 64px cells except the cleave, which needs the
#full 128 and rides its own sprite offset to stay anchored. Those two have to change
#in the same breath: drop the offset while a wide frame is still on screen and the
#drawing jumps 96px behind the boss until something finally plays a narrow one. Any
#exit out of the cleave goes through here.
func _play_narrow(anim : String):
	sprite.offset = phase1_offset
	sprite.play(anim)

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
	_play_narrow("walk")
	_enter(Act.CHASE, 0.0)

#Damage the player if it stands inside `radius` - the shape the slam draws.
func _hit_player(radius : float, damage : int):
	if not _alive_player():
		return
	var offset = _to_player()
	if offset.length() > radius:
		return
	_damage_player(damage, offset)

#The lance: a straight band down `dir`, the shape the streak draws. A little slack
#behind the boss covers the frame where the streak still overlaps its own body.
func _hit_player_band(dir : Vector2, reach : float, half_width : float, damage : int):
	if not _alive_player():
		return
	var offset = _to_player()
	var along = offset.dot(dir)
	if along < -12.0 or along > reach:
		return
	if absf(offset.cross(dir)) > half_width:
		return
	_damage_player(damage, offset)

#The sweep: a wedge of `half_angle` degrees either side of `dir`, out to `radius`.
func _hit_player_wedge(dir : Vector2, radius : float, half_angle : float, damage : int):
	if not _alive_player():
		return
	var offset = _to_player()
	if offset.length() > radius:
		return
	if offset != Vector2.ZERO and absf(rad_to_deg(offset.angle_to(dir))) > half_angle:
		return
	_damage_player(damage, offset)

#Honours the parry window - every hit above lands here, so a parry catches all of them
func _damage_player(damage : int, offset : Vector2):
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
	#Cleave is checked first because it is the pickier of the two mid-range moves -
	#letting the spin claim the whole band would mean the lance almost never comes out
	if _can_cleave(offset, distance):
		velocity = Vector2.ZERO
		_start_cleave()
		return
	if _can_spin(distance):
		velocity = Vector2.ZERO
		_start_spin()
		return

	if sprite.animation != "walk":
		_play_narrow("walk")
	velocity = offset.normalized() * chase_speed
	move_and_slide()

func _start_slam():
	_play_narrow("slam")
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

#The gap the other two moves leave: past the slam's reach, but not lined up for a lance
func _can_spin(distance : float) -> bool:
	if _now() < _spin_ready_at:
		return false
	return distance <= spin_trigger_range

func _start_spin():
	#The sweep starts on the far side and comes round to the player, rather than opening
	#on top of them. That buys half a revolution of travel the player can watch and react
	#to on top of the windup, which is the difference between a move you dodge on sight
	#and one you can only dodge by having memorised it.
	_spin_from = _to_player().angle() + PI
	_play_narrow("spin_up")
	if spin_aura:
		spin_aura.begin(spin_radius, spin_arc, _spin_from)
	_enter(Act.SPIN, spin_windup + spin_sweep_time)
	_spin_ready_at = _now() + spin_cooldown

#The one phase 1 move driven by a timer rather than by sprite.frame. The other two fire
#single hits on the frame that draws them, which is why they read their own animation;
#this one needs a sweep angle that is continuous, and its four ring frames loop
#underneath for however long spin_sweep_time is set to.
func _do_spin():
	var elapsed = (spin_windup + spin_sweep_time) - _timer

	if elapsed < spin_windup:
		if spin_aura:
			spin_aura.telegraph(elapsed / maxf(spin_windup, 0.001))
		return

	#One-shot, on the frame the windup ends: the loop below runs every frame after it
	if sprite.animation != "spin":
		_play_narrow("spin")
		GameManager.hitstop(0.04, 0.35)
		AudioManager.play_sound(AudioManager.PLAYER_ATTACK_SWING, 0.0, -2)

	var progress = clampf((elapsed - spin_windup) / maxf(spin_sweep_time, 0.001), 0.0, 1.0)
	var angle = _spin_from + TAU * spin_revolutions * progress
	var aim = Vector2.RIGHT.rotated(angle)

	if spin_aura:
		spin_aura.sweep(angle)
	_face_sweep(aim)
	#Standing in it is meant to hurt. The player's own i-frames are what keep this from
	#landing every physics frame, so one revolution is at most one hit.
	_hit_player_wedge(aim, spin_radius, spin_arc, spin_damage)

	if _timer <= 0.0:
		_play_narrow("idle")
		_enter(Act.RECOVER, spin_recover)

#Turning the boss to follow its own sweep is what sells four looping ring frames as one
#continuous swing rather than four poses on repeat
func _face_sweep(aim : Vector2):
	var dir = -1.0 if flipped_horizontal else 1.0
	var size = absf(sprite.scale.x)
	sprite.scale.x = size * (dir if aim.x >= 0.0 else -dir)

#Only worth swinging when the player is both far enough out for the lance to have
#somewhere to go and close enough to the boss's own line for the streak to point at
#them - the art draws it along the sprite's x and nowhere else.
func _can_cleave(offset : Vector2, distance : float) -> bool:
	if _now() < _cleave_ready_at:
		return false
	if distance < cleave_min_range or distance > cleave_max_range:
		return false
	return absf(offset.y) <= cleave_band

func _start_cleave():
	#Take the swing direction from the flip rather than from the player, so the band
	#below can only ever point where the streak is actually drawn
	_face_player()
	_cleave_dir = Vector2.RIGHT if sprite.scale.x >= 0.0 else Vector2.LEFT
	#Row 5 is packed as full-width cells; the character sits 33px off their centre
	sprite.offset = CLEAVE_CELL_OFFSET
	sprite.play("cleave")
	_enter(Act.CLEAVE, 0.0)
	_cleave_ready_at = _now() + cleave_cooldown

func _do_cleave():
	var frame = sprite.frame
	if not _fired and frame >= CLEAVE_LANCE_FRAME:
		_fired = true
		_hit_player_band(_cleave_dir, cleave_reach, cleave_half_width, cleave_damage)
		GameManager.hitstop(0.04, 0.3)
	if not _fired2 and frame >= CLEAVE_SWEEP_FRAME:
		_fired2 = true
		_hit_player_wedge(_cleave_dir, sweep_radius, sweep_arc, sweep_damage)
	if not sprite.is_playing():
		#idle, not just the offset - the last cleave frame is still a wide one
		_play_narrow("idle")
		_enter(Act.RECOVER, cleave_recover)

func _do_recover():
	#The stagger pose is two frames long; drop to idle once it has played so a parry
	#window isn't spent frozen on the last hurt frame
	if sprite.animation == "hurt" and not sprite.is_playing():
		_play_narrow("idle")
	if _timer > 0.0:
		return
	_play_narrow("walk")
	_enter(Act.CHASE, 0.0)

func _reset_fight():
	velocity = Vector2.ZERO
	if spin_aura:
		spin_aura.finish()
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
	#Half health can land mid-cleave, and "death" is packed in the narrow cells
	_play_narrow("death")
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
			_aim = _beam_aim()
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

#Where the beam leaves the boss: the lit core in Crystal Knight's head. The frame is
#drawn centred on `sprite.offset` at `phase2_scale`, so a cell coordinate converts
#straight through - retuning either export moves the muzzle along with the art.
func _head_point() -> Vector2:
	return global_position + (phase2_offset + HEAD_CELL - CELL_CENTRE) * phase2_scale

#Aimed from the head, not from the boss's feet. The beam's hitbox is the line it
#draws, so the two have to share an origin: aiming along the ground instead would
#leave the drawing hanging a head's height above everything it looks like it hits.
func _beam_aim() -> Vector2:
	if not _alive_player():
		return _aim
	var dir = (_player.global_position - _head_point()).normalized()
	return dir if dir != Vector2.ZERO else _aim

#The beam leaves on the last frame of the charge, and tracks until then
func _do_cast():
	if sprite.frame < sprite.sprite_frames.get_frame_count("cast") - 1:
		_aim = _beam_aim()
	if sprite.is_playing():
		return
	if beam_scene:
		var beam = beam_scene.instantiate()
		beam.direction = _aim
		beam.damage = beam_damage
		beam.lifetime = beam_lifetime
		beam.global_position = _head_point() + _aim * beam_muzzle
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
	if act == Act.TRANSITION or act == Act.DYING or act == Act.SLEEP:
		return
	super.apply_knockback(direction, force * 0.12, duration * 0.6)

#A parry staggers the boss out of whichever phase 1 swing it was in. Moving to RECOVER
#also drops the rest of that attack's hits - the slam's dome, the cleave's sweep, and
#every remaining degree of the spin - so the parry cancels the follow-up, not just the
#frame it caught.
func interrupt_attack():
	if act != Act.SLAM and act != Act.CLEAVE and act != Act.SPIN:
		return
	_play_narrow("hurt")
	#The cleave stays down past the stagger too, or the boss would answer the punish
	#with a 270px lance while the player is still backing off
	_cleave_ready_at = _now() + parry_stagger + cleave_cooldown * 0.5
	_enter(Act.RECOVER, parry_stagger)

func finished_attacking():
	pass

func _die():
	if is_dead:
		return
	is_dead = true
	act = Act.DYING
	velocity = Vector2.ZERO
	#Same as the transition: the killing blow can land mid-cleave
	if phase == PHASE1:
		_play_narrow("death")
	else:
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
