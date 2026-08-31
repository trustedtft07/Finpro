extends State
class_name PlayerWalking

#Velocity is ramped rather than assigned - snapping to full speed and back to zero is
#what made the character read as a cursor being dragged around.

@export var movespeed := float(240)
#Time to full speed is movespeed / acceleration - keep these in proportion when retuning
@export var acceleration := float(3400)
@export var friction := float(4200)

@export var animator : AnimationPlayer
@onready var player : PlayerMain = $"../.."

func Enter():
	animator.play("Walk")

func Update(delta : float):
	if player.is_knockbacked:
		return

	var input_dir = Input.get_vector("MoveLeft", "MoveRight", "MoveUp", "MoveDown")
	_drive(input_dir, delta)

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

	#Coast to a stop in here - Idle never calls move_and_slide(), so handing over on the
	#release frame would stop the character dead
	if(input_dir == Vector2.ZERO and player.velocity.length() <= 1.0):
		state_transition.emit(self, "Idle")

func _drive(input_dir : Vector2, delta : float):
	if(input_dir != Vector2.ZERO):
		player.set_facing_direction(input_dir)
		#Scaling the target rather than the ramp: stepping into a bush should bleed speed
		#off against friction, not change how sharply the character answers the stick
		var target = input_dir * movespeed * player.move_speed_scale()
		player.velocity = player.velocity.move_toward(target, acceleration * delta)
	else:
		player.velocity = player.velocity.move_toward(Vector2.ZERO, friction * delta)

	player.move_and_slide()
