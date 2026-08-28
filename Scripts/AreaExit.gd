extends Area2D

@onready var label = $Label
@export var next_scene : PackedScene

func _ready():
	label.visible = false

func _process(_delta):
	if(Input.is_action_just_pressed("Enter") and label.visible == true and _player_is_alive()):
		GameManager.load_next_level(next_scene)

#Dying inside the exit would otherwise race the death screen, which binds 'E' to
#restarting - both would fire on the same frame and fight over the scene change
func _player_is_alive() -> bool:
	var player = get_tree().get_first_node_in_group("Player") as CharacterBase
	return is_instance_valid(player) and not player.is_dead

func _on_body_entered(body):
	if body.is_in_group("Player"):
		label.visible = true

func _on_body_exited(body):
	if body.is_in_group("Player"):
		label.visible = false
