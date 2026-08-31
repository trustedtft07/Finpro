extends State
class_name PlayerWalking

#Walking, and nothing else. The dodge roll used to live in here as a "dashspeed" added
#on top of the walk - see PlayerRollState for why it moved out.
#
#Velocity is ramped rather than assigned. Snapping straight to full speed and straight
#back to zero is what made the character read as a cursor being dragged around; a short
#ramp (about four physics frames each way) keeps the response instant but gives starts,
#stops and direction changes some weight.

@export var movespeed := float(240)
#Time to full speed is movespeed / acceleration - keep these in proportion when retuning
@export var acceleration := float(3400)
@export var friction := float(4200)

@export var animator : AnimationPlayer
@onready var player : PlayerMain = $"../.."

func Enter():
	animator.play("Walk")

func Update(delta : float):
	#CharacterBase drives the body itself while knockback is active
	if player.is_knockbacked:
		return

	var input_dir = Input.get_vector("MoveLeft", "MoveRight", "MoveUp", "MoveDown")
	_drive(input_dir, delta)

	#Peek, don't claim: the state being handed to spends the press, so it survives the
	#change_state() in between
	if player.peek_input(["Dash"]):
		state_transition.emit(self, "Rolling")
		return

	if player.peek_input(["Punch", "Kick"]):
		state_transition.emit(self, "Attacking")
		return

	if player.peek_input(["Heal"]):
		state_transition.emit(self, "Healing")
		return

	if player.peek_input(["Parry"]):
		state_transition.emit(self, "Parrying")
		return

	#Coast to a stop in here rather than handing over on the release frame - Idle never
	#calls move_and_slide(), so leaving early would stop the character dead
	if(input_dir == Vector2.ZERO and player.velocity.length() <= 1.0):
		state_transition.emit(self, "Idle")

func _drive(input_dir : Vector2, delta : float):
	if(input_dir != Vector2.ZERO):
		player.set_facing_direction(input_dir)
		player.velocity = player.velocity.move_toward(input_dir * movespeed, acceleration * delta)
	else:
		player.velocity = player.velocity.move_toward(Vector2.ZERO, friction * delta)

	player.move_and_slide()
