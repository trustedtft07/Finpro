extends Node2D

#Used by the large outdoor levels. They are much bigger than the viewport, so the
#player camera has to be fenced in - without limits it pans past the map edge and
#shows empty void.
@export var map_size : Vector2i = Vector2i(3840, 2400)

func _ready():
	_setup.call_deferred()

#The HUD used to hang off the camera node, so clamping the view against a limit slid
#the bars off screen and every frame of camera movement shifted them a fraction of a
#pixel. It lives on its own CanvasLayer now (Player/HUD), which no camera transform can
#reach - so all this has left to do is set the limits.
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
