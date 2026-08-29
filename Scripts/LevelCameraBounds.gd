extends Node2D

#Used by the large outdoor levels. They are much bigger than the viewport, so the
#player camera has to be fenced in - without limits it pans past the map edge and
#shows empty void.
@export var map_size : Vector2i = Vector2i(3840, 2400)

var _camera : Camera2D
#The HUD lives under the camera node, so once the camera clamps against a limit the
#view centre stops matching the node position and the bars drift off screen. Shift
#them back by whatever the clamp took away.
var _hud : Array[Control] = []
var _hud_home : Array[Vector2] = []

func _ready():
	_setup.call_deferred()

func _setup():
	var player = get_tree().get_first_node_in_group("Player")
	if !is_instance_valid(player):
		return
	_camera = player.get_node_or_null("Camera2D") as Camera2D
	if _camera == null:
		return
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = map_size.x
	_camera.limit_bottom = map_size.y
	_camera.reset_smoothing()
	for child in _camera.get_children():
		if child is Control:
			_hud.append(child)
			_hud_home.append(child.position)

func _process(_delta):
	if _camera == null or !is_instance_valid(_camera):
		return
	var shift = (_camera.get_screen_center_position() - _camera.global_position) / _camera.scale
	for i in _hud.size():
		_hud[i].position = _hud_home[i] + shift
