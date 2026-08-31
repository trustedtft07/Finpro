extends State
class_name PlayerRolling

#Direction, distance and i-frames are all fixed in Enter() and nothing during the roll
#can shorten them - that is what makes it something a player can time against a swing.

@export var roll_speed : float = 700.0
@export var roll_duration : float = 0.34
#Shorter than the roll on purpose: the tail is a recovery window an enemy can punish
@export var iframe_duration : float = 0.24
@export var stamina_cost : float = 22.0
#Fraction of the roll held at full speed before it eases out
@export var speed_hold : float = 0.55

@export var animator : AnimationPlayer
@onready var player : PlayerMain = $"../.."

var _direction : Vector2 = Vector2.RIGHT
var _elapsed : float = 0.0
var _rolling : bool = false

func Enter():
	#Claimed here so a roll that can't start doesn't leave the press to fire next frame
	player.claim_input(["Dash"])
	_rolling = false

	#call_deferred: emitting now fires mid change_state() and gets dropped
	if(!player.has_stamina(stamina_cost)):
		call_deferred("_abort_to_idle")
		return

	var input_dir = Input.get_vector("MoveLeft", "MoveRight", "MoveUp", "MoveDown")
	_direction = input_dir.normalized() if input_dir != Vector2.ZERO else player.facing_direction
	player.set_facing_direction(_direction)

	player.use_stamina(stamina_cost)
	player.dodge_invincible = true
	AudioManager.play_sound(AudioManager.PLAYER_ATTACK_SWING, 0.3, -1)
	animator.play("Dash")

	_elapsed = 0.0
	_rolling = true

func Exit():
	_rolling = false
	player.dodge_invincible = false

func Update(delta : float):
	if(!_rolling):
		return

	_elapsed += delta
	if(_elapsed >= iframe_duration):
		player.dodge_invincible = false

	if(!player.is_knockbacked):
		player.velocity = _direction * roll_speed * _speed_curve()
		player.move_and_slide()

	if(_elapsed < roll_duration):
		return

	_finish()

#Rolling into the next action is the point of the move, so the buffer is read the
#instant the roll ends instead of after a detour through Idle
func _finish():
	_rolling = false

	if player.peek_input(["Punch", "Kick"]):
		state_transition.emit(self, "Attacking")
	elif player.peek_input(["Parry"]):
		state_transition.emit(self, "Parrying")
	elif player.peek_input(["Dash"]):
		state_transition.emit(self, "Rolling")
	elif Input.get_vector("MoveLeft", "MoveRight", "MoveUp", "MoveDown") != Vector2.ZERO:
		state_transition.emit(self, "Moving")
	else:
		state_transition.emit(self, "Idle")

#Full speed, then eased down so the roll settles into a step instead of stopping dead
func _speed_curve() -> float:
	var t = _elapsed / roll_duration
	if(t <= speed_hold):
		return 1.0

	var tail = (t - speed_hold) / (1.0 - speed_hold)
	return maxf(1.0 - tail * tail, 0.12)

func _abort_to_idle():
	state_transition.emit(self, "Idle")
