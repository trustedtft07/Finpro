extends State
class_name PlayerRolling

#The dodge roll.
#
#It used to be part of the walk state: a "dashspeed" that decayed on top of the normal
#walk velocity. That version could not be started from a standstill, cancelled itself
#the instant the movement key was released or nudged sideways, and had no fixed length -
#so the i-frames and the distance covered never lined up the same way twice.
#
#Here the roll is committed the frame it starts. Direction, distance and i-frames are
#all fixed in Enter() and nothing during the roll can shorten them, which is what makes
#it something a player can learn to time against an incoming swing.

@export var roll_speed : float = 700.0
@export var roll_duration : float = 0.34
#Measured from the start of the roll, and deliberately shorter than it: the tail is a
#real recovery window an enemy can punish
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
	#Claimed here rather than by whichever state sent us, so a roll that can't start
	#doesn't leave the press in the buffer to fire again next frame
	player.claim_input(["Dash"])
	_rolling = false

	#call_deferred: emitting now fires mid change_state() and gets dropped
	if(!player.has_stamina(stamina_cost)):
		call_deferred("_abort_to_idle")
		return

	#Roll where the player is steering, or straight ahead from a standstill
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

	#CharacterBase drives the body itself while knockback is active
	if(!player.is_knockbacked):
		player.velocity = _direction * roll_speed * _speed_curve()
		player.move_and_slide()

	if(_elapsed < roll_duration):
		return

	_finish()

#Rolling into the next action is the whole point of the move, so the buffer is read the
#instant the roll is over instead of after a detour through Idle
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

#Full speed for the first stretch, then eased down so the roll settles into a step
#instead of stopping dead against nothing
func _speed_curve() -> float:
	var t = _elapsed / roll_duration
	if(t <= speed_hold):
		return 1.0

	var tail = (t - speed_hold) / (1.0 - speed_hold)
	return maxf(1.0 - tail * tail, 0.12)

func _abort_to_idle():
	state_transition.emit(self, "Idle")
