extends Node2D

#The outdoor levels are much bigger than the viewport, so the player camera has to be
#fenced in or it pans past the map edge and shows empty void.
@export var map_size : Vector2i = Vector2i(3840, 2400)

func _ready():
	_setup.call_deferred()

func _setup():
	var player = get_tree().get_first_node_in_group("Player")
	if !is_instance_valid(player):
		return
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = map_size.x
	camera.limit_bottom = map_size.y
	camera.reset_smoothing()
