extends Node

#Attached to the death/victory screens
func _process(_delta):
	if Input.is_action_just_pressed("Restart"):
		restart()
	if Input.is_action_just_pressed("Escape"):
		get_tree().quit()
	if Input.is_action_just_pressed("Enter"):
		GameManager.load_next_level(load("res://Scenes/Levels/MainFloor.tscn")) #Hardcoded because export gave issues

func restart():
	GameManager.reset_money()
	GameManager.respawn_at_checkpoint()
