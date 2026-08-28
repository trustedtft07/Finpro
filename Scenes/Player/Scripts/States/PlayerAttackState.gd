extends State
class_name PlayerAttacking

#Combo chain window after the attack finishes
@export var combo_window : float = 0.6

#Per combo stage: 0=first hit, last=finisher
const COMBO_DAMAGE_MULT : Array[float] = [1.0, 1.15, 1.5]
const COMBO_KNOCKBACK_MULT : Array[float] = [1.0, 1.2, 2.0]
const COMBO_LABEL : Array[String] = ["COMBO 1", "COMBO 2", "FINISHER!"]
const COMBO_COLOR : Array[Color] = [Color(1, 1, 1), Color(1, 0.85, 0.35), Color(1, 0.45, 0.2)]
const MAX_COMBO_STAGE := 2

#Shows which combo stage just landed - the multipliers above are invisible without it
@export var combo_text : Label

@export var animator : AnimationPlayer
var current_attack : Attack_Data
@export var attacks : Array[Attack_Data]

var combo_stage : int = 0
var _last_hit_ms : int = -999999

@onready var hit_particles = $"../../AnimatedSprite2D/HitParticles"
@onready var fsm = $".." as FiniteStateMachine
var player : PlayerMain

func Enter():
	player = get_tree().get_first_node_in_group("Player") as PlayerMain
	DetermineAttack()

	#Only reachable if something enters this state without a fresh Punch/Kick press
	if(!current_attack):
		call_deferred("_abort_to_idle")
		return

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

#Hitbox toggled by the animation player, both hitboxes route here via signals.
#FSM-state check guards against hitbox/animation desync: dying mid-swing replaces the
#animation, so the track that re-disables the hitbox never runs and the corpse would
#keep dealing damage.
func _on_hitbox_body_entered(body):
	if body.is_in_group("Enemy") and fsm.current_state == self:
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

	_show_combo_text(combo_stage)
	#Later stages land harder, so the freeze-frame leans on them too
	GameManager.hitstop(current_attack.hitstop_duration * damage_mult)

func _show_combo_text(stage : int):
	if(!combo_text):
		return

	combo_text.text = COMBO_LABEL[stage]
	combo_text.modulate = COMBO_COLOR[stage]
	combo_text.scale = Vector2(0.6, 0.6)

	var tween = create_tween()
	tween.tween_property(combo_text, "scale", Vector2(1.0 + stage * 0.15, 1.0 + stage * 0.15), 0.08).set_trans(Tween.TRANS_BACK)
	tween.tween_interval(0.3)
	tween.tween_property(combo_text, "modulate:a", 0.0, 0.25)
