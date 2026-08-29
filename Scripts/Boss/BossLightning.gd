extends Node2D
class_name BossLightning

#One bolt of the phase 2 storm. It paints a circle on the ground first and only
#strikes once that circle has closed, so the hit is always dodgeable on reaction.

@export var bolt_sprite : AnimatedSprite2D
@export var radius : float = 46.0
@export var strike_flash : float = 0.18

var warn_time : float = 0.9
var damage : int = 40

var _elapsed : float = 0.0
var _struck : bool = false

func _ready():
	if bolt_sprite:
		bolt_sprite.visible = false
	z_index = -1        # the ground marker belongs under the characters

func _process(delta):
	if _struck:
		return
	_elapsed += delta
	queue_redraw()
	if _elapsed >= warn_time:
		_strike()

func _draw():
	if _struck:
		return
	var t = clampf(_elapsed / maxf(warn_time, 0.001), 0.0, 1.0)
	#Pool of danger, then a ring closing in on the impact point
	draw_circle(Vector2.ZERO, radius, Color(0.95, 0.35, 0.2, 0.18))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(1.0, 0.62, 0.25, 0.75), 2.0, true)
	draw_arc(Vector2.ZERO, maxf(radius * (1.0 - t), 1.0), 0.0, TAU, 40,
			Color(1.0, 0.9, 0.55, 0.95), 3.0, true)

func _strike():
	_struck = true
	queue_redraw()
	z_index = 1
	if bolt_sprite:
		bolt_sprite.visible = true
		bolt_sprite.play("lightning")
	_damage_player()
	AudioManager.play_sound(AudioManager.ENEMY_HIT, 0, -6)
	var tween = create_tween()
	tween.tween_interval(0.55)
	tween.tween_callback(queue_free)

func _damage_player():
	var player = get_tree().get_first_node_in_group("Player") as PlayerMain
	if not is_instance_valid(player) or player.is_dead:
		return
	if player.global_position.distance_to(global_position) > radius:
		return
	if player.parry_active:
		return
	player._take_damage(damage)
	player.apply_knockback(Vector2.DOWN, 200.0, 0.14)
