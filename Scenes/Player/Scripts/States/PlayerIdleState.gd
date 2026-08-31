extends State
class_name PlayerIdle

@export var animator : AnimationPlayer
@onready var player : PlayerMain = $"../.."

func Enter():
	#Moving coasts to a halt before handing over, so there is nothing left to shed here
	player.velocity = Vector2.ZERO
	animator.play("Idle")

func Update(_delta : float):
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

	if(Input.get_vector("MoveLeft", "MoveRight", "MoveUp", "MoveDown") != Vector2.ZERO):
		state_transition.emit(self, "Moving")
