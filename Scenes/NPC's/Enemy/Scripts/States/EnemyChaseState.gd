extends State
class_name enemy_chase_state

@export var attack_range := float(50)
@export var move_speed := float(65)

@export var animator : AnimationPlayer
@onready var body = $"../.."

func Enter():
	animator.play("Chasing")

func Update(_delta):
	if body.is_knockbacked:
		return

	var player = get_tree().get_first_node_in_group("Player") as CharacterBody2D
	if not is_instance_valid(player):
		state_transition.emit(self, "enemy_idle_state")
		return

	#global, not local: local only happens to match under a transformless parent
	var chase_direction = player.global_position - body.global_position as Vector2

	body.velocity = chase_direction.normalized() * move_speed
	body.move_and_slide()
	
	if(chase_direction.length() <= attack_range and body.can_attack()):
		state_transition.emit(self, "enemy_attack_state")
		
