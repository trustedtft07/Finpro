extends State
class_name PlayerAttacking

#Melee. Two things in here decide how the combat reads:
#
#  - the swing runs off a timer measured against the animation's own length instead of
#    awaiting animation_finished. An await cannot be cancelled, so a swing that got cut
#    short left a coroutine alive that woke up inside whatever state came next and
#    dragged it back to Idle;
#  - from cancel_time onwards the next buffered press is honoured straight away. That is
#    the combo feel: three hits read as one chain instead of three separate swings each
#    waiting out its own recovery.

#How long after a swing a follow-up still counts as part of the same chain
@export var combo_window : float = 0.7

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

#Both melee hitboxes. Cleared on the way out because the animation tracks that re-disable
#them only fire if the animation is allowed to run to its end - cancelling into another
#move, or dying mid-swing, skips them and would leave a live hitbox attached.
@export var hitboxes : Array[CollisionShape2D]

var combo_stage : int = 0
var _last_hit_ms : int = -999999
var _elapsed : float = 0.0
var _length : float = 0.0
var _lunge : float = 0.0
var _lunge_dir : Vector2 = Vector2.RIGHT
var _swinging : bool = false

@onready var hit_particles = $"../../AnimatedSprite2D/HitParticles"
@onready var fsm = $".." as FiniteStateMachine
@onready var player : PlayerMain = $"../.."

func Enter():
	_swinging = false
	current_attack = _attack_for(player.claim_input(["Punch", "Kick"]))

	#Only reachable if something enters this state without a fresh Punch/Kick press
	if(!current_attack):
		call_deferred("_abort_to_idle")
		return

	#call_deferred: emitting now fires mid change_state() and gets dropped
	if(!player.has_stamina(current_attack.stamina_cost)):
		call_deferred("_abort_to_idle")
		return

	if Time.get_ticks_msec() - _last_hit_ms > combo_window * 1000:
		combo_stage = 0

	#Swings land where the player is steering, not where the last step happened to leave
	#the character pointing
	var input_dir = Input.get_vector("MoveLeft", "MoveRight", "MoveUp", "MoveDown")
	if(input_dir != Vector2.ZERO):
		player.set_facing_direction(input_dir)

	player.use_stamina(current_attack.stamina_cost)
	AudioManager.play_sound(AudioManager.PLAYER_ATTACK_SWING, 0.3, 1)

	animator.play(current_attack.anim)
	_length = _anim_length(current_attack.anim)
	_elapsed = 0.0
	_lunge_dir = player.facing_direction
	_lunge = current_attack.lunge_speed
	_swinging = true

func Exit():
	_swinging = false
	_disable_hitboxes()

func Update(delta : float):
	if(!_swinging):
		return

	_elapsed += delta
	_step_lunge(delta)

	if(_elapsed < current_attack.cancel_time):
		return

	#Chaining, rolling or parrying out of the recovery all beat standing there watching
	#the swing play itself out
	if player.peek_input(["Punch", "Kick"]):
		_close_swing()
		state_transition.emit(self, "Attacking")
		return

	if player.peek_input(["Dash"]):
		_close_swing()
		state_transition.emit(self, "Rolling")
		return

	if player.peek_input(["Parry"]):
		_close_swing()
		state_transition.emit(self, "Parrying")
		return

	if(_elapsed < _length):
		return

	_close_swing()
	#Straight back into the walk if a direction is held, so a combo doesn't drop the
	#character into a standstill between swings
	var moving = Input.get_vector("MoveLeft", "MoveRight", "MoveUp", "MoveDown") != Vector2.ZERO
	state_transition.emit(self, "Moving" if moving else "Idle")

#A swing counts as spent once it is over or cancelled out of, whether or not it connected
func _close_swing():
	_swinging = false
	_last_hit_ms = Time.get_ticks_msec()
	combo_stage = 0 if combo_stage >= MAX_COMBO_STAGE else combo_stage + 1

#A short shove behind the swing. Small on purpose: enough to give the hit weight and
#close the last few pixels of a whiff, not enough to be a movement option.
func _step_lunge(delta : float):
	if(_lunge <= 0.0 or player.is_knockbacked):
		return

	player.velocity = _lunge_dir * _lunge
	player.move_and_slide()
	_lunge = move_toward(_lunge, 0.0, current_attack.lunge_decel * delta)
	if(_lunge <= 0.0):
		player.velocity = Vector2.ZERO

func _attack_for(action : String) -> Attack_Data:
	match action:
		"Punch":
			return attacks[0]
		"Kick":
			return attacks[1]
	return null

func _anim_length(anim : String) -> float:
	var animation = animator.get_animation(anim)
	return animation.length if animation else 0.45

func _disable_hitboxes():
	for hitbox in hitboxes:
		if is_instance_valid(hitbox):
			hitbox.set_deferred("disabled", true)

func _abort_to_idle():
	state_transition.emit(self, "Idle")

#Hitbox toggled by the animation player, both hitboxes route here via signals.
#FSM-state check guards against hitbox/animation desync: dying mid-swing replaces the
#animation, so the track that re-disables the hitbox never runs and the corpse would
#keep dealing damage.
func _on_hitbox_body_entered(body):
	if body.is_in_group("Enemy") and fsm.current_state == self and _swinging:
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
