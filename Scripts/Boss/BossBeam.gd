extends Node2D
class_name BossBeam

#The phase 2 "kamehameha": a wide beam locked to the direction the boss was aiming
#when it finished charging. It stops at the first wall so it never crosses the arena
#edge, and ticks damage while the player stands in it.

@export var beam_sprite : Sprite2D
@export var width : float = 46.0
@export var max_length : float = 1200.0
@export var art_length : float = 80.0
@export var fade_in : float = 0.1
@export var fade_out : float = 0.22
#Standing in the beam for its whole life should cost about two hits, not four
@export var tick : float = 0.5

var direction : Vector2 = Vector2.RIGHT
var damage : int = 46
var lifetime : float = 0.95

var _length : float = 0.0
var _age : float = 0.0
var _tick_timer : float = 0.0
var _dying : bool = false

var _started : bool = false

#Set up on the first physics frame, not in _ready(): the spawner may still be placing
#this node, and the wall raycast needs the final position to measure against.
func _start():
	_started = true
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	direction = direction.normalized()
	#Local +Y runs along the beam, so the art (drawn tip-up) points down the beam
	rotation = direction.angle() - PI * 0.5
	_length = _measure_length()
	if beam_sprite:
		beam_sprite.scale.y = _length / art_length
		beam_sprite.modulate.a = 0.0
	_tick_timer = 0.0

func _measure_length() -> float:
	var space = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(
		global_position, global_position + direction * max_length)
	query.collision_mask = 1        # World only
	query.collide_with_areas = false
	var hit = space.intersect_ray(query)
	if hit.is_empty():
		return max_length
	return maxf(global_position.distance_to(hit.position), 60.0)

func _physics_process(delta):
	if not _started:
		_start()
	_age += delta

	if beam_sprite and not _dying:
		beam_sprite.modulate.a = minf(_age / maxf(fade_in, 0.001), 1.0)

	if _age >= lifetime and not _dying:
		_dying = true
		var tween = create_tween()
		tween.tween_property(beam_sprite, "modulate:a", 0.0, fade_out)
		tween.tween_callback(queue_free)
		return
	if _dying:
		return

	_tick_timer -= delta
	if _tick_timer > 0.0:
		return
	_tick_timer = tick
	_try_hit()

func _try_hit():
	var player = get_tree().get_first_node_in_group("Player") as PlayerMain
	if not is_instance_valid(player) or player.is_dead:
		return
	#Beam space: x across the beam, y along it
	var local = (player.global_position - global_position).rotated(-rotation)
	if local.y < -8.0 or local.y > _length:
		return
	if absf(local.x) > width * 0.5:
		return
	if player.parry_active:
		return
	player._take_damage(damage)
	player.apply_knockback(direction, 320.0, 0.2)
