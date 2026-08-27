extends State
class_name PlayerAttacking

#How long after an attack finishes the player can still chain into the next combo stage
@export var combo_window : float = 0.6

#Damage/knockback multipliers per combo stage (0 = first hit, last index = finisher)
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

	#call_deferred: emitting synchronously here fires while the FSM is still mid-way through
	#change_state() (current_state isn't us yet), so the transition gets dropped and we'd get stuck
	if(!player.has_stamina(current_attack.stamina_cost)):
		call_deferred("_abort_to_idle")
		return

	player.use_stamina(current_attack.stamina_cost)
	AudioManager.play_sound(AudioManager.PLAYER_ATTACK_SWING, 0.3, 1)

	#If we're outside the combo window since our last hit landed, start the chain over
	if Time.get_ticks_msec() - _last_hit_ms > combo_window * 1000:
		combo_stage = 0

	#Play the attack animation and wait for it to finish, transition from this state is handled by the animation player
	animator.play(current_attack.anim)
	await animator.animation_finished

	_last_hit_ms = Time.get_ticks_msec()
	combo_stage = 0 if combo_stage >= MAX_COMBO_STAGE else combo_stage + 1

	state_transition.emit(self, "Idle")

func _abort_to_idle():
	state_transition.emit(self, "Idle")

#Read which attack to use from our two attack nodes
func DetermineAttack():
	if(Input.is_action_just_pressed("Punch")):
		current_attack = attacks[0]
	elif(Input.is_action_just_pressed("Kick")):
		current_attack = attacks[1]

#Hitbox is turned on/off through the animationplayer, it an enemy is standing inside of it once that happens they take damage
#Both hitboxes call back to this function through signals
func _on_hitbox_body_entered(body):
	if body.is_in_group("Enemy"):
		deal_damage(body)
		AudioManager.play_sound(AudioManager.PLAYER_ATTACK_HIT, 0, 1)

func deal_damage(enemy : EnemyMain):
	hit_particles.emitting = true

	var damage_mult = COMBO_DAMAGE_MULT[combo_stage]
	var knockback_mult = COMBO_KNOCKBACK_MULT[combo_stage]

	enemy._take_damage(int(round(current_attack.damage * damage_mult)))

	var direction = enemy.global_position - player.global_position
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	enemy.apply_knockback(direction, current_attack.knockback_force * knockback_mult)

	GameManager.hitstop(current_attack.hitstop_duration)
