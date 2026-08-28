extends State
class_name enemy_attack_state

@export var attack : Attack_Data
@onready var enemy = $"../.."
@onready var hit_particles = $"../../AnimatedSprite2D/HitParticles"
@onready var hitbox_shape = $"../../AnimatedSprite2D/HitBox/CollisionShape2D"
@export var animator : AnimationPlayer

#DEBUG: telegraphs the hitbox window early - remove once parry timing is confirmed
@export var parry_indicator : CanvasItem
@export var hitbox_active_start : float = 0.5
@export var parry_telegraph_lead : float = 0.25
@export var parry_telegraph_duration : float = 0.2

#Bumped on start/cancel so a stale await can tell it's outdated
var _swing_id : int = 0

func Enter():
	_swing_id += 1
	var swing_id = _swing_id

	animator.play(attack.anim)
	_run_parry_telegraph(swing_id)
	await animator.animation_finished

	if swing_id != _swing_id:
		return

	enemy.finished_attacking()

func _run_parry_telegraph(swing_id : int):
	if not parry_indicator:
		return

	var lead_start = max(hitbox_active_start - parry_telegraph_lead, 0.0)
	await get_tree().create_timer(lead_start).timeout
	if swing_id != _swing_id:
		return
	parry_indicator.visible = true

	await get_tree().create_timer(parry_telegraph_duration).timeout
	if swing_id != _swing_id:
		return
	parry_indicator.visible = false

#Called on parry - re-disables the hitbox mid-swing
func cancel():
	_swing_id += 1
	hitbox_shape.set_deferred("disabled", true)
	if parry_indicator:
		parry_indicator.visible = false

#FSM-state check guards against hitbox/animation desync
func _on_hit_box_body_entered(body):
	if body.is_in_group("Player") and enemy.fsm.current_state == self:
		deal_damage_to_player(body)

func deal_damage_to_player(player : PlayerMain):
	if player.try_parry(enemy):
		return

	hit_particles.emitting = true
	player._take_damage(attack.damage)

func play_hitground_sound():
	AudioManager.play_sound(AudioManager.ENEMY_HIT, 0, -10)
