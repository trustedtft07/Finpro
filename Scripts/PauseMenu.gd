extends CanvasLayer

#The scene root sets process_mode to ALWAYS so this keeps polling while the tree is paused
@export var panel : Control

#load(), not preload(): this scene lives inside Player.tscn, which MainFloor instances,
#so preloading it here would make the two scenes cyclically depend on each other
const MAIN_FLOOR_PATH = "res://Scenes/Levels/MainFloor.tscn"

var player : PlayerMain

func _ready():
	panel.visible = false

func _process(_delta):
	if Input.is_action_just_pressed("Escape"):
		#Closing always works - only opening is blocked, so a pause can never get stuck
		if get_tree().paused:
			set_paused(false)
		elif !_player_is_dead():
			#The death screen owns Escape once the player is down
			set_paused(true)
		return

	if !get_tree().paused:
		return

	#Unpause before any scene change, or the next scene loads frozen
	if Input.is_action_just_pressed("Restart"):
		set_paused(false)
		GameManager.reset_money()
		GameManager.respawn_at_checkpoint()
	elif Input.is_action_just_pressed("Enter"):
		set_paused(false)
		GameManager.reset_run()
		GameManager.load_next_level(load(MAIN_FLOOR_PATH))
	elif Input.is_action_just_pressed("QuitGame"):
		set_paused(false)
		get_tree().quit()

func set_paused(value : bool):
	get_tree().paused = value
	panel.visible = value

func _player_is_dead() -> bool:
	if !is_instance_valid(player):
		player = get_tree().get_first_node_in_group("Player") as PlayerMain
	return is_instance_valid(player) and player.is_dead
