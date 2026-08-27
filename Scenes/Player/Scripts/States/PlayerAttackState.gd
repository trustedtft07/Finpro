extends State
class_name PlayerAttacking

#Combo chain window after the attack finishes
@export var combo_window : float = 0.6

#Per combo stage: 0=first hit, last=finisher
const COMBO_DAMAGE_MULT : Array[float] = [1.0, 1.15, 1.5]
const COMBO_KNOCKBACK_MULT : Array[float] = [1.0, 1.2, 2.0]
const MAX_COMBO_STAGE := 2

@export var animator : AnimationPlayer
var current_attack : Attack_Data
@export var attacks : Array[Attack_Data]

var combo_stage : int = 0
var _last_hit_ms : int = -999999

@onready var hit_particles = $"../../AnimatedSprite2D/HitParticles"
var player : PlayerMain

func Enter():
	player = get_tree().get_first_node_in_group("Player") as PlayerMain
	DetermineAttack()

	#call_deferred: emitting now fires mid change_state() and gets dropped
	if(!player.has_stamina(current_attack.stamina_cost)):
		call_deferred("_abort_to_idle")
		return

	player.use_stamina(current_attack.stamina_cost)
	AudioManager.play_sound(AudioManager.PLAYER_ATTACK_SWING, 0.3, 1)

	if Time.get_ticks_msec() - _last_hit_ms > combo_window * 1000:
		combo_stage = 0

	#Transition happens via the animation player
	animator.play(current_attack.anim)
	await animator.animation_finished

	_last_hit_ms = Time.get_ticks_msec()
	combo_stage = 0 if combo_stage >= MAX_COMBO_STAGE else combo_stage + 1

	state_transition.emit(self, "Idle")

func _abort_to_idle():
	state_transition.emit(self, "Idle")

func DetermineAttack():
	if(Input.is_action_just_pressed("Punch")):
		current_attack = attacks[0]
	elif(Input.is_action_just_pressed("Kick")):
		current_attack = attacks[1]

#Hitbox toggled by the animation player, both hitboxes route here via signals
func _on_hitbox_body_entered(body):
	if body.is_in_group("Enemy"):
		deal_damage(body)
		AudioManager.play_sound(AudioManager.PLAYER_ATTACK_HIT, 0, 1)

func deal_damage(enemy : EnemyMain):
	hit_particles.emitting = true

	var damage_mult = COMBO_DAMAGE_MULT[combo_stage]
	var knockback_mult = COMBO_KNOCKBACK_MULT[combo_stage]

	var was_dead = enemy.is_dead
	enemy._take_damage(int(round(current_attack.damage * damage_mult)))
	if(!was_dead && enemy.is_dead):
		player.restore_mana_on_kill()

	var direction = enemy.global_position - player.global_position
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	enemy.apply_knockback(direction, current_attack.knockback_force * knockback_mult)

	GameManager.hitstop(current_attack.hitstop_duration)
